import json
import subprocess

from .base import LLMProvider, ProviderError


class ClaudeProvider(LLMProvider):
    def __init__(self, model: str | None = None, timeout: int = 600):
        self.model = model
        self.timeout = timeout

    def synthesize(self, prompt: str) -> dict:
        cmd = ["claude", "-p", "--output-format", "json"]
        if self.model:
            cmd += ["--model", self.model]
        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=self.timeout,
                check=True,
            )
        except subprocess.TimeoutExpired as exc:
            raise ProviderError(f"claude CLI timeout after {self.timeout}s") from exc
        except subprocess.CalledProcessError as exc:
            raise ProviderError(
                f"claude CLI failed (exit {exc.returncode}): {exc.stderr[:500]}"
            ) from exc

        try:
            envelope = json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            raise ProviderError(
                f"claude envelope not JSON: {result.stdout[:200]}"
            ) from exc

        body = (envelope.get("result") or "").strip()
        if body.startswith("```"):
            lines = body.splitlines()
            body = "\n".join(lines[1:-1]) if len(lines) >= 2 else body
        try:
            return json.loads(body)
        except json.JSONDecodeError as exc:
            raise ProviderError(f"claude response not JSON: {body[:500]}") from exc
