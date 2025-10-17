#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../../sdk/tool-sdk.sh
source "$(dirname "$0")/../../sdk/tool-sdk.sh"
value="$(mcp_args_get '.value')"
if [ -z "${value}" ]; then
  stderr_message="Missing 'value' argument"
  printf '%s' "${stderr_message}" >&2
  exit 1
fi
mcp_emit_text "You sent: ${value}"
