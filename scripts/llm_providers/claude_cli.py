"""Claude Code CLI provider — uses the locally installed `claude` binary
in `-p` (print, non-interactive) mode. Auth comes from the user's claude
login (subscription OAuth), so no API key billing.

Trade-offs vs ClaudeProvider (which uses the Anthropic SDK):
- (+) Uses Claude Pro/Max subscription, no per-token API charges
- (+) Same model quality
- (-) Subprocess overhead (~1-2s per call vs direct HTTPS)
- (-) Requires `claude` binary in PATH and prior `claude` OAuth login
"""

from __future__ import annotations

import json
import os
import re
import subprocess

from .base import LLMProvider, ProviderError


_FENCE_RE = re.compile(r"^```(?:json)?\s*\n(.*?)\n```\s*$", re.DOTALL)


class ClaudeCliProvider(LLMProvider):
    def __init__(
        self,
        model: str | None = None,
        timeout: int = 600,
        binary: str | None = None,
    ):
        # model alias accepted by claude CLI: sonnet | opus | haiku, or full id
        self.model = model or os.environ.get("CLAUDE_CLI_MODEL")
        self.timeout = timeout
        self.binary = binary or os.environ.get("CLAUDE_CLI_BIN", "claude")

    def synthesize(self, prompt: str) -> dict:
        cmd = [self.binary, "-p"]
        if self.model:
            cmd += ["--model", self.model]

        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=self.timeout,
            )
        except FileNotFoundError as exc:
            raise ProviderError(f"claude binary not found: {self.binary}") from exc
        except subprocess.TimeoutExpired as exc:
            raise ProviderError(f"claude -p timed out after {self.timeout}s") from exc

        if result.returncode != 0:
            stderr_tail = (result.stderr or "")[-500:]
            raise ProviderError(
                f"claude -p exit {result.returncode}: {stderr_tail.strip()}"
            )

        raw = (result.stdout or "").strip()
        if not raw:
            raise ProviderError("claude -p returned empty stdout")

        # Strip optional fenced code block (```json ... ```)
        m = _FENCE_RE.match(raw)
        if m:
            raw = m.group(1).strip()

        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ProviderError(
                f"claude -p response not JSON: {raw[:500]}"
            ) from exc
