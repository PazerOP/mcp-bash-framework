#!/usr/bin/env bash
# Spec §4–§6: lifecycle bootstrap, concurrency, cancellation, timeouts, stdout discipline.

set -euo pipefail

MCPBASH_MAIN_PGID=""
MCPBASH_SHUTDOWN_PENDING=false
MCPBASH_NO_RESPONSE="__MCP_NO_RESPONSE__"
MCPBASH_INITIALIZE_HANDSHAKE_DONE=false
MCPBASH_HANDLER_OUTPUT=""

mcp_core_run() {
  mcp_core_require_handlers
  mcp_core_bootstrap_state
  mcp_core_read_loop
  mcp_core_wait_for_workers
}

mcp_core_require_handlers() {
  . "${MCPBASH_ROOT}/handlers/lifecycle.sh"
  . "${MCPBASH_ROOT}/handlers/ping.sh"
  . "${MCPBASH_ROOT}/handlers/logging.sh"
  . "${MCPBASH_ROOT}/handlers/tools.sh"
  . "${MCPBASH_ROOT}/handlers/resources.sh"
  . "${MCPBASH_ROOT}/handlers/prompts.sh"
  . "${MCPBASH_ROOT}/handlers/completion.sh"
}

mcp_core_bootstrap_state() {
  MCPBASH_INITIALIZED=false
  MCPBASH_SHUTDOWN_PENDING=false
  MCPBASH_INITIALIZE_HANDSHAKE_DONE=false
  mcp_runtime_init_paths
  mcp_ids_init_state
  mcp_lock_init
  mcp_io_init
  . "${MCPBASH_ROOT}/lib/timeout.sh"
  MCPBASH_MAIN_PGID="$(mcp_core_lookup_pgid "$$")"

  # setup SDK notification streams
  MCP_PROGRESS_STREAM="${MCPBASH_STATE_DIR}/progress.ndjson"
  MCP_LOG_STREAM="${MCPBASH_STATE_DIR}/logs.ndjson"
  : >"${MCP_PROGRESS_STREAM}"
  : >"${MCP_LOG_STREAM}"
}

mcp_core_read_loop() {
  local line
  while IFS= read -r line; do
    mcp_core_handle_line "${line}"
  done
}

mcp_core_wait_for_workers() {
  local pid
  local exit_code
  local pids

  pids="$(jobs -p 2>/dev/null || true)"
  if [ -z "${pids}" ]; then
    return 0
  fi

  for pid in ${pids}; do
    if ! wait "${pid}"; then
      exit_code=$?
      printf '%s\n' "mcp-bash: background worker ${pid} exited with status ${exit_code}" >&2
    fi
  done
}

mcp_core_handle_line() {
  local raw_line="$1"
  local normalized_line
  local method

  normalized_line="$(mcp_json_normalize_line "${raw_line}")" || {
    mcp_core_emit_parse_error "Invalid Request" -32600 "Failed to normalize input"
    return
  }

  if [ -z "${normalized_line}" ]; then
    return
  fi

  method="$(mcp_json_extract_method "${normalized_line}")" || {
    mcp_core_emit_parse_error "Invalid Request" -32600 "Missing method"
    return
  }

  mcp_core_dispatch_object "${normalized_line}" "${method}"

  mcp_core_emit_registry_notifications
}

