#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${MCP_SDK:-}" ] || [ ! -f "${MCP_SDK}/tool-sdk.sh" ]; then
	if fallback_sdk="$(cd "${script_dir}/../../../sdk" 2>/dev/null && pwd)"; then
		if [ -f "${fallback_sdk}/tool-sdk.sh" ]; then
			MCP_SDK="${fallback_sdk}"
		fi
	fi
fi

if [ -z "${MCP_SDK:-}" ] || [ ! -f "${MCP_SDK}/tool-sdk.sh" ]; then
	printf 'mcp: SDK helpers not found (expected %s/tool-sdk.sh)\n' "${MCP_SDK:-<unset>}" >&2
	exit 1
fi

# shellcheck source=../../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK}/tool-sdk.sh"

confirm_resp="$(mcp_elicit_confirm "Do you want to proceed with the demo?")"
confirm_action="$(printf '%s' "${confirm_resp}" | jq -r '.action')"

if [ "${confirm_action}" != "accept" ]; then
	mcp_emit_text "Stopped: elicitation action=${confirm_action}"
	exit 0
fi

mode_resp="$(mcp_elicit_choice "Pick a mode" "explore" "safe" "expert")"
mode_action="$(printf '%s' "${mode_resp}" | jq -r '.action')"

if [ "${mode_action}" != "accept" ]; then
	mcp_emit_text "Stopped after confirm: elicitation action=${mode_action}"
	exit 0
fi

choice="$(printf '%s' "${mode_resp}" | jq -r '.content.choice')"
mcp_emit_text "Elicitation complete: mode=${choice}"
