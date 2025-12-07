#!/usr/bin/env bash
set -euo pipefail

# Source SDK (MCP_SDK is set by the framework when running tools)
# shellcheck source=../../../../sdk/tool-sdk.sh disable=SC1091
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

json_bin="${MCPBASH_JSON_TOOL_BIN:-}"
if [[ -z "${json_bin}" ]] || ! command -v "${json_bin}" >/dev/null 2>&1; then
	mcp_fail -32603 "JSON tooling unavailable for elicitation parsing"
fi

confirm_resp="$(mcp_elicit_confirm "Do you want to proceed with the demo?")"
confirm_fields="$("${json_bin}" -r '[.action, (.content.confirmed // false)] | @tsv' <<<"${confirm_resp}")"
confirm_action="${confirm_fields%%$'\t'*}"

if [[ "${confirm_action}" != "accept" ]]; then
	mcp_emit_text "Stopped: elicitation action=${confirm_action}"
	exit 0
fi

mode_resp="$(mcp_elicit_choice "Pick a mode" "explore" "safe" "expert")"
mode_fields="$("${json_bin}" -r '[.action, (.content.choice // empty)] | @tsv' <<<"${mode_resp}")"
mode_action="${mode_fields%%$'\t'*}"
mode_choice="${mode_fields#*$'\t'}"

if [[ "${mode_action}" != "accept" ]]; then
	mcp_emit_text "Stopped after confirm: elicitation action=${mode_action}"
	exit 0
fi

mcp_emit_text "Elicitation complete: mode=${mode_choice}"
