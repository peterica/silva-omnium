# silva-omnium 풀스택 구축 플랜

## Context

`silva-omnium` 은 현재 skeleton 이다 — `raw/`, `wiki/`, `wiki/_meta/`, `scripts/` 디렉토리가 있지만 전부 비어 있고, `CLAUDE.md` 와 `README.md` 가 의도만 선언해 둔 상태다. 사용자의 원본 MD 를 Claude 가 읽어 영속 위키로 종합·카테고리 자동 분류·인용 연결·모순 탐지를 수행하는 Memex 를 실제로 동작시키려면, README 가 "예정"으로 나열한 5가지(ingest 파이프라인, frontmatter 스키마, Astro Starlight 웹 뷰, Obsidian vault 설정, Makefile)를 한 번에 이어 붙여 최소 동작 가능한 루프를 만들어야 한다.

이번 플랜은:

- **엔진**: `scripts/ingest.py` 가 `claude -p` 를 서브프로세스로 호출
- **분류**: emergent — `wiki/_meta/categories.yaml` 은 비어서 출발, Claude 가 새 raw 를 처리하며 카테고리를 제안·추가
- **범위**: ingest + Obsidian vault + Astro Starlight 풀스택

목표는 "사용자가 `raw/` 에 MD 를 떨어뜨리고 `make ingest` 를 돌리면 `wiki/<category>/<slug>.md` 가 생기고 `make dev` 로 브라우저에서 확인 가능" 까지.

## 아키텍처

```
  ┌─────────┐
  │ raw/*.md│  (사용자 Obsidian 저장 · Claude 읽기만)
  └────┬────┘
       │ sha256 diff vs _meta/ingested.json
       ▼
  ┌──────────────────┐       spawn       ┌──────────────┐
  │ scripts/ingest.py├──────────────────▶│  claude -p   │
  │  (Python 3.11)   │  prompt + context │  (CLI)       │
  └────────┬─────────┘                   └──────┬───────┘
           │                                    │ Read/Edit/Write
           │                                    ▼
           │                       ┌──────────────────────────┐
           │                       │ wiki/<category>/<slug>.md│
           │                       │ wiki/_meta/categories.yaml│
           │                       └────────────┬─────────────┘
           ▼                                    │
  wiki/_meta/ingested.json                      │
  (raw_path → sha256, ingested_at)              │
                                                ▼
                     ┌──────────────────────────────────────────┐
                     │              wiki/                       │
                     │  Obsidian vault 루트 (.obsidian/ 공유 설정) │
                     │  Astro Starlight content source          │
                     │    ↑ web/src/content/docs → symlink      │
                     └──────────────────────────────────────────┘
```

## 작업 순서 (feature 브랜치 `feat/bootstrap-pipeline` 에서)

### 1. Frontmatter 스키마 문서화

**파일 생성**: `wiki/_meta/schema.md`

모든 `wiki/**/*.md` 프론트매터는 다음을 따른다:

```yaml
---
title: string                 # 필수
aliases: [string]             # Obsidian alias + Starlight redirect
category: string              # _meta/categories.yaml 의 key 또는 신규
tags: [string]
src: [string]                 # raw/ 경로 배열 (e.g. raw/2026/04-24-foo.md)
updated: YYYY-MM-DD
status: draft | stable
---
```

인용 각주 형식: `[^src-<raw-id>]` — `raw-id` 는 raw 파일의 상대 경로에서 `raw/` 접두어와 `.md` 접미어를 제거하고 `/` → `-` 로 치환한 값. 예: `raw/2026/04-24-foo.md` → `[^src-2026-04-24-foo]`.

**파일 생성**: `wiki/_meta/categories.yaml`

```yaml
# Claude 가 ingest 중 append. 수동 편집·리네이밍 가능.
# 형식:
#   <slug>:
#     title: 사람이 읽는 이름
#     description: 한 줄 설명
#     created: YYYY-MM-DD
categories: {}
```

