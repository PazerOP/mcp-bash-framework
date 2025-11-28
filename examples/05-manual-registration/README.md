# Manual registration, live progress, and custom providers

This example bundles three advanced behaviours:

- `server.d/register.sh` replaces auto-discovery with curated tool/resource/prompt entries.
- `tools/progress-demo.sh` emits progress updates; export `MCPBASH_ENABLE_LIVE_PROGRESS=true` to stream them during execution.
- `resources/echo-placeholder.txt` demonstrates a custom `echo://` provider implemented in `providers/echo.sh`.

## Running the example
1. `export MCPBASH_PROJECT_ROOT=$(pwd)/examples/05-manual-registration`
2. `export MCPBASH_ENABLE_LIVE_PROGRESS=true` (optional) and start the server: `bin/mcp-bash`.
3. Use your MCP client to call:
   - Tool: `manual.progress` (observe progress streaming if live mode is enabled).
   - Resource: `echo.hello` (returns the payload from the `echo://` URI via the custom provider).
   - Prompt: `manual.prompt` (accepts optional `topic`).

Manual registration output lives entirely in `server.d/register.sh`, so `.registry/*.json` is regenerated from that JSON without scanning `tools/`/`resources/`/`prompts/`.
