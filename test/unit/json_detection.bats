#!/usr/bin/env bash
# Unit tests for JSON tool detection ordering, overrides, and exec checks.

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

unset -f jq 2>/dev/null || true

test_create_tmpdir
ORIG_PATH="${PATH}"

reset_detection_state() {
	MCPBASH_MODE=""
	MCPBASH_JSON_TOOL=""
	MCPBASH_JSON_TOOL_BIN=""
	MCPBASH_FORCE_MINIMAL=false
	MCPBASH_LOG_JSON_TOOL="quiet"
}

stub_bin() {
	local dir="$1"
	local name="$2"
	local behavior="${3:-ok}"
	cat >"${dir}/${name}" <<'EOF'
#!/usr/bin/env bash
case "$1" in
--version)
EOF
if [ "${behavior}" = "hang" ]; then
	# Simulate a hung binary if a timeout wrapper is ever added; keep it short.
	cat >>"${dir}/${name}" <<'EOF'
	sleep 2
	exit 1
EOF
	elif [ "${behavior}" = "fail" ]; then
		cat >>"${dir}/${name}" <<'EOF'
	exit 1
EOF
	else
		cat >>"${dir}/${name}" <<'EOF'
	exit 0
EOF
	fi
	cat >>"${dir}/${name}" <<'EOF'
		;;
*)
	exit 0
		;;
esac
EOF
	chmod +x "${dir}/${name}"
}

BIN_JQ_GOJQ="${TEST_TMPDIR}/bin-jq-gojq"
mkdir -p "${BIN_JQ_GOJQ}"
stub_bin "${BIN_JQ_GOJQ}" jq
stub_bin "${BIN_JQ_GOJQ}" gojq

BIN_GOJQ_ONLY="${TEST_TMPDIR}/bin-gojq"
mkdir -p "${BIN_GOJQ_ONLY}"
stub_bin "${BIN_GOJQ_ONLY}" jq fail
stub_bin "${BIN_GOJQ_ONLY}" gojq

BIN_JQ_ONLY="${TEST_TMPDIR}/bin-jq"
mkdir -p "${BIN_JQ_ONLY}"
stub_bin "${BIN_JQ_ONLY}" jq

BIN_CUSTOM="${TEST_TMPDIR}/bin-custom"
mkdir -p "${BIN_CUSTOM}"
stub_bin "${BIN_CUSTOM}" myjson

printf ' -> jq preferred over gojq when both present\n'
reset_detection_state
PATH="${BIN_JQ_GOJQ}:/usr/bin:/bin"
hash -r
mcp_runtime_detect_json_tool
assert_eq "jq" "${MCPBASH_JSON_TOOL}" "expected jq to be selected"
assert_eq "${BIN_JQ_GOJQ}/jq" "${MCPBASH_JSON_TOOL_BIN}" "expected jq path from stub"

printf ' -> gojq used when jq absent\n'
reset_detection_state
PATH="${BIN_GOJQ_ONLY}:/usr/bin:/bin"
hash -r
mcp_runtime_detect_json_tool
assert_eq "gojq" "${MCPBASH_JSON_TOOL}" "expected gojq to be selected"
assert_eq "${BIN_GOJQ_ONLY}/gojq" "${MCPBASH_JSON_TOOL_BIN}" "expected gojq path from stub"

printf ' -> explicit override succeeds when binary is valid\n'
reset_detection_state
PATH="${BIN_JQ_GOJQ}:/usr/bin:/bin"
hash -r
MCPBASH_JSON_TOOL="gojq"
MCPBASH_JSON_TOOL_BIN="${BIN_JQ_GOJQ}/gojq"
mcp_runtime_detect_json_tool
assert_eq "gojq" "${MCPBASH_JSON_TOOL}" "expected override to keep gojq"
assert_eq "${BIN_JQ_GOJQ}/gojq" "${MCPBASH_JSON_TOOL_BIN}" "expected override bin to be used"

printf ' -> override missing binary falls back to jq\n'
reset_detection_state
PATH="${BIN_JQ_ONLY}:/usr/bin:/bin"
hash -r
MCPBASH_JSON_TOOL="gojq"
MCPBASH_JSON_TOOL_BIN=""
mcp_runtime_detect_json_tool
assert_eq "jq" "${MCPBASH_JSON_TOOL}" "expected fallback to jq when override missing"
assert_eq "${BIN_JQ_ONLY}/jq" "${MCPBASH_JSON_TOOL_BIN}" "expected jq path after fallback"

printf ' -> override none enters minimal mode\n'
reset_detection_state
PATH="${BIN_JQ_GOJQ}:/usr/bin:/bin"
hash -r
MCPBASH_JSON_TOOL="none"
mcp_runtime_detect_json_tool
assert_eq "minimal" "${MCPBASH_MODE}" "expected minimal mode when override requests none"
assert_eq "none" "${MCPBASH_JSON_TOOL}" "expected tool none when override requests none"

printf ' -> directory override falls back to jq\n'
reset_detection_state
PATH="${BIN_JQ_ONLY}:/usr/bin:/bin"
hash -r
MCPBASH_JSON_TOOL="gojq"
MCPBASH_JSON_TOOL_BIN="${TEST_TMPDIR}"
mcp_runtime_detect_json_tool
assert_eq "jq" "${MCPBASH_JSON_TOOL}" "expected jq after directory override fails"
assert_eq "${BIN_JQ_ONLY}/jq" "${MCPBASH_JSON_TOOL_BIN}" "expected jq path after fallback from directory override"

printf ' -> custom binary basename treated as jq-compatible\n'
reset_detection_state
PATH="${BIN_JQ_ONLY}:/usr/bin:/bin"
hash -r
unset MCPBASH_JSON_TOOL
MCPBASH_JSON_TOOL_BIN="${BIN_CUSTOM}/myjson"
mcp_runtime_detect_json_tool
assert_eq "jq" "${MCPBASH_JSON_TOOL}" "expected custom binary to be treated as jq-compatible"
assert_eq "${BIN_CUSTOM}/myjson" "${MCPBASH_JSON_TOOL_BIN}" "expected custom binary path to be used"

PATH="${ORIG_PATH}"

printf 'JSON detection tests passed.\n'
