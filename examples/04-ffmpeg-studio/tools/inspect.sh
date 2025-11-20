#!/usr/bin/env bash
set -euo pipefail

# Handle SDK path if not set
if [ -z "${MCPBASH_SDK:-}" ]; then
	MCPBASH_SDK="$(cd "$(dirname "$0")/../../../sdk" && pwd)"
fi

# shellcheck source=../../../sdk/tool-sdk.sh disable=SC1091
source "${MCPBASH_SDK}/tool-sdk.sh"

# Validation: Check args
if [ $# -ne 1 ]; then
	mcp_tool_error -32602 "Missing required argument: path"
	exit 1
fi

FFMPEG_STUDIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/fs_guard.sh disable=SC1091
source "${FFMPEG_STUDIO_ROOT}/lib/fs_guard.sh"

if ! mcp_ffmpeg_guard_init "${FFMPEG_STUDIO_ROOT}"; then
	mcp_tool_error -32603 "Media guard initialization failed"
	exit 1
fi

path="$1"

if ! full_path="$(mcp_ffmpeg_guard_read_path "${path}")"; then
	mcp_tool_error -32602 "Access denied: ${path} is outside configured media roots"
	exit 1
fi

# Validation: File exists
if [ ! -f "${full_path}" ]; then
	mcp_tool_error -32602 "File not found: ${path}"
	exit 1
fi

# Run ffprobe
if ! output=$(ffprobe -v quiet -print_format json -show_format -show_streams "${full_path}" 2>/dev/null); then
	mcp_tool_error -32603 "Failed to inspect media file"
	exit 1
fi

mcp_emit_text "${output}"
