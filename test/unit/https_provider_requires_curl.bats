#!/usr/bin/env bash
# Unit: HTTPS provider requires curl (wget fallback removed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=test/common/assert.sh
# shellcheck disable=SC1091
. "${REPO_ROOT}/test/common/assert.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mcpbash-test.XXXXXX")"
export TEST_TMPDIR
trap 'rm -rf "${TEST_TMPDIR}" 2>/dev/null || true' EXIT

PROVIDER="${REPO_ROOT}/providers/https.sh"

FAKE_HOME="${TEST_TMPDIR}/home"
mkdir -p "${FAKE_HOME}/lib"

# Minimal policy shim so the provider doesn't depend on system DNS tools.
cat >"${FAKE_HOME}/lib/policy.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mcp_policy_normalize_host() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
mcp_policy_extract_host_from_url() {
	local url="$1"
	local authority="${url#*://}"
	authority="${authority%%/*}"
	authority="${authority%%\?*}"
	authority="${authority%%\#*}"
	authority="${authority##*@}"
	local host="${authority%%:*}"
	printf '%s' "${host}" | tr '[:upper:]' '[:lower:]'
}
mcp_policy_host_is_private() { return 1; }
mcp_policy_host_allowed() { return 0; }
mcp_policy_resolve_ips() { printf '%s\n' "203.0.113.10"; }
EOF

BIN_DIR="${TEST_TMPDIR}/bin"
mkdir -p "${BIN_DIR}"

# Provide mktemp without putting /usr/bin on PATH (macOS curl lives in /usr/bin).
cat >"${BIN_DIR}/mktemp" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/mktemp "$@"
EOF
chmod 700 "${BIN_DIR}/mktemp"

# Minimal coreutils shims (provider/policy use tr/grep).
cat >"${BIN_DIR}/tr" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/tr "$@"
EOF
chmod 700 "${BIN_DIR}/tr"

cat >"${BIN_DIR}/grep" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/grep "$@"
EOF
chmod 700 "${BIN_DIR}/grep"

# Provide a wget stub to prove we don't call it (curl is required).
WGET_CALLED_FILE="${TEST_TMPDIR}/wget.called"
cat >"${BIN_DIR}/wget" <<EOF
#!/usr/bin/env bash
set -euo pipefail
: >"${WGET_CALLED_FILE:?}"
exit 0
EOF
chmod 700 "${BIN_DIR}/wget"

stderr_file="${TEST_TMPDIR}/stderr.txt"
: >"${stderr_file}"

printf ' -> fails closed when curl is missing, even if wget exists\n'
set +e
PATH="${BIN_DIR}:/bin" \
	MCPBASH_HOME="${FAKE_HOME}" \
	MCPBASH_HTTPS_ALLOW_ALL="true" \
	/bin/bash "${PROVIDER}" "https://example.com/" 1>/dev/null 2>"${stderr_file}"
rc=$?
set -e

assert_eq "4" "${rc}" "expected exit 4 when curl is missing"
if ! grep -q "curl is required" "${stderr_file}"; then
	test_fail "expected missing-curl error message"
fi
if [ -f "${WGET_CALLED_FILE}" ]; then
	test_fail "wget should not be called when curl is required"
fi

printf 'https provider requires curl tests passed.\n'

