#!/usr/bin/env bash
# Integration: init, config, and doctor happy path.
# shellcheck disable=SC2034  # Used by test runner for reporting.
TEST_DESC="CLI init, config, and doctor work end-to-end."

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
PROJECT_DIR="${TEST_TMPDIR}/git-sorcerer"
mkdir -p "${PROJECT_DIR}"

printf ' -> init project\n'
(
	cd "${PROJECT_DIR}" || exit 1
	"${MCPBASH_TEST_ROOT}/bin/mcp-bash" init --name git-sorcerer >/dev/null
)

assert_file_exists "${PROJECT_DIR}/server.d/server.meta.json"
assert_file_exists "${PROJECT_DIR}/tools/hello/tool.sh"
assert_file_exists "${PROJECT_DIR}/tools/hello/tool.meta.json"
assert_file_exists "${PROJECT_DIR}/.gitignore"

if ! jq -e '.name == "git-sorcerer"' "${PROJECT_DIR}/server.d/server.meta.json" >/dev/null; then
	test_fail "server.meta.json does not contain expected server name"
fi

printf ' -> validate project\n'
(
	cd "${PROJECT_DIR}" || exit 1
	"${MCPBASH_TEST_ROOT}/bin/mcp-bash" validate >/dev/null
)

printf ' -> config --json\n'
config_json="$(
	cd "${PROJECT_DIR}" || exit 1
	"${MCPBASH_TEST_ROOT}/bin/mcp-bash" config --json
)"

if ! printf '%s' "${config_json}" | jq -e '.name == "git-sorcerer"' >/dev/null; then
	test_fail "config --json name mismatch"
fi

canonical_root="$(cd "${PROJECT_DIR}" && (pwd -P 2>/dev/null || pwd))"
if ! printf '%s' "${config_json}" | jq -e --arg root "${canonical_root}" '.env.MCPBASH_PROJECT_ROOT == $root' >/dev/null; then
	test_fail "config --json MCPBASH_PROJECT_ROOT does not match project directory"
fi

printf ' -> doctor\n'
(
	cd "${PROJECT_DIR}" || exit 1
	"${MCPBASH_TEST_ROOT}/bin/mcp-bash" doctor >/dev/null
)

printf 'CLI init/config/doctor test passed.\n'
