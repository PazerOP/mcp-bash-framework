#!/usr/bin/env bash
set -euo pipefail

mcp_completion_manual_begin
mcp_completion_register_manual '{"name":"demo.completion","path":"completions/suggest.sh","timeoutSecs":5}'
mcp_completion_manual_finalize
