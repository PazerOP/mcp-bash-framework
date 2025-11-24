#!/usr/bin/env bash
set -euo pipefail
set -x

MCPBASH_HOME="$(pwd)"
export MCPBASH_HOME
MCPBASH_TMP_ROOT="$(mktemp -d)"
export MCPBASH_TMP_ROOT
export MCPBASH_PROJECT_ROOT="${MCPBASH_TMP_ROOT}"
export MCPBASH_REGISTRY_DIR="${MCPBASH_TMP_ROOT}/.registry"
export MCPBASH_TOOLS_DIR="${MCPBASH_TMP_ROOT}/tools"

mkdir -p "${MCPBASH_REGISTRY_DIR}"
mkdir -p "${MCPBASH_TOOLS_DIR}"

echo "HOME: ${MCPBASH_HOME}"
echo "PROJECT_ROOT: ${MCPBASH_PROJECT_ROOT}"

. lib/runtime.sh
. lib/json.sh
. lib/tools.sh
. lib/logging.sh
. lib/io.sh

# Create a dummy tool in the project
cat <<'EOF' >"${MCPBASH_TOOLS_DIR}/smoke.sh"
#!/bin/bash
echo "Hello from smoke tool"
EOF
chmod +x "${MCPBASH_TOOLS_DIR}/smoke.sh"

# Register it manually to bypass scanning for now
MCP_TOOLS_REGISTRY_JSON='{"version":1,"items":[{"name":"smoke.echo","path":"smoke.sh","inputSchema":{},"timeoutSecs":null}],"total":1}'
MCP_TOOLS_REGISTRY_HASH="dummy"

mcp_tools_metadata_for_name() {
	echo "{\"name\":\"smoke.echo\",\"path\":\"smoke.sh\",\"inputSchema\":{},\"timeoutSecs\":null}"
}

# Call it
result=$(mcp_tools_call "smoke.echo" "{}" "")
echo "Result: $result"

rm -rf "${MCPBASH_TMP_ROOT}"
