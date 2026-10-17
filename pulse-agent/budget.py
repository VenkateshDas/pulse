"""Conservative prompt budget guard applied before every provider invocation.
The count is an estimate (UTF-8 bytes), not a claim about provider tokenizer usage.
"""
import json
from types import MethodType

class ContextBudgetExceeded(ValueError): pass

def prompt_units(messages, kwargs):
    encoded = [m.to_dict() if hasattr(m, 'to_dict') else str(m) for m in messages]
    extras = {k:v for k,v in kwargs.items() if k in {'tools', 'response_format', 'output_schema'}}
    raw = json.dumps([encoded, extras], default=str, ensure_ascii=False).encode()
    # Three ASCII bytes/token, one byte/token for non-ASCII; conservative
    # estimate for typical prose, not a substitute for the provider tokenizer.
    return sum(1 if byte >= 128 else 1 / 3 for byte in raw)

def bound_model(model, context_tokens, output_tokens):
    # The provider retains its authoritative tokenizer/context limit.
    limit = context_tokens - output_tokens
    original_invoke, original_stream = model.ainvoke, model.ainvoke_stream
    def guard(messages, kwargs):
        estimate = prompt_units(messages, kwargs)
        if estimate > limit: raise ContextBudgetExceeded('Context budget reached. Start a new conversation or choose a larger context budget.')
    async def invoke(self, messages, *args, **kwargs):
        guard(messages, kwargs)
        return await original_invoke(messages, *args, **kwargs)
    async def stream(self, messages, *args, **kwargs):
        guard(messages, kwargs)
        async for chunk in original_stream(messages, *args, **kwargs): yield chunk
    model.ainvoke = MethodType(invoke, model)
    model.ainvoke_stream = MethodType(stream, model)
    return model
