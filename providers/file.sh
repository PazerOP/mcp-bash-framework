#!/usr/bin/env bash
# Spec §8/§12 default file provider.

set -euo pipefail

uri="$1"
path="${uri#file://}"
case "${path}" in
  [A-Za-z]:/*)
    drive="${path%%:*}"
    rest="${path#*:}"
    path="/${drive,,}${rest}"
    ;;
esac
path="${path//\\//}"
if [ -z "${MSYS2_ARG_CONV_EXCL:-}" ]; then
  MSYS2_ARG_CONV_EXCL="*"
fi
if command -v realpath >/dev/null 2>&1; then
  path="$(realpath -m "${path}")"
fi
roots="${MCP_RESOURCES_ROOTS:-${MCPBASH_ROOT}}"
allowed=false
for root in ${roots}; do
  check_root="$root"
  if command -v realpath >/dev/null 2>&1; then
    check_root="$(realpath -m "${root}")"
  fi
  case "${path}" in
    "${check_root}" | "${check_root}"/*)
      allowed=true
      break
      ;;
  esac
done
if [ "${allowed}" != true ]; then
  printf '%s' "" >&2
  exit 2
fi
if [ ! -f "${path}" ]; then
  exit 3
fi
cat "${path}"
