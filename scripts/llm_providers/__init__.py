from .base import LLMProvider, ProviderError
from .claude import ClaudeProvider
from .claude_cli import ClaudeCliProvider
from .ollama import OllamaProvider


def get_provider(name: str, **kwargs) -> LLMProvider:
    name = name.lower()
    if name == "ollama":
        return OllamaProvider(**kwargs)
    if name == "claude":
        return ClaudeProvider(**kwargs)
    if name == "claude-cli":
        return ClaudeCliProvider(**kwargs)
    raise ValueError(
        f"unknown provider: {name!r} (expected: ollama | claude | claude-cli)"
    )


__all__ = [
    "LLMProvider",
    "ProviderError",
    "OllamaProvider",
    "ClaudeProvider",
    "ClaudeCliProvider",
    "get_provider",
]