**파일 생성**: `wiki/_meta/ingested.json`

```json
{
  "version": 1,
  "entries": {}
}
```

`entries` 는 `{ "raw/path.md": { "sha256": "...", "ingested_at": "...", "wiki_pages": ["wiki/..."] } }` 형태. 스크립트가 읽고 씀.

### 2. Ingest 파이프라인

**파일 생성**: `scripts/ingest.py` (의존성 없음 — stdlib only, `hashlib`, `json`, `subprocess`, `pathlib`, `argparse`, `datetime`)

동작:

1. `raw/**/*.md` 순회. 각 파일의 sha256 계산.
2. `wiki/_meta/ingested.json` 과 비교해 **신규·변경** 파일 목록 산출 (`--force` 플래그로 전체 재처리 가능, `--only <path>` 로 단일 파일 처리 가능).
3. 처리할 파일이 없으면 "nothing to ingest" 로그 후 종료.
4. 각 대상 raw 에 대해:
    - `scripts/ingest_prompt.md` 템플릿을 읽어 `{{RAW_PATH}}`, `{{RAW_ID}}`, `{{RAW_CONTENT}}`, `{{EXISTING_CATEGORIES}}`, `{{EXISTING_PAGES}}` 치환.
        - `EXISTING_CATEGORIES`: `categories.yaml` 을 읽어 slug + title + description 목록으로 직렬화.
        - `EXISTING_PAGES`: `wiki/**/*.md` 을 glob 해 `path · title · aliases` 를 나열 (모순 탐지용). `_meta/**` 제외.
    - `subprocess.run(["claude", "-p", prompt, "--permission-mode", "acceptEdits", "--allowedTools", "Read,Edit,Write,Glob,Grep", "--add-dir", str(repo_root)], cwd=repo_root, check=True)`. CLAUDE.md 자동 디스커버리로 프로젝트 규칙이 로드된다.
    - 반환 후 sha256 과 `ingested_at` (ISO8601) 을 `ingested.json.entries[raw_path]` 에 기록. `wiki_pages` 는 해당 호출 전후 `git diff --name-only -- wiki/` 로 산출.
5. 전체 완료 후 `ingested.json` 을 atomic 쓰기 (`.tmp` → `rename`).

**정책**:
- 커밋하지 않는다 (CLAUDE.md 규칙). 파일만 수정.
- 실패하면 해당 raw 는 `ingested.json` 에 쓰지 않고 다음 파일로 진행. 종료 코드는 실패 수.

**파일 생성**: `scripts/ingest_prompt.md` — 템플릿. 핵심 지시:

1. `raw/` 를 **절대** 수정·삭제하지 말 것.
2. `{{RAW_CONTENT}}` 를 읽고 기존 wiki 페이지 (`{{EXISTING_PAGES}}`) 와 의미적으로 중복·관련되는 페이지가 있는지 판단.
    - 관련 없음 → 새 페이지 생성.
    - 관련 있고 동일 사실 확장 → 기존 페이지에 섹션 추가, `src:` 프론트매터에 `{{RAW_PATH}}` append.
    - 관련 있으나 기존 서술과 **모순** → 기존 페이지에 `> [!conflict]` callout 으로 명시, 병합하지 말 것.
3. 카테고리: `{{EXISTING_CATEGORIES}}` 중 맞는 게 있으면 재사용. 없으면 새 slug 제안하고 `wiki/_meta/categories.yaml` 의 `categories:` 맵에 `{slug: {title, description, created}}` 를 추가 (YAML 을 Read 후 Edit).
4. 신규 페이지 경로: `wiki/<category_slug>/<page_slug>.md`. 프론트매터는 schema.md 스펙 준수.
5. 모든 사실 진술 뒤에 `[^src-{{RAW_ID}}]` 각주를 붙이고, 페이지 하단에 `[^src-{{RAW_ID}}]: raw/...` 정의를 추가.
6. 마무리로 한 줄 요약을 stdout 에 출력 (어느 페이지를 어떻게 바꿨는지).

