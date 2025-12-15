#!/usr/bin/env bash
# Ensure JSON error logs never include raw payloads.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=test/common/env.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/env.sh"
# shellcheck source=test/common/assert.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/assert.sh"

# shellcheck source=lib/runtime.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/lib/runtime.sh"
# shellcheck source=lib/json.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/lib/json.sh"

MCPBASH_FORCE_MINIMAL=false
mcp_runtime_detect_json_tool
if [ "${MCPBASH_MODE}" = "minimal" ]; then
	test_fail "JSON tooling unavailable for error logging test"
fi

printf ' -> JSON parse failure logs are bounded/single-line\n'
padding="$(printf 'x%.0s' {1..1500})"
secret="Authorization: Bearer SHOULD_NOT_APPEAR"
# Invalid JSON (unterminated string), with an early newline and a large prefix to
# ensure the secret is beyond the excerpt cap.
payload_prefix=$'{"a":"NL_TEST\n'
payload="${payload_prefix}${padding}${secret}"

set +e
output="$(mcp_json_normalize_line "${payload}" 2>&1)"
rc=$?
set -e

if [ "${rc}" -eq 0 ]; then
	test_fail "expected normalization to fail for invalid JSON"
fi

# Single-line invariant: command substitution strips trailing newlines; any
# remaining newline indicates log injection / unsafe excerpt handling.
case "${output}" in
*$'\n'*)
	test_fail "expected a single-line stderr log summary"
	;;
esac

# Must not include the secret (it's beyond the excerpt limit).
if grep -q -- "${secret}" <<<"${output}"; then
	test_fail "secret leaked in error log output"
fi

# Should include structured fields.
if ! grep -q -- 'JSON normalization failed' <<<"${output}"; then
	test_fail "missing expected prefix in error log output"
fi
if ! grep -q -- 'bytes=' <<<"${output}"; then
	test_fail "missing bytes field in error log output"
fi
if ! grep -q -- 'sha256=' <<<"${output}"; then
	test_fail "missing sha256 field in error log output"
fi
if ! grep -q -- 'truncated=' <<<"${output}"; then
	test_fail "missing truncated field in error log output"
fi
if ! grep -q -- 'excerpt="' <<<"${output}"; then
	test_fail "missing excerpt field in error log output"
fi

printf ' -> regression guard: no raw payload printf remains\n'
# SECURITY: prevent reintroducing raw `${json}`/`${line}` in error-path printf statements.
if grep -E "printf '.*failed for: %s.*'\\s+\\\"\\$\\{(json|line)\\}\\\"" "${REPO_ROOT}/lib/json.sh" >/dev/null 2>&1; then
	test_fail "found raw payload logging pattern in lib/json.sh"
fi

printf 'json error logging tests passed.\n'

