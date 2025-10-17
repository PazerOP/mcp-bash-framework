#!/usr/bin/env bash
# Spec §3/§8 lifecycle handler: initialize/initialized/shutdown workflow.

set -euo pipefail

mcp_handle_lifecycle() {
  local method="$1"
  local json_payload="$2"
  local id
  if ! id="$(mcp_json_extract_id "${json_payload}")"; then
    id="null"
  fi

  case "${method}" in
    initialize)
      if [ "${MCPBASH_INITIALIZE_HANDSHAKE_DONE}" = true ]; then
        printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32600,"message":"Server already initialized"}}' "${id}"
        return 0
      fi

      local requested_version=""
      requested_version="$(mcp_json_extract_protocol_version "${json_payload}")"
      if [ -n "${requested_version}" ] && [ "${requested_version}" != "${MCPBASH_PROTOCOL_VERSION}" ]; then
        printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32602,"message":"Unsupported protocol version"}}' "${id}"
        return 0
      fi

      local capabilities
      capabilities="$(mcp_spec_capabilities_for_runtime)"

      MCPBASH_INITIALIZE_HANDSHAKE_DONE=true
      MCPBASH_INITIALIZED=false

      printf '%s' "$(mcp_spec_build_initialize_response "${id}" "${capabilities}")"
      ;;
    notifications/initialized | initialized)
      # shellcheck disable=SC2034
      MCPBASH_INITIALIZED=true
      printf '%s' "${MCPBASH_NO_RESPONSE}"
      ;;
    shutdown)
      MCPBASH_SHUTDOWN_PENDING=true
      if [ "${MCPBASH_SHUTDOWN_TIMER_STARTED:-false}" != "true" ]; then
        MCPBASH_SHUTDOWN_TIMER_STARTED=true
        mcp_core_start_shutdown_watchdog &
      fi
      printf '{"jsonrpc":"2.0","id":%s,"result":{}}' "${id}"
      ;;
    exit)
      if [ "${MCPBASH_SHUTDOWN_PENDING}" != "true" ]; then
        printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32003,"message":"Shutdown not requested"}}' "${id}"
        return 0
      fi
      printf '{"jsonrpc":"2.0","id":%s,"result":{}}' "${id}"
      mcp_runtime_cleanup
      exit 0
      ;;
    *)
      printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"Unknown lifecycle method"}}' "${id}"
      ;;
  esac
}
