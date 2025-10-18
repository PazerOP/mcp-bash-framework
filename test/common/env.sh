#!/usr/bin/env bash
# Shared test environment helpers.

set -euo pipefail

# Root of the repository.
MCPBASH_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Export canonical environment variables consumed by the server and helpers.
export MCPBASH_ROOT="${MCPBASH_TEST_ROOT}"
export PATH="${MCPBASH_ROOT}/bin:${PATH}"

test_create_tmpdir() {
	local dir
	dir="$(mktemp -d)"
	TEST_TMPDIR="${dir}"
	trap 'rm -rf "${TEST_TMPDIR:-}"' EXIT INT TERM
}

test_cleanup_tmpdir() {
	if [ -n "${TEST_TMPDIR:-}" ] && [ -d "${TEST_TMPDIR}" ]; then
		rm -rf "${TEST_TMPDIR}"
	fi
}