### 3. Makefile

**파일 생성**: `Makefile` (repo 루트)

```make
.PHONY: setup ingest ingest-force dev build clean

setup:
	cd web && npm install
	@test -e web/src/content/docs || (mkdir -p web/src/content && ln -s ../../../wiki web/src/content/docs)

ingest:
	python3 scripts/ingest.py

ingest-force:
	python3 scripts/ingest.py --force

dev:
	cd web && npm run dev

build:
	cd web && npm run build

clean:
	rm -rf web/node_modules web/dist web/.astro
```

### 4. Obsidian vault 설정

**파일 생성**: `wiki/.obsidian/app.json`

```json
{
  "alwaysUpdateLinks": true,
  "newLinkFormat": "shortest",
  "useMarkdownLinks": false,
  "attachmentFolderPath": "_attachments"
}
```

**파일 생성**: `wiki/.obsidian/appearance.json`

```json
{ "baseFontSize": 16 }
```

기존 `.gitignore` 가 `workspace.json`, `graph.json`, `cache` 등을 무시하므로 공유 가능한 부분만 커밋된다.

### 5. Astro Starlight 웹 뷰

수동 스캐폴드 (의존성 충돌·프롬프트 회피):

**파일 생성**: `web/package.json`

```json
{
  "name": "silva-omnium-web",
  "type": "module",
  "version": "0.0.1",
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview"
  },
  "dependencies": {
    "@astrojs/starlight": "^0.30.0",
    "astro": "^5.0.0",
    "sharp": "^0.33.0"
  }
}
```

**파일 생성**: `web/astro.config.mjs`

```js
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  integrations: [
    starlight({
      title: 'silva-omnium',
      description: '모든 것이 쌓이는 개인 숲',
      sidebar: [{ label: 'Home', link: '/' }, { label: 'Wiki', autogenerate: { directory: '.' } }],
    }),
  ],
});
```

**파일 생성**: `web/src/content.config.ts` — `_meta/**` 를 content collection 에서 제외.

```ts
import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({
    loader: docsLoader({ pattern: ['**/*.{md,mdx}', '!_meta/**'] }),
    schema: docsSchema(),
  }),
};
```

**파일 생성**: `web/tsconfig.json`

```json
{ "extends": "astro/tsconfigs/strict" }
```

**파일 생성**: `web/.gitignore`

```
node_modules/
dist/
.astro/
```

**심볼릭 링크**: `make setup` 이 `web/src/content/docs` → `../../../wiki` 를 만든다 (상대 경로 기준: `web/src/content/docs` 에서 `wiki/` 까지 `../../../wiki`). wiki 루트의 `index.md` 가 Starlight 홈이 된다.

### 6. `.gitignore` 보강

`web/` 무시는 `web/.gitignore` 로 처리. 루트 `.gitignore` 에 `ingested.json` 이 커밋되도록 (명시적으로 무시하지 않음 — 이미 포함되지 않음, 그대로 둠).

심볼릭 링크 `web/src/content/docs` 는 커밋하면 git 에 symlink 로 저장된다. 커밋한다 (재클론 시 `make setup` 없이도 구조 보존).

### 7. 기존 `wiki/index.md` 프론트매터 정렬

현재 `wiki/index.md` 의 프론트매터(`category: _root`)는 schema 와 충돌하지 않지만, `src: []`, `updated`, `status: stable` 필드를 추가해 스키마 준수 예시로 둔다. (간단한 Edit.)

## 변경·생성 파일 요약

