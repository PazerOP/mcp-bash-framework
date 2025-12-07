#!/usr/bin/env bash
# Integration: unsupported protocol version should return -32602.
# shellcheck disable=SC2034  # Used by test runner for reporting.
TEST_DESC="Unsupported protocol versions return -32602 errors."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

cat <<'JSON' >"${TMP}/requests.ndjson"
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{"protocolVersion":"2024-10-07"}}
JSON

"${MCPBASH_HOME}/examples/run" 00-hello-tool <"${TMP}/requests.ndjson" >"${TMP}/responses.ndjson" || true

init_code="$(jq -r 'select(.id=="init") | .error.code // empty' "${TMP}/responses.ndjson")"
init_message="$(jq -r 'select(.id=="init") | .error.message // empty' "${TMP}/responses.ndjson")"

test_assert_eq "${init_code}" "-32602"
if [[ "${init_message}" != *"Unsupported protocol version"* ]]; then
	test_fail "unexpected error message for unsupported protocol: ${init_message}"
fi
# Should include the requested version and supported versions in the message
if [[ "${init_message}" != *"2024-10-07"* ]]; then
	test_fail "error message should include the unsupported version requested: ${init_message}"
fi
if [[ "${init_message}" != *"Supported:"* ]]; then
	test_fail "error message should list supported versions: ${init_message}"
fi

printf 'Protocol reject unknown version test passed.\n'
