#!/usr/bin/env bash
# Unit layer: path normalization helpers (lib/path.sh).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=test/common/env.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/env.sh"
# shellcheck source=test/common/assert.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/assert.sh"

# shellcheck source=lib/path.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/lib/path.sh"

test_create_tmpdir
cd "${TEST_TMPDIR}"
mkdir -p base/dir

printf ' -> collapses relative with dot-dot relative to PWD\n'
cd "${TEST_TMPDIR}/base/dir"
collapsed="$(mcp_path_collapse '../../..')"
expected_collapse="$(cd ../../.. && pwd)"
assert_eq "${expected_collapse}" "${collapsed}" "expected collapse to follow PWD"

printf ' -> normalize relative dot-dot to absolute path\n'
normalized="$(mcp_path_normalize "../dir")"
expected_norm="$(cd . && pwd -P)"
assert_eq "${expected_norm}" "${normalized}" "expected normalize to resolve relative path"

printf ' -> empty normalize resolves to PWD when resolver exists\n'
empty_norm="$(mcp_path_normalize '')"
assert_eq "$(pwd -P)" "${empty_norm}" "empty path should normalize to PWD"

printf 'path normalization tests passed.\n'