| 파일 | 동작 |
|---|---|
| `wiki/_meta/schema.md` | 신규 |
| `wiki/_meta/categories.yaml` | 신규 |
| `wiki/_meta/ingested.json` | 신규 |
| `scripts/ingest.py` | 신규 |
| `scripts/ingest_prompt.md` | 신규 |
| `Makefile` | 신규 |
| `wiki/.obsidian/app.json` | 신규 |
| `wiki/.obsidian/appearance.json` | 신규 |
| `web/package.json` | 신규 |
| `web/astro.config.mjs` | 신규 |
| `web/src/content.config.ts` | 신규 |
| `web/tsconfig.json` | 신규 |
| `web/.gitignore` | 신규 |
| `web/src/content/docs` | symlink → `../../../wiki` (setup 시 생성) |
| `wiki/index.md` | 프론트매터 보강 |

raw/ 는 건드리지 않음. `.gitkeep` 들은 디렉토리가 실제 내용으로 채워진 뒤 각자 판단으로 정리 (wiki/_meta 는 schema.md 생기면 삭제).

## 검증 절차

1. `make setup` — `web/node_modules/` 설치, symlink 생성 확인.
2. `raw/2026/04-24-test.md` 에 짧은 테스트 원본을 떨어뜨린다 (예: "제습기 추천을 찾았다. 삼성 AX90 은 8평, LG OBJET 는 12평. LG 가 소음 낮음.").
3. `make ingest` — stdout 에 Claude 의 요약 한 줄이 찍히고, `wiki/<something>/test.md` 생성·`wiki/_meta/categories.yaml` 에 카테고리 추가·`wiki/_meta/ingested.json` 에 엔트리 추가를 `git status` 로 확인.
4. 생성된 wiki 페이지에 `[^src-2026-04-24-test]` 각주가 있고, 프론트매터 `src: [raw/2026/04-24-test.md]` 가 맞는지 확인.
5. 동일 raw 를 한 번 수정 후 `make ingest` 재실행 — sha 변경 감지되어 Claude 가 재처리하는지 확인.
6. 모순 유발 raw (예: "삼성이 더 조용함") 를 추가 → `make ingest` → 기존 페이지에 `> [!conflict]` callout 이 붙는지 확인.
7. `make dev` — Astro 가 `wiki/` 를 읽어 `http://localhost:4321` 에 페이지를 렌더. 좌측 사이드바에 자동 생성된 트리가 보이고 `_meta/` 는 나오지 않아야 한다.
8. `make build` — `web/dist/` 가 생성되고 빌드 에러 없음.
9. Obsidian 에서 `wiki/` 를 vault 로 열어 그래프·백링크가 뜨는지 확인.
10. 작업 전부 `feat/bootstrap-pipeline` 브랜치 위에서. 커밋·푸시는 사용자 명시적 요청 시에만.

## 리스크 & 비확정 지점

- **Astro/Starlight 버전**: 0.30 / astro 5 가 현재 안정이라고 적었지만 실제 설치 시 `npm install` 이 최신 호환 버전을 해결한다. `content.config.ts` 의 `docsLoader` pattern 시그니처가 버전마다 조금씩 다를 수 있어, 설치 후 공식 문서로 확정 후 첫 `npm run dev` 로 검증한다.
- **symlink**: 재클론·윈도우 호환 이슈. 현 환경은 Linux 이므로 문제 없음. README 에 "git clone 후 `make setup`" 안내를 추후 추가.
- **claude -p 종료 코드**: 비대화형 호출이 permission 이슈로 중간에 실패할 수 있어 `--allowedTools` 를 `Read,Edit,Write,Glob,Grep` 로 고정하고 `--permission-mode acceptEdits`. 실패 시 해당 raw 는 `ingested.json` 에 반영하지 않아 다음 실행에서 재시도.
- **카테고리 드리프트**: emergent 분류는 중복·의미 겹침 슬러그를 만들 수 있다. 사용자가 주기적으로 `wiki/_meta/categories.yaml` 에서 병합·리네이밍하도록 schema.md 에 운영 가이드 한 단락 추가.
