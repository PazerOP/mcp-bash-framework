# Changelog

## 0.1.0 - unreleased

- Initial public release of mcp-bash (stdio MCP server targeting MCP 2025-06-18 with negotiated downgrades).
- Tool/resource/prompt discovery with registry TTLs and list_changed notifications.
- Manual registration hooks for tools, resources, prompts, and completions via `server.d/register.sh`.
- Resource subscriptions with polling updates; file/git/https providers included.
- Completion support (manual registration) with cursor pagination and rate limits.
- Error handling tightened (timeouts now emit `-32603` by policy); output/stderr size caps enforced.
