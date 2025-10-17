#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091 # examples/run stages sdk/ alongside these tools before execution
source "$(dirname "$0")/../../../sdk/tool-sdk.sh"
mcp_log info example.logger '{"message":"about to work"}'
mcp_emit_text "Check your logging notifications"
