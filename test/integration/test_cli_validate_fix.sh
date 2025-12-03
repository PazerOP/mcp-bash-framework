#!/usr/bin/env bash
# Integration: validate --fix and error paths.
# shellcheck disable=SC2034  # Used by test runner for reporting.
TEST_DESC="CLI validate detects issues and --fix repairs executables."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"

test_require_command jq

test_create_tmpdir
PROJECT_ROOT="${TEST_TMPDIR}/validate-demo"
mkdir -p "${PROJECT_ROOT}"

printf ' -> create project with valid server meta and tools\n'
mkdir -p "${PROJECT_ROOT}/server.d"
cat >"${PROJECT_ROOT}/server.d/server.meta.json" <<'META'
{
  "name": "validate-demo",
  "title": "Validate Demo"
}
META

mkdir -p "${PROJECT_ROOT}/tools/sample"
cat >"${PROJECT_ROOT}/tools/sample/tool.meta.json" <<'META'
{
  "name": "sample",
  "description": "Sample tool",
  "inputSchema": { "type": "object" }
}
META
cat >"${PROJECT_ROOT}/tools/sample/tool.sh" <<'SH'
echo "ok"
SH
chmod 644 "${PROJECT_ROOT}/tools/sample/tool.sh"

printf ' -> validate reports non-executable script\n'
set +e
output="$(
	cd "${PROJECT_ROOT}" && "${MCPBASH_TEST_ROOT}/bin/mcp-bash" validate 2>&1
)"
status=$?
set -e

if [ "${status}" -eq 0 ]; then
	test_fail "validate succeeded despite non-executable script"
fi
assert_contains "not executable" "${output}" "validate did not report non-executable script"

printf ' -> validate --fix makes script executable\n'
(
	cd "${PROJECT_ROOT}" && "${MCPBASH_TEST_ROOT}/bin/mcp-bash" validate --fix >/dev/null
)

if [ ! -x "${PROJECT_ROOT}/tools/sample/tool.sh" ]; then
	test_fail "validate --fix did not make tool.sh executable"
fi

printf ' -> validate --fix handles multiple scripts\n'
mkdir -p "${PROJECT_ROOT}/tools/extra" "${PROJECT_ROOT}/resources/example"
cat >"${PROJECT_ROOT}/tools/extra/tool.meta.json" <<'META'
{
  "name": "extra",
  "description": "Extra tool",
  "inputSchema": { "type": "object" }
}
META
cat >"${PROJECT_ROOT}/tools/extra/tool.sh" <<'SH'
echo "extra"
SH
chmod 644 "${PROJECT_ROOT}/tools/extra/tool.sh"

cat >"${PROJECT_ROOT}/resources/example/example.meta.json" <<'META'
{
  "name": "resource.example",
  "description": "Example resource",
  "uri": "file:///tmp/example.txt"
}
META
cat >"${PROJECT_ROOT}/resources/example/example.sh" <<'SH'
echo "resource"
SH
chmod 644 "${PROJECT_ROOT}/resources/example/example.sh"

(
	cd "${PROJECT_ROOT}" && "${MCPBASH_TEST_ROOT}/bin/mcp-bash" validate --fix >/dev/null
)

if [ ! -x "${PROJECT_ROOT}/tools/extra/tool.sh" ]; then
	test_fail "validate --fix did not make extra tool executable"
fi
if [ ! -x "${PROJECT_ROOT}/resources/example/example.sh" ]; then
	test_fail "validate --fix did not make resource script executable"
fi

printf 'CLI validate --fix test passed.\n'

