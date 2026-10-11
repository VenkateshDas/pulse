"""Explicit provider configuration; credentials never enter events or storage."""
import os
from urllib.parse import urlsplit
from pydantic import BaseModel, Field, model_validator

class ProviderConfiguration(BaseModel):
    provider: str = "openai-chat"
    base_url: str = "https://openrouter.ai/api/v1"
    api_key: str = Field(default="", repr=False, max_length=8192)
    model: str = Field(default="openai/gpt-4.1-mini", min_length=1, max_length=200)
    context_tokens: int = Field(default=32768, ge=8192, le=262144)
    output_tokens: int = Field(default=4096, ge=512, le=16384)
    memory_enabled: bool = True

    @model_validator(mode="after")
    def validate_configuration(self):
        self.base_url = self.base_url.strip()
        self.model = self.model.strip()
        if self.provider not in {"openai-chat", "openai-responses", "anthropic", "google", "ollama"}:
            raise ValueError("Unsupported provider transport")
        u = urlsplit(self.base_url)
        local = u.hostname in {"localhost", "127.0.0.1", "::1"}
        if not u.hostname or u.username or u.password or u.query or u.fragment or not (u.scheme == "https" or u.scheme == "http" and local):
            raise ValueError("Use HTTPS, or HTTP on loopback, without URL credentials")
        if not self.model or self.output_tokens >= self.context_tokens // 2:
            raise ValueError("Model and context/output budgets must be valid")
        # These integrations do not expose a custom API URL in the pinned SDK.
        if self.provider == "anthropic" and self.base_url.rstrip("/") != "https://api.anthropic.com":
            raise ValueError("Anthropic requires https://api.anthropic.com; use a compatible gateway through OpenAI Chat")
        if self.provider == "google" and self.base_url.rstrip("/") != "https://generativelanguage.googleapis.com":
            raise ValueError("Gemini requires https://generativelanguage.googleapis.com")
        return self

    @property
    def ready(self):
        return bool(self.api_key) or (self.provider in {"openai-chat", "ollama"} and urlsplit(self.base_url).hostname in {"localhost", "127.0.0.1", "::1"})

    def make_model(self):
        common = dict(id=self.model, retries=0)
        if self.provider == "openai-chat":
            from agno.models.openai import OpenAIChat
            return OpenAIChat(**common, base_url=self.base_url, api_key=self.api_key or "local", max_completion_tokens=self.output_tokens, timeout=60, max_retries=0, retry_with_guidance=False)
        if self.provider == "openai-responses":
            from agno.models.openai import OpenAIResponses
            return OpenAIResponses(**common, base_url=self.base_url, api_key=self.api_key, max_output_tokens=self.output_tokens, timeout=60, max_retries=0, retry_with_guidance=False)
        if self.provider == "anthropic":
            from agno.models.anthropic import Claude
            return Claude(**common, api_key=self.api_key, max_tokens=self.output_tokens, timeout=60, retry_with_guidance=False)
        if self.provider == "google":
            from agno.models.google import Gemini
            return Gemini(**common, api_key=self.api_key, max_output_tokens=self.output_tokens)
        from agno.models.ollama import Ollama
        return Ollama(**common, host=self.base_url, api_key=self.api_key or None, options={"num_predict": self.output_tokens, "num_ctx": self.context_tokens})

    @classmethod
    def from_environment(cls):
        return cls(provider=os.getenv("PULSE_PROVIDER", "openai-chat"), base_url=os.getenv("OPENAI_BASE_URL", "https://openrouter.ai/api/v1"),
                   api_key=os.getenv("OPENAI_API_KEY", ""), model=os.getenv("PULSE_MODEL_ID", "openai/gpt-4.1-mini"),
                   context_tokens=int(os.getenv("PULSE_CONTEXT_TOKENS", "32768")), output_tokens=int(os.getenv("PULSE_OUTPUT_TOKENS", "4096")),
                   memory_enabled=os.getenv("PULSE_MEMORY_ENABLED", "true") == "true")
