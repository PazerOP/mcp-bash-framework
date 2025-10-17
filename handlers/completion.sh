#!/usr/bin/env bash
# Spec §8 completion handler implementation.

set -euo pipefail

mcp_completion_quote() {
  local text="$1"
  local py
  if py="$(mcp_tools_python 2>/dev/null)"; then
    TEXT="${text}" "${py}" <<'PY'
import json, os
print(json.dumps(os.environ.get("TEXT", "")))
PY
  else
    printf '"%s"' "$(printf '%s' "${text}" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
}

mcp_handle_completion() {
  local method="$1"
  local json_payload="$2"
  local id
  if ! id="$(mcp_json_extract_id "${json_payload}")"; then
    id="null"
  fi

  if mcp_runtime_is_minimal_mode; then
    local message
    message=$(mcp_completion_quote "Completion capability unavailable in minimal mode")
    printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":%s}}' "${id}" "${message}"
    return 0
  fi

  case "${method}" in
    completion/complete)
      local name
      name="$(mcp_json_extract_completion_name "${json_payload}")"
      if [ -z "${name}" ]; then
        local message
        message=$(mcp_completion_quote "Completion name is required")
        printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32602,"message":%s}}' "${id}" "${message}"
        return 0
      fi
      mcp_completion_reset
      if ! mcp_completion_add_text "Suggestion for ${name}"; then
        local message
        message=$(mcp_completion_quote "Unable to generate suggestions")
        printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32603,"message":%s}}' "${id}" "${message}"
        return 0
      fi
      local result_json
      result_json="$(mcp_completion_finalize)"
      printf '{"jsonrpc":"2.0","id":%s,"result":%s}' "${id}" "${result_json}"
      ;;
    *)
      local message
      message=$(mcp_completion_quote "Unknown completion method")
      printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":%s}}' "${id}" "${message}"
      ;;
  esac
}
