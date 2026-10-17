"""Bounded local diagnostics. Deliberately accepts metadata, never arbitrary payloads."""
import json
import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path
import time

FIELDS = frozenset({"run_id", "session_id", "call_id", "operation", "stage", "status", "error_type",
                    "elapsed_ms", "input_bytes", "output_bytes", "context_estimate", "context_limit",
                    "message_count", "sequence", "queue_depth", "count", "provider", "attempt", "context_before", "status_code"})
logger = logging.getLogger("pulse.harness")
logger.propagate = False

def configure(directory):
    if logger.handlers:
        return
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / "harness.jsonl"
    # Open with owner-only permissions from the first byte, including rotations.
    class PrivateHandler(RotatingFileHandler):
        def _open(self):
            fd = os.open(self.baseFilename, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            os.fchmod(fd, 0o600)
            return os.fdopen(fd, "a", encoding="utf-8")
    handler = PrivateHandler(path, maxBytes=2_000_000, backupCount=3, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

def record(event, **fields):
    # Allowlist field names AND bounded scalar values. No errors/URLs/arguments/messages.
    safe = {key: value[:128] if isinstance(value, str) else value
            for key, value in fields.items() if key in FIELDS and isinstance(value, (str, int, float, bool))}
    logger.info(json.dumps({"time": time.time(), "event": event, **safe}, separators=(",", ":")))
