import json
import os
import urllib.error
import urllib.request

from .base import LLMProvider, ProviderError


class OllamaProvider(LLMProvider):
    def __init__(
        self,
        model: str | None = None,
        host: str | None = None,
        timeout: int = 300,
    ):
        self.model = model or os.environ.get("OLLAMA_MODEL", "gemma4:latest")
        host = host or os.environ.get("OLLAMA_HOST", "http://localhost:11434")
        self.endpoint = f"{host.rstrip('/')}/api/generate"
        self.timeout = timeout

    def synthesize(self, prompt: str) -> dict:
        payload = json.dumps(
            {
                "model": self.model,
                "prompt": prompt,
                "stream": False,
                "format": "json",
                "options": {"temperature": 0.2},
            }
        ).encode("utf-8")
        req = urllib.request.Request(
            self.endpoint,
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read().decode("utf-8")
        except urllib.error.URLError as exc:
            raise ProviderError(f"ollama request failed: {exc}") from exc

        try:
            envelope = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ProviderError(f"ollama envelope not JSON: {raw[:200]}") from exc

        body = envelope.get("response", "")
        try:
            return json.loads(body)
        except json.JSONDecodeError as exc:
            raise ProviderError(f"ollama response not JSON: {body[:500]}") from exc