mcp_core_dispatch_object() {
  local json_line="$1"
  local method="$2"
  local handler=""
  local async="false"
  local id_json

  if [ "${method}" = "notifications/cancelled" ]; then
    mcp_core_handle_cancel_notification "${json_line}"
    return
  fi

  if [ "${method}" = "notifications/message" ]; then
    mcp_core_emit_parse_error "Invalid Request" -32601 "notifications/message is server-originated"
    return
  fi

  if ! id_json="$(mcp_json_extract_id "${json_line}")"; then
    id_json=""
  fi

  if [ "${MCPBASH_INITIALIZED}" != true ] && ! mcp_core_method_allowed_preinit "${method}"; then
    mcp_core_emit_not_initialized "${id_json}"
    return
  fi

  if [ "${MCPBASH_SHUTDOWN_PENDING}" = true ] && ! mcp_core_method_allowed_during_shutdown "${method}"; then
    mcp_core_emit_shutting_down "${id_json}"
    return
  fi

  if ! mcp_core_resolve_handler "${method}"; then
    mcp_core_emit_method_not_found "${id_json}"
    return
  fi

  handler="${MCPBASH_RESOLVED_HANDLER}"
  async="${MCPBASH_RESOLVED_ASYNC}"

  if [ "${async}" = "true" ]; then
    mcp_core_spawn_worker "${handler}" "${method}" "${json_line}" "${id_json}"
  else
    mcp_core_execute_handler "${handler}" "${method}" "${json_line}" "${id_json}"
  fi
}

