#!/usr/bin/env bash
# Spec §7: capability negotiation helpers.

set -euo pipefail

mcp_spec_capabilities_full() {
  cat <<'EOF'
{"logging":{},"tools":{"listChanged":true},"resources":{"subscribe":true,"listChanged":true},"prompts":{"listChanged":true},"completion":{}}
EOF
}

mcp_spec_capabilities_minimal() {
  printf '{"logging":{}}'
}

mcp_spec_capabilities_for_runtime() {
  if mcp_runtime_is_minimal_mode; then
    mcp_spec_capabilities_minimal
  else
    mcp_spec_capabilities_full
  fi
}

mcp_spec_build_initialize_response() {
  local id_json="$1"
  local capabilities_json="$2"
  printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"%s","capabilities":%s,"serverInfo":{"name":"%s","version":"%s","title":"%s"}}}' \
    "${id_json}" \
    "${MCPBASH_PROTOCOL_VERSION}" \
    "${capabilities_json}" \
    "${MCPBASH_SERVER_NAME}" \
    "${MCPBASH_SERVER_VERSION}" \
    "${MCPBASH_SERVER_TITLE}"
}
