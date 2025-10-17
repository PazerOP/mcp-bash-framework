#!/usr/bin/env bash
# Spec §5: stdout serialization, UTF-8 validation, and cancellation-aware emission.

set -euo pipefail

MCPBASH_STDOUT_LOCK_NAME="stdout"
MCPBASH_ICONV_AVAILABLE=""

mcp_io_init() {
  mcp_lock_init
}

mcp_io_stdout_lock_acquire() {
  mcp_lock_acquire "${MCPBASH_STDOUT_LOCK_NAME}"
}

mcp_io_stdout_lock_release() {
  mcp_lock_release "${MCPBASH_STDOUT_LOCK_NAME}"
}

mcp_io_send_line() {
  local payload="$1"
  if [ -z "${payload}" ]; then
    return 0
  fi
  mcp_io_stdout_lock_acquire
  mcp_io_write_payload "${payload}"
  mcp_io_stdout_lock_release
}

mcp_io_send_response() {
  local key="$1"
  local payload="$2"

  if [ -z "${payload}" ]; then
    return 0
  fi

  mcp_io_stdout_lock_acquire
  if [ -n "${key}" ] && mcp_ids_is_cancelled_key "${key}"; then
    mcp_io_stdout_lock_release
    return 0
  fi

  if ! mcp_io_write_payload "${payload}"; then
    mcp_io_stdout_lock_release
    return 1
  fi

  mcp_io_stdout_lock_release
  return 0
}

mcp_io_write_payload() {
  local payload="$1"
  local normalized

  normalized="$(printf '%s' "${payload}" | tr -d '\r')"

  if ! mcp_io_validate_utf8 "${normalized}"; then
    printf '%s\n' 'mcp-bash: dropping non-UTF8 payload to preserve stdout contract (Spec §5).' >&2
    return 1
  fi

  printf '%s\n' "${normalized}"
  return 0
}

mcp_io_validate_utf8() {
  local data="$1"

  if [ -z "${data}" ]; then
    return 0
  fi

  if [ -z "${MCPBASH_ICONV_AVAILABLE}" ]; then
    if command -v iconv >/dev/null 2>&1; then
      MCPBASH_ICONV_AVAILABLE="true"
    else
      MCPBASH_ICONV_AVAILABLE="false"
    fi
  fi

  if [ "${MCPBASH_ICONV_AVAILABLE}" = "false" ]; then
    return 0
  fi

  printf '%s' "${data}" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1
}
