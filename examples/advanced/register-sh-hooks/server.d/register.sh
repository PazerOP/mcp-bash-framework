#!/usr/bin/env bash
# Advanced hook example: dynamic/imperative registration.
#
# SECURITY:
# - This file is shell code that runs during registry refresh (often during list calls).
# - It executes only when MCPBASH_ALLOW_PROJECT_HOOKS=true and ownership/perms are safe.
# - Avoid side effects: do not perform network calls, file writes, or spawn background processes.
#
# Prefer server.d/register.json for data-only registration.

set -euo pipefail

# Register completions imperatively.
mcp_completion_manual_begin
mcp_completion_register_manual '{"name":"demo.completion","path":"completions/suggest.sh","timeoutSecs":5}'

case "${DEMO_ENABLE_ALT_COMPLETION:-false}" in
true | 1 | yes | on)
	mcp_completion_register_manual '{"name":"demo.completion.alt","path":"completions/alt.sh","timeoutSecs":5}'
	;;
esac
mcp_completion_manual_finalize

# Register a resource template imperatively.
mcp_resources_templates_manual_begin
mcp_resources_templates_register_manual '{"name":"logs-by-date","title":"Logs by Date","uriTemplate":"file:///var/log/{service}/{date}.log","description":"Access log files by service and date"}'
mcp_resources_templates_manual_finalize
