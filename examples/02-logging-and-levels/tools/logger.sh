#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../../sdk/tool-sdk.sh
source "$(dirname "$0")/../../sdk/tool-sdk.sh"
mcp_log info example.logger '{"message":"about to work"}'
mcp_emit_text "Check your logging notifications"
