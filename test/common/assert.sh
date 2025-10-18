#!/usr/bin/env bash
# Lightweight assertion helpers for shell tests.

set -euo pipefail

test_fail() {
	local message="${1:-assertion failed}"
	printf 'ASSERTION FAILED: %s\n' "${message}" >&2
	exit 1
}

assert_eq() {
	local expected="$1"
	local actual="$2"
	local message="${3:-expected ${expected}, got ${actual}}"
	if [ "${expected}" != "${actual}" ]; then
		test_fail "${message}"
	fi
}

assert_contains() {
	local needle="$1"
	local haystack="$2"
	local message="${3:-expected to find \"${needle}\" in ${haystack}}"
	if ! grep -q "${needle}" "${haystack}"; then
		test_fail "${message}"
	fi
}