mcp_core_resolve_handler() {
  local method="$1"
  MCPBASH_RESOLVED_HANDLER=""
  MCPBASH_RESOLVED_ASYNC="false"

  case "${method}" in
    initialize|shutdown|exit|initialized|notifications/initialized)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_lifecycle"
      ;;
    ping)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_ping"
      ;;
    logging/*)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_logging"
      ;;
    tools/*)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_tools"
      MCPBASH_RESOLVED_ASYNC="true"
      ;;
    resources/*)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_resources"
      MCPBASH_RESOLVED_ASYNC="true"
      ;;
    prompts/get)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_prompts"
      MCPBASH_RESOLVED_ASYNC="true"
      ;;
    prompts/*)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_prompts"
      ;;
    completion/complete)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_completion"
      MCPBASH_RESOLVED_ASYNC="true"
      ;;
    completion/*)
      MCPBASH_RESOLVED_HANDLER="mcp_handle_completion"
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

mcp_core_execute_handler() {
  local handler="$1"
  local method="$2"
  local json_line="$3"
  local id_json="$4"
  local response

  if ! mcp_core_invoke_handler "${handler}" "${method}" "${json_line}"; then
    response="$(mcp_core_build_error_response "${id_json}" -32601 "Handler not implemented" "")"
  else
    response="${MCPBASH_HANDLER_OUTPUT}"
    if [ "${response}" = "${MCPBASH_NO_RESPONSE}" ]; then
      return 0
    fi
    if [ -z "${response}" ]; then
      response="$(mcp_core_build_error_response "${id_json}" -32603 "Empty handler response" "")"
    fi
  fi

  rpc_send_line "${response}"
}

mcp_core_spawn_worker() {
  local handler="$1"
  local method="$2"
  local json_line="$3"
  local id_json="$4"
  local key
  local stderr_file=""
  local timeout=""

  key="$(mcp_core_get_id_key "${id_json}")"

  if [ -n "${key}" ]; then
    stderr_file="${MCPBASH_STATE_DIR}/stderr.${key}.log"
  else
    stderr_file="${MCPBASH_STATE_DIR}/stderr.${BASHPID:-$$}.${RANDOM}.log"
  fi

  timeout="$(mcp_core_timeout_for_method "${method}" "${json_line}")"
  timeout="$(mcp_core_normalize_timeout "${timeout}")"

  local progress_stream="${MCPBASH_STATE_DIR}/progress.${key:-main}.ndjson"
  local log_stream="${MCPBASH_STATE_DIR}/logs.${key:-main}.ndjson"
  : >"${progress_stream}"
  : >"${log_stream}"
  local cancel_file
  cancel_file="$(mcp_ids_state_path "cancelled" "${key}")"
  rm -f "${cancel_file}"
  local progress_token
  progress_token="$(mcp_json_extract_progress_token "${json_line}")"

  (
    exec 2>"${stderr_file}"
    # shellcheck disable=SC2030
    export MCP_PROGRESS_STREAM="${progress_stream}"
    # shellcheck disable=SC2030
    export MCP_LOG_STREAM="${log_stream}"
    export MCP_PROGRESS_TOKEN="${progress_token}"
    export MCP_CANCEL_FILE="${cancel_file}"
    if [ -n "${timeout}" ]; then
      with_timeout "${timeout}" -- mcp_core_worker_entry "${handler}" "${method}" "${json_line}" "${id_json}" "${key}" "${stderr_file}"
    else
      mcp_core_worker_entry "${handler}" "${method}" "${json_line}" "${id_json}" "${key}" "${stderr_file}"
    fi
  ) &

  local pid=$!

  mcp_core_assign_process_group "${pid}"
  local pgid
  pgid="$(mcp_core_lookup_pgid "${pid}")"

  mcp_ids_track_worker "${key}" "${pid}" "${pgid}" "${stderr_file}"
}

mcp_core_timeout_for_method() {
  local method="$1"
  local json_line="$2"

  case "${method}" in
    tools/*|resources/*|prompts/get|completion/complete)
      if mcp_runtime_is_minimal_mode; then
        printf ''
        return 0
      fi
      case "${MCPBASH_JSON_TOOL}" in
        gojq|jq)
          if ! printf '%s' "${json_line}" | "${MCPBASH_JSON_TOOL_BIN}" -er '.params.timeoutSecs // empty' 2>/dev/null; then
            printf ''
            return 0
          fi
          ;;
        python)
          if ! printf '%s' "${json_line}" | "${MCPBASH_JSON_TOOL_BIN}" -c 'import json,sys
data=json.load(sys.stdin)
params=data.get("params", {})
value=params.get("timeoutSecs")
if value is None:
    raise SystemExit(1)
sys.stdout.write(str(int(value)))' 2>/dev/null; then
            printf ''
            return 0
          fi
          ;;
        *)
          printf ''
          return 0
          ;;
      esac
      ;;
    *)
      printf ''
      return 0
      ;;
  esac
}

mcp_core_worker_entry() {
  local handler="$1"
  local method="$2"
  local json_line="$3"
  local id_json="$4"
  local key="$5"
  local stderr_file="$6"
  local response
  # shellcheck disable=SC2031
  local progress_stream="${MCP_PROGRESS_STREAM:-}"
  # shellcheck disable=SC2031
  local log_stream="${MCP_LOG_STREAM:-}"

  trap 'mcp_core_worker_cleanup "${key}" "${stderr_file}"' EXIT

  if ! mcp_core_invoke_handler "${handler}" "${method}" "${json_line}"; then
    response="$(mcp_core_build_error_response "${id_json}" -32601 "Handler not implemented" "")"
  else
    response="${MCPBASH_HANDLER_OUTPUT}"
    if [ "${response}" = "${MCPBASH_NO_RESPONSE}" ]; then
      response=""
    elif [ -z "${response}" ]; then
      response="$(mcp_core_build_error_response "${id_json}" -32603 "Empty handler response" "")"
    fi
  fi

  if [ -n "${response}" ]; then
    mcp_core_worker_emit "${key}" "${response}"
  fi

  if [ -n "${progress_stream}" ]; then
    mcp_core_emit_progress_stream "${progress_stream}"
    rm -f "${progress_stream}"
  fi
  if [ -n "${log_stream}" ]; then
    mcp_core_emit_log_stream "${log_stream}"
    rm -f "${log_stream}"
  fi
}

mcp_core_worker_emit() {
  local key="$1"
  local payload="$2"
  mcp_io_send_response "${key}" "${payload}"
}

mcp_core_worker_cleanup() {
  local key="$1"
  local stderr_file="$2"

  if [ -n "${key}" ]; then
    mcp_ids_clear_worker "${key}"
  fi

  if [ -n "${stderr_file}" ] && [ -f "${stderr_file}" ]; then
    rm -f "${stderr_file}"
  fi
}

mcp_core_invoke_handler() {
  local handler="$1"
  local method="$2"
  local json_line="$3"
  local tmp_file=""
  local status=0

  if ! declare -f "${handler}" >/dev/null 2>&1; then
    return 127
  fi

  tmp_file="$(mktemp "${MCPBASH_STATE_DIR}/handler.${BASHPID:-$$}.XXXXXX")"
  MCPBASH_HANDLER_OUTPUT=""
  if "${handler}" "${method}" "${json_line}" >"${tmp_file}"; then
    status=0
  else
    status=$?
  fi
  MCPBASH_HANDLER_OUTPUT="$(cat "${tmp_file}")"
  rm -f "${tmp_file}"
  return "${status}"
}

mcp_core_assign_process_group() {
  local pid="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$pid" <<'PY' >/dev/null 2>&1
import os, sys
pid = int(sys.argv[1])
try:
    os.setpgid(pid, pid)
except Exception:
    pass
PY
  elif command -v python >/dev/null 2>&1; then
    python - "$pid" <<'PY' >/dev/null 2>&1
import os, sys
pid = int(sys.argv[1])
try:
    os.setpgid(pid, pid)
except Exception:
    pass
PY
  fi
}

mcp_core_lookup_pgid() {
  local pid="$1"
  local pgid=""

  if command -v python3 >/dev/null 2>&1; then
    pgid="$(python3 - "$pid" <<'PY'
import os, sys
pid = int(sys.argv[1])
try:
    print(os.getpgid(pid))
except Exception:
    pass
PY
)"
  elif command -v python >/dev/null 2>&1; then
    pgid="$(python - "$pid" <<'PY'
import os, sys
pid = int(sys.argv[1])
try:
    print(os.getpgid(pid))
except Exception:
    pass
PY
)"
  fi

  if [ -z "${pgid}" ]; then
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ')"
  fi

  if [ -z "${pgid}" ]; then
    pgid="${pid}"
  fi

  printf '%s' "${pgid}"
}

mcp_core_handle_cancel_notification() {
  local json_line="$1"
  local cancel_id

  if [ "${MCPBASH_INITIALIZED}" = "false" ]; then
    return 0
  fi

  cancel_id="$(mcp_json_extract_cancel_id "${json_line}")"
  if [ -z "${cancel_id}" ]; then
    return 0
  fi

  mcp_core_cancel_request "${cancel_id}"
}

mcp_core_cancel_request() {
  local id_json="$1"
  local key
  local info
  local pid=""
  local pgid=""

  key="$(mcp_core_get_id_key "${id_json}")"
  if [ -z "${key}" ]; then
    return 0
  fi

  mcp_ids_mark_cancelled "${key}"

  if ! info="$(mcp_ids_worker_info "${key}")"; then
    return 0
  fi

  pid="$(printf '%s' "${info}" | awk '{print $1}')"
  pgid="$(printf '%s' "${info}" | awk '{print $2}')"

  if [ -z "${pid}" ]; then
    return 0
  fi

  mcp_core_send_signal_chain "${pid}" "${pgid}" TERM
  sleep 1
  if mcp_core_process_alive "${pid}"; then
    mcp_core_send_signal_chain "${pid}" "${pgid}" KILL
  fi
}

mcp_core_send_signal_chain() {
  local pid="$1"
  local pgid="$2"
  local signal="$3"

  if [ -n "${pgid}" ] && [ "${pgid}" != "${MCPBASH_MAIN_PGID}" ]; then
    kill -"${signal}" "-${pgid}" 2>/dev/null || kill -"${signal}" "${pid}" 2>/dev/null
  else
    kill -"${signal}" "${pid}" 2>/dev/null
  fi
}

mcp_core_process_alive() {
  local pid="$1"
  kill -0 "${pid}" 2>/dev/null
}

mcp_core_get_id_key() {
  local id_json="$1"
  mcp_ids_key_from_json "${id_json}"
}

mcp_core_method_allowed_preinit() {
  case "$1" in
    initialize|notifications/initialized|notifications/cancelled|shutdown|exit)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mcp_core_method_allowed_during_shutdown() {
  case "$1" in
    exit|shutdown|notifications/cancelled|notifications/initialized)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mcp_core_emit_not_initialized() {
  local id_json="$1"
  if [ -z "${id_json}" ]; then
    id_json="null"
  fi
  rpc_send_line "$(mcp_core_build_error_response "${id_json}" -32002 "Server not initialized" "")"
}

mcp_core_emit_shutting_down() {
  local id_json="$1"
  if [ -z "${id_json}" ]; then
    id_json="null"
  fi
  rpc_send_line "$(mcp_core_build_error_response "${id_json}" -32003 "Server shutting down" "")"
}

mcp_core_build_error_response() {
  local id_json="$1"
  local code="$2"
  local message="$3"
  local data="$4"
  local id_value

  id_value="${id_json:-null}"

  if [ -n "${data}" ]; then
    printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%s,"message":"%s","data":"%s"}}' "${id_value}" "${code}" "${message}" "${data}"
  else
    printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%s,"message":"%s"}}' "${id_value}" "${code}" "${message}"
  fi
}

mcp_core_emit_parse_error() {
  local message="$1"
  local code="$2"
  local details="$3"
  rpc_send_line "$(mcp_core_build_error_response "null" "${code}" "${message}" "${details}")"
}

mcp_core_emit_method_not_found() {
  local id_json="$1"
  rpc_send_line "$(mcp_core_build_error_response "${id_json}" -32601 "Method not found" "")"
}

mcp_core_normalize_timeout() {
  local value="$1"
  value="$(printf '%s' "${value}" | tr -d '\r\n')"
  case "${value}" in
    '' ) printf '' ;;
    *[!0-9]* ) printf '' ;;
    0 ) printf '' ;;
    * ) printf '%s' "${value}" ;;
  esac
}

mcp_core_emit_progress_stream() {
  local stream="$1"
  [ -n "${stream}" ] || return 0
  [ -f "${stream}" ] || return 0
  while IFS= read -r line || [ -n "${line}" ]; do
    [ -z "${line}" ] && continue
    rpc_send_line "${line}"
  done <"${stream}"
}

mcp_core_extract_log_level() {
  local line="$1"
  local py
  if ! py="$(mcp_tools_python 2>/dev/null)"; then
    printf 'info'
    return 0
  fi
  local level
  level="$(LINE="${line}" "${py}" <<'PY'
import json, os, sys
try:
    data = json.loads(os.environ["LINE"])
    level = data.get("params", {}).get("level") or "info"
    print(str(level).lower())
except Exception:
    print("info")
PY
)"
  [ -z "${level}" ] && level="info"
  printf '%s' "${level}"
}

mcp_core_emit_log_stream() {
  local stream="$1"
  [ -n "${stream}" ] || return 0
  [ -f "${stream}" ] || return 0
  while IFS= read -r line || [ -n "${line}" ]; do
    [ -z "${line}" ] && continue
    local level
    level="$(mcp_core_extract_log_level "${line}")"
    if mcp_logging_is_enabled "${level}"; then
      rpc_send_line "${line}"
    fi
  done <"${stream}"
}

mcp_core_emit_registry_notifications() {
  local note
  note="$(mcp_tools_consume_notification)"
  if [ -n "${note}" ]; then
    rpc_send_line "${note}"
  fi
  note="$(mcp_resources_consume_notification)"
  if [ -n "${note}" ]; then
    rpc_send_line "${note}"
  fi
  note="$(mcp_prompts_consume_notification)"
  if [ -n "${note}" ]; then
    rpc_send_line "${note}"
  fi
}
