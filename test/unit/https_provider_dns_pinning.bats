#!/usr/bin/env bash
# Unit: HTTPS provider pins DNS resolution with curl --resolve to prevent
# DNS-rebinding TOCTOU between "check host/IPs" and the actual fetch.

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

# Minimal policy shim so the provider sources our resolver.
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
	printf '%s' "${authority%%:*}" | tr '[:upper:]' '[:lower:]'
}
mcp_policy_host_is_private() { return 1; }
mcp_policy_host_allowed() { return 0; }
mcp_policy_resolve_ips() {
	# Provide two public IPs; fake curl will fail the first and succeed the second.
	printf '%s\n' "203.0.113.10" "203.0.113.11"
}
EOF

BIN_DIR="${TEST_TMPDIR}/bin"
mkdir -p "${BIN_DIR}"

CALLS_FILE="${TEST_TMPDIR}/curl.calls"
STATE_FILE="${TEST_TMPDIR}/curl.state"
: >"${CALLS_FILE}"
: >"${STATE_FILE}"

# Fake curl: record argv; fail first call, succeed second; write output file.
cat >"${BIN_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

calls_file="${CALLS_FILE:?}"
state_file="${STATE_FILE:?}"

printf '%s\n' "$*" >>"${calls_file}"

out=""
prev=""
for a in "$@"; do
	if [ "${prev}" = "-o" ]; then
		out="${a}"
	fi
	prev="${a}"
done
if [ -n "${out}" ]; then
	printf 'ok\n' >"${out}"
fi

n=0
if [ -f "${state_file}" ]; then
	n="$(cat "${state_file}" 2>/dev/null || printf '0')"
fi
n=$((n + 1))
printf '%s' "${n}" >"${state_file}"

if [ "${n}" -eq 1 ]; then
	exit 7
fi
exit 0
EOF
chmod 700 "${BIN_DIR}/curl"

printf ' -> pins curl to resolved IPs with --resolve and retries\n'
set +e
PATH="${BIN_DIR}:${PATH}" \
	CALLS_FILE="${CALLS_FILE}" \
	STATE_FILE="${STATE_FILE}" \
	MCPBASH_HOME="${FAKE_HOME}" \
	MCPBASH_HTTPS_ALLOW_ALL="true" \
	bash "${PROVIDER}" "https://example.com:8443/path" >/dev/null 2>&1
rc=$?
set -e
assert_eq "0" "${rc}" "expected provider to succeed after retrying pinned IPs"

calls="$(cat "${CALLS_FILE}")"
assert_contains "--resolve example.com:8443:203.0.113.10" "${calls}" "expected --resolve for first IP"
assert_contains "--resolve example.com:8443:203.0.113.11" "${calls}" "expected retry with --resolve for second IP"

printf 'https provider DNS pinning tests passed.\n'

