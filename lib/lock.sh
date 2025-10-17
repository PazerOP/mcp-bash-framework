#!/usr/bin/env bash
# Spec §5/§12: portable lock-dir primitives for stdout serialization and state coordination.

set -euo pipefail

MCPBASH_LOCK_POLL_INTERVAL="0.01"

mcp_lock_init() {
  if [ -z "${MCPBASH_LOCK_ROOT}" ]; then
    printf '%s\n' 'MCPBASH_LOCK_ROOT not set; call mcp_runtime_init_paths first.' >&2
    exit 1
  fi
  mkdir -p "${MCPBASH_LOCK_ROOT}"
}

mcp_lock_path() {
  printf '%s/%s.lock' "${MCPBASH_LOCK_ROOT}" "$1"
}

mcp_lock_acquire() {
  local name="$1"
  local path
  path="$(mcp_lock_path "${name}")"

  while ! mkdir "${path}" 2>/dev/null; do
    mcp_lock_try_reap "${path}"
    sleep "${MCPBASH_LOCK_POLL_INTERVAL}"
  done

  printf '%s' "${BASHPID:-$$}" >"${path}/pid"
}

mcp_lock_release() {
  local name="$1"
  local path
  path="$(mcp_lock_path "${name}")"
  if [ -d "${path}" ]; then
    rm -rf "${path}"
  fi
}

mcp_lock_try_reap() {
  local path="$1"
  local owner
  if [ ! -f "${path}/pid" ]; then
    return
  fi

  owner="$(cat "${path}/pid" 2>/dev/null || true)"
  if [ -z "${owner}" ]; then
    rm -rf "${path}"
    return
  fi

  if ! kill -0 "${owner}" 2>/dev/null; then
    rm -rf "${path}"
  fi
}
