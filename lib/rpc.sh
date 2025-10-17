#!/usr/bin/env bash
# Spec §4: ensure single-line JSON emission with stdout discipline.

set -euo pipefail

rpc_send_line() {
  local payload="$1"
  mcp_io_send_line "${payload}"
}
