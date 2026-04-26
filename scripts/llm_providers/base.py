from abc import ABC, abstractmethod


class ProviderError(Exception):
    pass


class LLMProvider(ABC):
    @abstractmethod
    def synthesize(self, prompt: str) -> dict:
        """Send prompt, return parsed JSON dict per ingest schema.

        Providers do not touch disk; ingest.py applies the returned change.
        Raises ProviderError on transport failure or invalid JSON.
        """
        ...
