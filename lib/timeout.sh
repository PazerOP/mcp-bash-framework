#!/usr/bin/env bash
# Spec §6: timeout orchestration via watchdog processes.

set -euo pipefail

with_timeout() {
  local seconds
  local cmd

  if [ $# -lt 3 ]; then
    printf '%s\n' 'with_timeout expects: with_timeout <seconds> -- <command...>' >&2
    return 1
  fi

  seconds="$1"
  shift

  if ! [ "$1" = "--" ]; then
    printf '%s\n' 'with_timeout usage: with_timeout <seconds> -- <command...>' >&2
    return 1
  fi

  shift
  cmd=("$@")

  local worker_pid
  local watchdog_pid

  ( "${cmd[@]}" ) &
  worker_pid=$!

  mcp_timeout_spawn_watchdog "${worker_pid}" "${seconds}" &
  watchdog_pid=$!

  wait "${worker_pid}"
  local status=$?

  kill -0 "${watchdog_pid}" 2>/dev/null && kill -TERM "${watchdog_pid}" 2>/dev/null
  wait "${watchdog_pid}" 2>/dev/null || true

  return "${status}"
}

mcp_timeout_spawn_watchdog() {
  local worker_pid="$1"
  local seconds="$2"

  sleep "${seconds}"

  if kill -0 "${worker_pid}" 2>/dev/null; then
    kill -TERM "${worker_pid}" 2>/dev/null
    sleep 1
  fi

  if kill -0 "${worker_pid}" 2>/dev/null; then
    kill -KILL "${worker_pid}" 2>/dev/null
  fi

  exit 0
}
