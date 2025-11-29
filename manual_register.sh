#!/usr/bin/env bash
set -euo pipefail

# If sourced by the runtime, register a demo tool; if executed directly, print guidance and exit cleanly.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
	if command -v mcp_register_tool >/dev/null 2>&1; then
		mcp_register_tool '{"name":"demo","path":"tools/manual/demo.sh"}'
	fi
	return 0
fi

cat <<'MSG'
This script is meant to be sourced by the mcp-bash runtime (server.d/manual hooks).
Running it directly will not register tools.
MSG
exit 0
