#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

if [ ! -d ".venv" ]; then
    /Users/venkateshmurugadas/.local/bin/uv venv .venv --python /Users/venkateshmurugadas/.local/share/uv/python/cpython-3.12.9-macos-aarch64-none/bin/python3.12
    /Users/venkateshmurugadas/.local/bin/uv pip install --python .venv/bin/python "agno[os,agui]" openai anthropic aiosqlite
fi

exec .venv/bin/python server.py
