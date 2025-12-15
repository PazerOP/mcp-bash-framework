#!/usr/bin/env bash
# shellcheck disable=SC2034  # Used by test runner for reporting.
TEST_DESC="Windows/Git Bash: tool calls survive large environments (E2BIG mitigation)."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"

case "$(uname -s 2>/dev/null || printf '')" in
MINGW* | MSYS* | CYGWIN*) : ;;
*)
	# This test is specifically about MSYS/Git Bash exec limits.
	exit 0
	;;
esac

test_create_tmpdir

create_project_root() {
	local dest="$1"
	mkdir -p "${dest}/tools" "${dest}/resources" "${dest}/prompts" "${dest}/server.d"
}

inflate_environment() {
	# Build a large environment without breaking PATH resolution for mcp-bash.
	# Keep this deterministic and fast (CI on Windows can be slow).
	local i=0
	local base_path="${PATH:-}"
	local extra_path=""

	# Add many small PATH entries.
	while [ "${i}" -lt 800 ]; do
		extra_path="${extra_path}:/x${i}"
		i=$((i + 1))
	done
	PATH="${base_path}${extra_path}"
	export PATH

	# Add many exported variables with moderate-sized values.
	local payload="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
	i=0
	while [ "${i}" -lt 200 ]; do
		export "MCPBASH_TEST_ENV_DUMMY_${i}=${payload}"
		i=$((i + 1))
	done
}

ENV_ROOT="${TEST_TMPDIR}/env-size"
create_project_root "${ENV_ROOT}"
mkdir -p "${ENV_ROOT}/tools/ok"

cat <<'META' >"${ENV_ROOT}/tools/ok/tool.meta.json"
{
  "name": "env.size.ok",
  "description": "Returns ok",
  "arguments": {"type": "object", "properties": {}}
}
META

cat <<'SH' >"${ENV_ROOT}/tools/ok/tool.sh"
#!/usr/bin/env bash
set -euo pipefail
printf 'ok'
SH
chmod +x "${ENV_ROOT}/tools/ok/tool.sh"

cat <<'JSON' >"${ENV_ROOT}/requests.ndjson"
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"call","method":"tools/call","params":{"name":"env.size.ok","arguments":{}}}
JSON

(
	cd "${ENV_ROOT}" || exit 1
	inflate_environment

	# Minimal should be safe even with a large host environment.
	MCPBASH_TOOL_ENV_MODE="minimal" MCPBASH_PROJECT_ROOT="${ENV_ROOT}" mcp-bash <"requests.ndjson" >"responses_minimal.ndjson"

	# Allowlist should also be safe with a large host environment.
	MCPBASH_TOOL_ENV_MODE="allowlist" MCPBASH_TOOL_ENV_ALLOWLIST="MCPBASH_TEST_ENV_DUMMY_1" MCPBASH_PROJECT_ROOT="${ENV_ROOT}" mcp-bash <"requests.ndjson" >"responses_allowlist.ndjson"
)

minimal_resp="$(grep '"id":"call"' "${ENV_ROOT}/responses_minimal.ndjson" | head -n1)"
if echo "${minimal_resp}" | jq -e '.error' >/dev/null 2>&1; then
	test_fail "tool call failed in minimal mode under large env"
fi
minimal_text="$(echo "${minimal_resp}" | jq -r '(.result.content // [])[] | select(.type=="text") | .text' | head -n1)"
assert_contains "ok" "${minimal_text}" "expected ok from tool (minimal mode)"

allow_resp="$(grep '"id":"call"' "${ENV_ROOT}/responses_allowlist.ndjson" | head -n1)"
if echo "${allow_resp}" | jq -e '.error' >/dev/null 2>&1; then
	test_fail "tool call failed in allowlist mode under large env"
fi
allow_text="$(echo "${allow_resp}" | jq -r '(.result.content // [])[] | select(.type=="text") | .text' | head -n1)"
assert_contains "ok" "${allow_text}" "expected ok from tool (allowlist mode)"
