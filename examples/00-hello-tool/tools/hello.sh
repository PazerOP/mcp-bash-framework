#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091 # sdk/ copied next to this script at runtime by examples/run
source "$(dirname "$0")/../../../sdk/tool-sdk.sh"
mcp_emit_text "Hello from example tool"
