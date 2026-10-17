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

    def make_provider(self, request_meter=None):
        """Use pinned OpenWorker transports with explicit run-local SDK clients."""
        if self.provider in {"openai-chat", "openai-responses", "ollama"}:
            from openai import OpenAI
            from coworker.providers.openai_provider import OpenAIProvider
            from coworker.providers.openai_responses import OpenAIResponsesProvider
            endpoint = self.base_url.rstrip("/")
            if self.provider == "ollama" and not endpoint.endswith("/v1"):
                endpoint += "/v1"
            client = OpenAI(api_key=self.api_key or "local", base_url=endpoint, timeout=60, max_retries=0)
            if request_meter:
                client.chat.completions.create = request_meter.raw_create(client.chat.completions.create)
                client.responses.create = request_meter.raw_create(client.responses.create)
            kind = OpenAIResponsesProvider if self.provider == "openai-responses" else OpenAIProvider
            return kind(client=client, default_model=self.model)
        if self.provider == "anthropic":
            from anthropic import Anthropic
            from coworker.providers.anthropic_provider import AnthropicProvider
            return AnthropicProvider(client=Anthropic(api_key=self.api_key, timeout=60, max_retries=0), default_model=self.model, thinking_budget=0)
        from google import genai
        from google.genai import types
        from coworker.providers.gemini_provider import GeminiProvider
        return GeminiProvider(client=genai.Client(api_key=self.api_key, http_options=types.HttpOptions(timeout=60000,
                              retry_options=types.HttpRetryOptions(attempts=1))), default_model=self.model)

    @classmethod
    def from_environment(cls):
        return cls(provider=os.getenv("PULSE_PROVIDER", "openai-chat"), base_url=os.getenv("OPENAI_BASE_URL", "https://openrouter.ai/api/v1"),
                   api_key=os.getenv("OPENAI_API_KEY", ""), model=os.getenv("PULSE_MODEL_ID", "openai/gpt-4.1-mini"),
                   context_tokens=int(os.getenv("PULSE_CONTEXT_TOKENS", "32768")), output_tokens=int(os.getenv("PULSE_OUTPUT_TOKENS", "4096")),
                   memory_enabled=os.getenv("PULSE_MEMORY_ENABLED", "true") == "true")
