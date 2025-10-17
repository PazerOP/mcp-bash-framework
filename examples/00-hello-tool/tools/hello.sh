#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../../sdk/tool-sdk.sh
source "$(dirname "$0")/../../sdk/tool-sdk.sh"
mcp_emit_text "Hello from example tool"
