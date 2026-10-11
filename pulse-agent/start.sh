#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${PULSE_AGENT_RUNTIME_DIR:-$DIR}"
mkdir -p "$RUNTIME_DIR"
UV="$(command -v uv || true)"
for candidate in "$HOME/.local/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
    if [ -z "$UV" ] && [ -x "$candidate" ]; then UV="$candidate"; fi
done
if [ -z "$UV" ]; then echo "Pulse Agent requires uv. Install with brew install uv." >&2; exit 1; fi
# Runtime files live in Application Support; the shipped lock is authoritative.
export UV_PROJECT_ENVIRONMENT="$RUNTIME_DIR/.venv"
"$UV" sync --project "$DIR" --frozen --no-dev --no-install-project --python 3.12
cd "$DIR"
exec "$RUNTIME_DIR/.venv/bin/python" server.py
