#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

RUNTIME_DIR="${PULSE_AGENT_RUNTIME_DIR:-$DIR}"
VENV="$RUNTIME_DIR/.venv"
mkdir -p "$RUNTIME_DIR"

if [ ! -x "$VENV/bin/python" ]; then
    UV="$(command -v uv || true)"
    if [ -z "$UV" ] && [ -x "$HOME/.local/bin/uv" ]; then UV="$HOME/.local/bin/uv"; fi
    if [ -z "$UV" ] && [ -x "/opt/homebrew/bin/uv" ]; then UV="/opt/homebrew/bin/uv"; fi
    if [ -z "$UV" ] && [ -x "/usr/local/bin/uv" ]; then UV="/usr/local/bin/uv"; fi
    if [ -z "$UV" ]; then
        echo "Pulse Agent requires uv. Install it with: brew install uv" >&2
        exit 1
    fi
    "$UV" venv --no-project --python 3.12 "$VENV"
fi

if ! "$VENV/bin/python" -c 'import agno, fastapi' >/dev/null 2>&1; then
    UV="${UV:-$(command -v uv || true)}"
    if [ -z "$UV" ] && [ -x "$HOME/.local/bin/uv" ]; then UV="$HOME/.local/bin/uv"; fi
    if [ -z "$UV" ] && [ -x "/opt/homebrew/bin/uv" ]; then UV="/opt/homebrew/bin/uv"; fi
    if [ -z "$UV" ] && [ -x "/usr/local/bin/uv" ]; then UV="/usr/local/bin/uv"; fi
    if [ -z "$UV" ]; then
        echo "Pulse Agent requires uv. Install it with: brew install uv" >&2
        exit 1
    fi
    "$UV" pip install --no-config --python "$VENV/bin/python" "agno[os,agui]" openai anthropic aiosqlite
fi

exec "$VENV/bin/python" server.py
