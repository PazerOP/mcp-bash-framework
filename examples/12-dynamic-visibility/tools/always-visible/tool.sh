#!/usr/bin/env bash
# A tool that is always visible (no visibility field)
set -euo pipefail
source "${MCPBASH_SDK:-/dev/null}" 2>/dev/null || true

mcp_emit_json '{"message": "This tool is always visible!"}'
