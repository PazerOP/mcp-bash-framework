#!/usr/bin/env bash
# Unit: debug payload redaction should scrub secrets beyond params._meta.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=test/common/env.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/env.sh"
# shellcheck source=test/common/assert.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/assert.sh"

# shellcheck source=lib/io.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/lib/io.sh"

printf ' -> redacts secrets recursively (arguments + nested objects)\n'
payload='{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"t","arguments":{"password":"pw-123","nested":{"client_secret":"cs-456"},"headers":[{"Authorization":"Bearer abc.def.ghi"}]},"_meta":{"mcpbash/remoteToken":"rt-789"}}}'

MCPBASH_JSON_TOOL_BIN="${TEST_JSON_TOOL_BIN}"
MCPBASH_JSON_TOOL="$(basename "${TEST_JSON_TOOL_BIN}")"
case "${MCPBASH_JSON_TOOL}" in
jq | gojq) ;;
*) MCPBASH_JSON_TOOL="jq" ;;
esac
export MCPBASH_JSON_TOOL MCPBASH_JSON_TOOL_BIN

redacted="$(mcp_io_debug_redact_payload "${payload}")"

# Must stay parseable JSON when jq/gojq is available.
printf '%s' "${redacted}" | jq . >/dev/null 2>&1 || test_fail "expected redacted output to be valid JSON"

# Verify original secrets are gone.
if grep -q -- "pw-123" <<<"${redacted}"; then
	test_fail "password leaked in redacted payload"
fi
if grep -q -- "cs-456" <<<"${redacted}"; then
	test_fail "client_secret leaked in redacted payload"
fi
if grep -q -- "rt-789" <<<"${redacted}"; then
	test_fail "remote token leaked in redacted payload"
fi
# Bearer/JWT strings should be scrubbed.
if grep -q -- "abc.def.ghi" <<<"${redacted}"; then
	test_fail "bearer token leaked in redacted payload"
fi

printf ' -> sed fallback redacts common keys when JSON tooling is disabled\n'
MCPBASH_JSON_TOOL="none"
MCPBASH_JSON_TOOL_BIN=""
export MCPBASH_JSON_TOOL MCPBASH_JSON_TOOL_BIN
fallback='{"authorization":"Bearer should-not-appear","access_token":"at-1","refresh_token":"rt-1","client_secret":"cs-1","password":"pw-1"}'
fallback_redacted="$(mcp_io_debug_redact_payload "${fallback}")"
if grep -q -- "should-not-appear" <<<"${fallback_redacted}"; then
	test_fail "authorization leaked in sed fallback"
fi
if grep -q -- "at-1" <<<"${fallback_redacted}"; then
	test_fail "access_token leaked in sed fallback"
fi
if grep -q -- "cs-1" <<<"${fallback_redacted}"; then
	test_fail "client_secret leaked in sed fallback"
fi

printf 'io debug redaction tests passed.\n'

