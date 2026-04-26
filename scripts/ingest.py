#!/usr/bin/env python3
"""silva-omnium ingest pipeline.

Walks raw/, finds new/changed files vs ingested.json, asks the configured
LLM provider to synthesize them into wiki/, applies the returned change
atomically. Providers do not touch disk; this script is the only writer.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
from scripts.llm_providers import ProviderError, get_provider  # noqa: E402

RAW_DIR = REPO_ROOT / "raw"
WIKI_DIR = REPO_ROOT / "wiki"
META_DIR = WIKI_DIR / "_meta"
CATEGORIES_PATH = META_DIR / "categories.yaml"
INGESTED_PATH = META_DIR / "ingested.json"
PROMPT_TEMPLATE_PATH = REPO_ROOT / "scripts" / "ingest_prompt.md"

CATEGORIES_HEADER = (
    "# Claude/Ollama 가 ingest 중 append. 수동 편집·리네이밍 가능.\n"
    "# 형식:\n"
    "#   <slug>:\n"
    "#     title: 사람이 읽는 이름\n"
    "#     description: 한 줄 설명\n"
    "#     created: YYYY-MM-DD\n"
)

EXCLUDED_WIKI_PREFIXES = ("wiki/_meta/", "wiki/.obsidian/", "wiki/_attachments/")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def raw_id_of(rel_path: str) -> str:
    s = rel_path
    if s.startswith("raw/"):
        s = s[4:]
    if s.endswith(".md"):
        s = s[:-3]
    return s.replace("/", "-")


def atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def load_ingested() -> dict[str, Any]:
    if not INGESTED_PATH.exists():
        return {"version": 1, "entries": {}}
    return json.loads(INGESTED_PATH.read_text("utf-8"))


def save_ingested(data: dict[str, Any]) -> None:
    atomic_write_text(
        INGESTED_PATH,
        json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
    )


def load_categories() -> dict[str, Any]:
    if not CATEGORIES_PATH.exists():
        return {"categories": {}}
    parsed = yaml.safe_load(CATEGORIES_PATH.read_text("utf-8"))
    if not parsed or "categories" not in parsed:
        return {"categories": {}}
    return parsed


def save_categories(data: dict[str, Any]) -> None:
    body = yaml.safe_dump(
        data, allow_unicode=True, sort_keys=False, default_flow_style=False
    )
    atomic_write_text(CATEGORIES_PATH, CATEGORIES_HEADER + body)


def parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    fm_text = text[4:end]
    body = text[end + 5 :]
    fm = yaml.safe_load(fm_text) or {}
    return fm, body


def render_frontmatter(meta: dict[str, Any], body: str) -> str:
    fm = yaml.safe_dump(
        meta, allow_unicode=True, sort_keys=False, default_flow_style=False
    )
    body = body.lstrip("\n")
    return f"---\n{fm}---\n\n{body}"


def collect_raw_files() -> list[Path]:
    return sorted(p for p in RAW_DIR.rglob("*.md") if p.is_file())


def collect_existing_pages() -> list[dict[str, Any]]:
    pages = []
    for p in WIKI_DIR.rglob("*.md"):
        rel = p.relative_to(REPO_ROOT).as_posix()
        if any(rel.startswith(prefix) for prefix in EXCLUDED_WIKI_PREFIXES):
            continue
        try:
            fm, _ = parse_frontmatter(p.read_text("utf-8"))
        except Exception:
            fm = {}
        pages.append(
            {
                "path": rel,
                "title": fm.get("title") or p.stem,
                "aliases": fm.get("aliases") or [],
                "tags": fm.get("tags") or [],
            }
        )
    return pages


def diff_targets(args: argparse.Namespace, ingested: dict[str, Any]) -> list[Path]:
    entries = ingested.get("entries", {})
    targets = []
    for raw_path in collect_raw_files():
        rel = raw_path.relative_to(REPO_ROOT).as_posix()
        if args.only and rel != args.only:
            continue
        sha = sha256_of(raw_path)
        if (
            args.force
            or rel not in entries
            or entries[rel].get("sha256") != sha
        ):
            targets.append(raw_path)
    return targets


def render_prompt(
    template: str,
    raw_path: Path,
    categories: dict[str, Any],
    existing_pages: list[dict[str, Any]],
) -> str:
    rel = raw_path.relative_to(REPO_ROOT).as_posix()
    raw_id = raw_id_of(rel)
    raw_content = raw_path.read_text("utf-8")
    cats_map = categories.get("categories") or {}
    cats_yaml = (
        yaml.safe_dump(cats_map, allow_unicode=True, sort_keys=False).strip()
        or "(empty)"
    )

    if existing_pages:
        lines = []
        for p in existing_pages:
            extras = []
            if p["aliases"]:
                extras.append(f"aliases: [{', '.join(p['aliases'])}]")
            if p["tags"]:
                extras.append(f"tags: [{', '.join(p['tags'])}]")
            suffix = (" · " + " · ".join(extras)) if extras else ""
            lines.append(f"- {p['path']} · {p['title']}{suffix}")
        pages_text = "\n".join(lines)
    else:
        pages_text = "(none)"

    today = dt.date.today().isoformat()

    return (
        template.replace("{{RAW_PATH}}", rel)
        .replace("{{RAW_ID}}", raw_id)
        .replace("{{RAW_CONTENT}}", raw_content)
        .replace("{{EXISTING_CATEGORIES}}", cats_yaml)
        .replace("{{EXISTING_PAGES}}", pages_text)
        .replace("{{TODAY}}", today)
    )


def validate_response(resp: Any) -> str | None:
    if not isinstance(resp, dict):
        return "response is not a JSON object"
    if resp.get("action") not in ("new", "append"):
        return f"action must be 'new' or 'append', got {resp.get('action')!r}"
    target = resp.get("target_path", "")
    if not isinstance(target, str) or not target.startswith("wiki/") or not target.endswith(".md"):
        return f"target_path must be 'wiki/.../*.md', got {target!r}"
    if any(target.startswith(prefix) for prefix in EXCLUDED_WIKI_PREFIXES):
        return f"target_path must not be inside excluded dirs: {target}"
    if not resp.get("category_slug"):
        return "category_slug is required"
    if not resp.get("body"):
        return "body is required"
    return None


def apply_change(
    resp: dict[str, Any],
    raw_path: Path,
    categories: dict[str, Any],
    today: str,
) -> str:
    target_rel = resp["target_path"]
    target_path = REPO_ROOT / target_rel

    cats_map = categories.setdefault("categories", {}) or {}
    slug = resp["category_slug"]
    if slug not in cats_map and resp.get("category_title"):
        cats_map[slug] = {
            "title": resp["category_title"],
            "description": resp.get("category_description", ""),
            "created": today,
        }
        categories["categories"] = cats_map
        save_categories(categories)

    raw_rel = raw_path.relative_to(REPO_ROOT).as_posix()
    src_append = resp.get("src_append") or [raw_rel]
    body_section = resp["body"]

    if resp["action"] == "new" or not target_path.exists():
        meta: dict[str, Any] = {
            "title": resp.get("title") or target_path.stem,
            "aliases": resp.get("aliases") or [],
            "category": slug,
            "tags": resp.get("tags") or [],
            "src": src_append,
            "updated": today,
            "status": "draft",
        }
        meta = {k: v for k, v in meta.items() if v not in ([], None, "")}
        atomic_write_text(target_path, render_frontmatter(meta, body_section.strip() + "\n"))
    else:
        existing = target_path.read_text("utf-8")
        fm, body = parse_frontmatter(existing)
        src_list = list(fm.get("src") or [])
        for s in src_append:
            if s not in src_list:
                src_list.append(s)
        fm["src"] = src_list
        fm["updated"] = today
        if resp.get("tags"):
            tag_list = list(fm.get("tags") or [])
            for t in resp["tags"]:
                if t not in tag_list:
                    tag_list.append(t)
            fm["tags"] = tag_list
        new_body = body.rstrip() + "\n\n" + body_section.strip() + "\n"
        atomic_write_text(target_path, render_frontmatter(fm, new_body))

    return target_rel


def main() -> int:
    parser = argparse.ArgumentParser(description="silva-omnium ingest pipeline")
    parser.add_argument(
        "--provider", default="ollama", choices=["ollama", "claude"]
    )
    parser.add_argument(
        "--model", default=None, help="override default model for the provider"
    )
    parser.add_argument("--force", action="store_true", help="re-ingest all raw files")
    parser.add_argument(
        "--only", default=None, help="ingest only this raw path (relative to repo root)"
    )
    args = parser.parse_args()

    ingested = load_ingested()
    targets = diff_targets(args, ingested)
    if not targets:
        print("nothing to ingest")
        return 0

    provider_kwargs: dict[str, Any] = {}
    if args.model:
        provider_kwargs["model"] = args.model
    provider = get_provider(args.provider, **provider_kwargs)

    template = PROMPT_TEMPLATE_PATH.read_text("utf-8")
    categories = load_categories()

    failures = 0
    for raw_path in targets:
        rel = raw_path.relative_to(REPO_ROOT).as_posix()
        existing_pages = collect_existing_pages()
        prompt = render_prompt(template, raw_path, categories, existing_pages)
        print(f"[ingest] {rel} via {args.provider}", file=sys.stderr)
        try:
            resp = provider.synthesize(prompt)
            err = validate_response(resp)
            if err:
                raise ProviderError(f"invalid response: {err}")
            today = dt.date.today().isoformat()
            target_rel = apply_change(resp, raw_path, categories, today)
            ingested.setdefault("entries", {})[rel] = {
                "sha256": sha256_of(raw_path),
                "ingested_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                "wiki_pages": [target_rel],
                "provider": args.provider,
            }
            save_ingested(ingested)
            print(f"  → {target_rel} | {resp.get('summary', '')}")
        except ProviderError as exc:
            failures += 1
            print(f"  ! {rel} failed: {exc}", file=sys.stderr)

    print(f"done: {len(targets) - failures}/{len(targets)} ingested, {failures} failed")
    return failures


if __name__ == "__main__":
    sys.exit(main())
