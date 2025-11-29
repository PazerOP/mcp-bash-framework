#!/usr/bin/env bash
# Orchestrate unit-layer scripts with TAP-style status output.

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

UNIT_TESTS=()
while IFS= read -r path; do
	UNIT_TESTS+=("${path}")
done < <(find "${SCRIPT_DIR}" -maxdepth 1 -type f -name '*.bats' -print | sort)

if [ "${#UNIT_TESTS[@]}" -eq 0 ]; then
	printf '%s\n' "No unit tests discovered under ${SCRIPT_DIR}" >&2
	exit 1
fi

passed=0
failed=0
total="${#UNIT_TESTS[@]}"
index=1

for test_script in "${UNIT_TESTS[@]}"; do
	name="$(basename "${test_script}")"
	printf '[%02d/%02d] %s ... ' "${index}" "${total}" "${name}"
	if bash "${test_script}"; then
		printf '%s\n' "${PASS_ICON}"
		passed=$((passed + 1))
	else
		printf '%s\n' "${FAIL_ICON}" >&2
		failed=$((failed + 1))
	fi
	index=$((index + 1))
done

printf '\nUnit summary: %d passed, %d failed\n' "${passed}" "${failed}"

if [ "${failed}" -ne 0 ]; then
	exit 1
fi
