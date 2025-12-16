#!/usr/bin/env bash
# Unit tests for doctor managed-install upgrade flow (archive + verify).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=test/common/env.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/env.sh"
# shellcheck source=test/common/assert.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/assert.sh"

test_require_command jq
test_init_sha256_cmd

test_create_tmpdir

# Exit code contract (see `mcp-bash doctor --help`):
# 3 = policy refusal (used for downgrade refusal unless --allow-downgrade).
EXIT_POLICY_REFUSAL="3"

HOME_ROOT="${TEST_TMPDIR}/home"
export HOME="${HOME_ROOT}"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_BIN_HOME="${HOME}/.local/bin"
mkdir -p "${XDG_DATA_HOME}" "${XDG_BIN_HOME}"

MANAGED_ROOT="${XDG_DATA_HOME}/mcp-bash"
mkdir -p "${MANAGED_ROOT}"

printf ' -> seed managed install with old VERSION\n'
(
	cd "${REPO_ROOT}" || exit 1
	tar -cf - --exclude .git bin lib VERSION | (cd "${MANAGED_ROOT}" && tar -xf -)
)
printf '%s\n' '{"managed":true}' >"${MANAGED_ROOT}/INSTALLER.json"
printf '%s\n' "0.0.0" >"${MANAGED_ROOT}/VERSION"

printf ' -> build verified archive from repo\n'
ARCHIVE_STAGE="${TEST_TMPDIR}/archive-stage"
mkdir -p "${ARCHIVE_STAGE}/mcp-bash"
(
	cd "${REPO_ROOT}" || exit 1
	tar -cf - --exclude .git . | (cd "${ARCHIVE_STAGE}/mcp-bash" && tar -xf -)
)
ARCHIVE_PATH="${TEST_TMPDIR}/mcp-bash-test.tar.gz"
(cd "${ARCHIVE_STAGE}" && tar -czf "${ARCHIVE_PATH}" mcp-bash)
archive_sha="$("${TEST_SHA256_CMD[@]}" "${ARCHIVE_PATH}" | awk '{print $1}')"
min_version="$(tr -d '[:space:]' <"${REPO_ROOT}/VERSION")"

printf ' -> doctor --dry-run proposes upgrade\n'
set +e
"${MANAGED_ROOT}/bin/mcp-bash" doctor --dry-run --json --min-version "${min_version}" --archive "${ARCHIVE_PATH}" --verify "${archive_sha}" >"${TEST_TMPDIR}/dry.json" 2>/dev/null
rc=$?
set -e
assert_eq "0" "${rc}" "expected dry-run to succeed"
jq -e '.exitCode == 0' "${TEST_TMPDIR}/dry.json" >/dev/null
jq -e '.proposedActions | map(.id) | index("self.upgrade") != null' "${TEST_TMPDIR}/dry.json" >/dev/null

printf ' -> doctor --fix performs upgrade\n'
set +e
"${MANAGED_ROOT}/bin/mcp-bash" doctor --fix --json --min-version "${min_version}" --archive "${ARCHIVE_PATH}" --verify "${archive_sha}" >"${TEST_TMPDIR}/fix.json" 2>/dev/null
rc=$?
set -e
assert_eq "0" "${rc}" "expected fix to succeed"
jq -e '.exitCode == 0' "${TEST_TMPDIR}/fix.json" >/dev/null
jq -e '.actionsTaken | map(.id) | index("self.upgrade") != null' "${TEST_TMPDIR}/fix.json" >/dev/null

installed_version="$(tr -d '[:space:]' <"${MANAGED_ROOT}/VERSION")"
assert_eq "${min_version}" "${installed_version}" "managed install VERSION did not update"

printf ' -> doctor refuses downgrade without --allow-downgrade\n'
printf '%s\n' "9.9.9" >"${MANAGED_ROOT}/VERSION"
set +e
"${MANAGED_ROOT}/bin/mcp-bash" doctor --fix --json --archive "${ARCHIVE_PATH}" --verify "${archive_sha}" >"${TEST_TMPDIR}/downgrade_refuse.json" 2>/dev/null
rc=$?
set -e
assert_eq "${EXIT_POLICY_REFUSAL}" "${rc}" "expected policy refusal for downgrade without --allow-downgrade"
jq -e '.exitCode == 3' "${TEST_TMPDIR}/downgrade_refuse.json" >/dev/null
jq -e '.findings | map(.id) | index("self.upgrade_downgrade_refused") != null' "${TEST_TMPDIR}/downgrade_refuse.json" >/dev/null
installed_version="$(tr -d '[:space:]' <"${MANAGED_ROOT}/VERSION")"
assert_eq "9.9.9" "${installed_version}" "managed install VERSION should not change when downgrade is refused"

printf ' -> doctor allows downgrade with --allow-downgrade\n'
set +e
"${MANAGED_ROOT}/bin/mcp-bash" doctor --fix --json --allow-downgrade --archive "${ARCHIVE_PATH}" --verify "${archive_sha}" >"${TEST_TMPDIR}/downgrade_allow.json" 2>/dev/null
rc=$?
set -e
assert_eq "0" "${rc}" "expected downgrade to succeed with --allow-downgrade"
jq -e '.exitCode == 0' "${TEST_TMPDIR}/downgrade_allow.json" >/dev/null
installed_version="$(tr -d '[:space:]' <"${MANAGED_ROOT}/VERSION")"
assert_eq "${min_version}" "${installed_version}" "managed install VERSION did not update after allowed downgrade"

printf 'Doctor upgrade/downgrade tests passed.\n'
