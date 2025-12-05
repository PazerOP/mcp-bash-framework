#!/usr/bin/env bash
# shellcheck disable=SC2034  # Used by test runner for reporting.
TEST_DESC="run-tool CLI smoke (dry-run, roots wiring)."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"

test_create_tmpdir
PROJECT_ROOT="${TEST_TMPDIR}/proj"
mkdir -p "${PROJECT_ROOT}/tools/echo" "${PROJECT_ROOT}/server.d"
export MCPBASH_PROJECT_ROOT="${PROJECT_ROOT}"

cat >"${PROJECT_ROOT}/server.d/server.meta.json" <<'EOF'
{"name":"cli-runner"}
EOF

cat >"${PROJECT_ROOT}/tools/echo/tool.meta.json" <<'EOF'
{
  "name": "cli.echo",
  "description": "Echo with roots info",
  "inputSchema": {
    "type": "object",
    "properties": {
      "value": { "type": "string" }
    }
  },
  "outputSchema": {
    "type": "object",
    "required": ["message"],
    "properties": {
      "message": { "type": "string" }
    }
  }
}
EOF

marker="${PROJECT_ROOT}/.should-not-exist"
cat >"${PROJECT_ROOT}/tools/echo/tool.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
value="ok"
if command -v jq >/dev/null 2>&1 && [ -n "\${MCP_TOOL_ARGS_JSON:-}" ]; then
	value="\$(printf '%s' "\${MCP_TOOL_ARGS_JSON}" | jq -r '.value // "ok"' 2>/dev/null || printf 'ok')"
fi
root_count="\${MCP_ROOTS_COUNT:-0}"
first_root="\$(printf '%s' "\${MCP_ROOTS_PATHS:-}" | head -n1)"
printf '{"message":"%s","rootCount":"%s","firstRoot":"%s"}' "\${value}" "\${root_count}" "\${first_root}"
EOF
chmod +x "${PROJECT_ROOT}/tools/echo/tool.sh"

printf ' -> dry-run does not execute tool\n'
"${MCPBASH_HOME}/bin/mcp-bash" run-tool cli.echo --dry-run
if [ -e "${marker}" ]; then
	test_fail "dry-run should not run tool script"
fi

printf ' -> roots wiring with direct invocation\n'
root_path="${PROJECT_ROOT}/roots-one"
mkdir -p "${root_path}"
set +e
output="$("${MCPBASH_HOME}/bin/mcp-bash" run-tool cli.echo --args '{"value":"hello"}' --roots "${root_path}")"
status=$?
set -e
if [ "${status}" -ne 0 ]; then
	printf 'run-tool returned non-zero status (%s):\n%s\n' "${status}" "${output}" >&2
	exit 1
fi
result_line="$(printf '%s\n' "${output}" | tail -n1)"
message="$(printf '%s\n' "${result_line}" | jq -r '.structuredContent.message // empty')"
rcount="$(printf '%s\n' "${result_line}" | jq -r '.structuredContent.rootCount // 0')"

assert_eq "hello" "${message}" "run-tool did not return expected message"
assert_eq "1" "${rcount}" "run-tool did not populate roots count"

printf 'run-tool CLI smoke passed.\n'
