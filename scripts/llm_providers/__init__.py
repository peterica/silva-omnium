from .base import LLMProvider, ProviderError
from .claude import ClaudeProvider
from .ollama import OllamaProvider


def get_provider(name: str, **kwargs) -> LLMProvider:
    name = name.lower()
    if name == "ollama":
        return OllamaProvider(**kwargs)
    if name == "claude":
        return ClaudeProvider(**kwargs)
    raise ValueError(f"unknown provider: {name!r} (expected: ollama | claude)")


__all__ = [
    "LLMProvider",
    "ProviderError",
    "OllamaProvider",
    "ClaudeProvider",
    "get_provider",
]
