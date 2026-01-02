#!/usr/bin/env bash
# A tool that uses a script to determine visibility
set -euo pipefail
source "${MCPBASH_SDK:-/dev/null}" 2>/dev/null || true

mcp_emit_json '{"message": "Script-controlled tool executed!", "current_hour": "'"$(date +%H)"'"}'
