#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERBOSE="${VERBOSE:-0}"
UNICODE="${UNICODE:-0}"

if [ -z "${MCPBASH_LOG_JSON_TOOL:-}" ] && [ "${VERBOSE}" != "1" ]; then
	MCPBASH_LOG_JSON_TOOL="quiet"
	export MCPBASH_LOG_JSON_TOOL
fi

PASS_ICON="[PASS]"
FAIL_ICON="[FAIL]"
if [ "${UNICODE}" = "1" ]; then
	PASS_ICON="✅"
	FAIL_ICON="❌"
fi

printf '[01/01] examples/test_examples.sh ... '
if "${SCRIPT_DIR}/test_examples.sh"; then
	printf '%s\n' "${PASS_ICON}"
else
	printf '%s\n' "${FAIL_ICON}" >&2
	exit 1
fi

printf '\nExamples summary: 1 passed, 0 failed\n'
