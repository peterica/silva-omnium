import json
import urllib.error
import urllib.request

from .base import LLMProvider, ProviderError


class OllamaProvider(LLMProvider):
    def __init__(
        self,
        model: str = "gemma4:latest",
        host: str = "http://localhost:11434",
        timeout: int = 300,
    ):
        self.model = model
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
