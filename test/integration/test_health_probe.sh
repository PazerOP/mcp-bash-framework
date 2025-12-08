#!/usr/bin/env bash
# Integration: health/readiness probe behavior.
# shellcheck disable=SC2034  # Used by test runner for reporting.
TEST_DESC="Health probe exits 0 on ready, 2 on missing project, and avoids registry writes."

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
WORKSPACE="${TEST_TMPDIR}/health"
test_stage_workspace "${WORKSPACE}"

# Ready probe: should exit 0, emit status ok, and avoid registry cache writes.
OUT="${WORKSPACE}/health.json"
set +e
(cd "${WORKSPACE}" && MCPBASH_PROJECT_ROOT="${WORKSPACE}" ./bin/mcp-bash --health >"${OUT}")
rc=$?
set -e

assert_eq "0" "${rc}" "health probe should exit 0 when ready"
status="$(jq -r '.status // ""' "${OUT}")"
assert_eq "ok" "${status}" "health status should be ok"

if [ -f "${WORKSPACE}/.registry/tools.json" ] || [ -f "${WORKSPACE}/.registry/resources.json" ] || [ -f "${WORKSPACE}/.registry/prompts.json" ]; then
	test_fail "health probe should not write registry cache files"
fi

# Missing project root should return 2.
set +e
(cd "${WORKSPACE}" && ./bin/mcp-bash --health --project-root "${WORKSPACE}/nope" >/dev/null)
rc_missing=$?
set -e
assert_eq "2" "${rc_missing}" "health probe should exit 2 for missing project root"

printf 'Health probe integration passed.\n'
