#!/usr/bin/env bash
# shellcheck disable=SC2034  # Used by test runner for reporting.
TEST_DESC="Icons support (SEP-973) in tools, resources, and prompts lists."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"

test_create_tmpdir

WORKROOT="${TEST_TMPDIR}/icons"
test_stage_workspace "${WORKROOT}"

# Remove register.sh to force auto-discovery
rm -f "${WORKROOT}/server.d/register.sh"

# Create tool with icons (including local file that should be converted to data URI)
mkdir -p "${WORKROOT}/tools/icon-tool"

# Create a local SVG icon file
cat <<'SVG' >"${WORKROOT}/tools/icon-tool/icon.svg"
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="6" fill="blue"/></svg>
SVG

cat <<'META' >"${WORKROOT}/tools/icon-tool/tool.meta.json"
{
  "name": "icon-tool",
  "description": "Tool with icons",
  "arguments": {"type": "object", "properties": {}},
  "icons": [
    {"src": "./icon.svg"},
    {"src": "https://example.com/icon.png", "mimeType": "image/png"}
  ]
}
META
cat <<'SH' >"${WORKROOT}/tools/icon-tool/tool.sh"
#!/usr/bin/env bash
printf '{"result":"ok"}'
SH
chmod +x "${WORKROOT}/tools/icon-tool/tool.sh"

# Create resource with icons
mkdir -p "${WORKROOT}/resources/icon-resource"
cat <<'META' >"${WORKROOT}/resources/icon-resource/resource.meta.json"
{
  "name": "icon-resource",
  "uri": "file:///icon-resource",
  "description": "Resource with icons",
  "mimeType": "text/plain",
  "icons": [
    {"src": "data:image/svg+xml,<svg/>"}
  ]
}
META
cat <<'SH' >"${WORKROOT}/resources/icon-resource/resource.sh"
#!/usr/bin/env bash
printf 'resource content'
SH
chmod +x "${WORKROOT}/resources/icon-resource/resource.sh"

# Create prompt with icons
mkdir -p "${WORKROOT}/prompts/icon-prompt"
cat <<'META' >"${WORKROOT}/prompts/icon-prompt/prompt.meta.json"
{
  "name": "icon-prompt",
  "description": "Prompt with icons",
  "icons": [
    {"src": "https://example.com/prompt-icon.png"}
  ]
}
META
cat <<'SH' >"${WORKROOT}/prompts/icon-prompt/prompt.sh"
#!/usr/bin/env bash
printf 'Hello from prompt'
SH
chmod +x "${WORKROOT}/prompts/icon-prompt/prompt.sh"

# Build requests
cat <<'JSON' >"${WORKROOT}/requests.ndjson"
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"tools-list","method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":"resources-list","method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":"prompts-list","method":"prompts/list","params":{}}
JSON

# Run server
(
	cd "${WORKROOT}" || exit 1
	MCPBASH_PROJECT_ROOT="${WORKROOT}" ./bin/mcp-bash <"${WORKROOT}/requests.ndjson" >"${WORKROOT}/responses.ndjson"
)

# Check tools/list for icons
tools_resp="$(grep '"id":"tools-list"' "${WORKROOT}/responses.ndjson" | head -n1)"
tool_icons="$(printf '%s' "${tools_resp}" | jq -r '.result.tools[] | select(.name=="icon-tool") | .icons | length')"
if [ "${tool_icons}" -lt 1 ]; then
	test_fail "tool should have icons array"
fi

# First icon should be converted to data URI from local file
tool_icon_src="$(printf '%s' "${tools_resp}" | jq -r '.result.tools[] | select(.name=="icon-tool") | .icons[0].src')"
if [[ "${tool_icon_src}" != data:image/svg* ]]; then
	test_fail "local icon file should be converted to data URI, got: ${tool_icon_src}"
fi

# Second icon should remain as HTTPS URL
tool_icon2_src="$(printf '%s' "${tools_resp}" | jq -r '.result.tools[] | select(.name=="icon-tool") | .icons[1].src')"
if [ "${tool_icon2_src}" != "https://example.com/icon.png" ]; then
	test_fail "HTTPS icon URL should be preserved, got: ${tool_icon2_src}"
fi

# Check resources/list for icons
resources_resp="$(grep '"id":"resources-list"' "${WORKROOT}/responses.ndjson" | head -n1)"
resource_icons="$(printf '%s' "${resources_resp}" | jq -r '.result.resources[] | select(.name=="icon-resource") | .icons | length')"
if [ "${resource_icons}" -lt 1 ]; then
	test_fail "resource should have icons array"
fi

# Check prompts/list for icons
prompts_resp="$(grep '"id":"prompts-list"' "${WORKROOT}/responses.ndjson" | head -n1)"
prompt_icons="$(printf '%s' "${prompts_resp}" | jq -r '.result.prompts[] | select(.name=="icon-prompt") | .icons | length')"
if [ "${prompt_icons}" -lt 1 ]; then
	test_fail "prompt should have icons array"
fi

printf 'Icons support (SEP-973) test passed\n'
