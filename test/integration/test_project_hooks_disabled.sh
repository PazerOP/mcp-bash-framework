#!/usr/bin/env bash
# shellcheck disable=SC2034  # Used by test runner for reporting.
TEST_DESC="Project hooks disabled (MCPBASH_ALLOW_PROJECT_HOOKS=false) should not be treated as an error."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"

test_create_tmpdir

WORKSPACE="${TEST_TMPDIR}/workspace"
test_stage_workspace "${WORKSPACE}"

# Ensure a register.sh exists so mcp_registry_register_apply hits the "skipped"
# path when hooks are disabled (instead of "no script").
cat >"${WORKSPACE}/server.d/register.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Intentionally no registrations.
exit 0
EOF
chmod +x "${WORKSPACE}/server.d/register.sh"

mkdir -p "${WORKSPACE}/prompts"
cat >"${WORKSPACE}/prompts/demo.txt" <<'EOF'
demo
EOF
cat >"${WORKSPACE}/prompts/demo.meta.json" <<'EOF'
{
  "name": "demo-prompt",
  "description": "Demo prompt",
  "path": "demo.txt",
  "arguments": {"type":"object","properties":{}}
}
EOF

REQUESTS="${WORKSPACE}/requests.ndjson"
RESPONSES="${WORKSPACE}/responses.ndjson"
cat >"${REQUESTS}" <<'JSON'
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"list","method":"prompts/list","params":{"limit":50}}
JSON

MCPBASH_ALLOW_PROJECT_HOOKS=false test_run_mcp "${WORKSPACE}" "${REQUESTS}" "${RESPONSES}"

assert_json_lines "${RESPONSES}"

found_name="$(jq -r 'select(.id=="list") | .result.prompts[].name // empty' "${RESPONSES}" | grep -Fx "demo-prompt" || true)"
if [ -z "${found_name}" ]; then
	test_fail "expected demo-prompt to be discoverable even when project hooks are disabled"
fi

printf 'Project hooks disabled test passed.\n'
