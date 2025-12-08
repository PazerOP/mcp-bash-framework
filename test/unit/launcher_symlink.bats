#!/usr/bin/env bash
# Ensure the launcher resolves symlinks so ~/.local/bin/mcp-bash works.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=test/common/env.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/env.sh"
# shellcheck source=test/common/assert.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/assert.sh"

test_create_tmpdir

PROJECT_ROOT="${TEST_TMPDIR}/proj"
mkdir -p "${PROJECT_ROOT}/server.d" "${PROJECT_ROOT}/tools/hello"
ln -sf "${REPO_ROOT}/bin/mcp-bash" "${TEST_TMPDIR}/mcp-bash"

cat >"${PROJECT_ROOT}/server.d/server.meta.json" <<'EOF'
{"name":"symlink-launcher-test"}
EOF

cat >"${PROJECT_ROOT}/tools/hello/tool.meta.json" <<'EOF'
{
  "name": "hello",
  "description": "Hello tool",
  "inputSchema": {"type": "object", "properties": {}}
}
EOF

cat >"${PROJECT_ROOT}/tools/hello/tool.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK}/tool-sdk.sh"
mcp_emit_json "$(mcp_json_obj ok true)"
EOF
chmod +x "${PROJECT_ROOT}/tools/hello/tool.sh"

printf ' -> launcher resolves symlink and finds libs\n'
if ! "${TEST_TMPDIR}/mcp-bash" validate --project-root "${PROJECT_ROOT}" --json >/dev/null 2>&1; then
	test_fail "validate via symlinked launcher should succeed"
fi

printf 'Launcher symlink test passed.\n'
