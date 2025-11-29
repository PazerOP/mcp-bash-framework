# Elicitation Support in mcp-bash

Elicitation lets a tool pause execution, ask the MCP client for user input, and continue once a response arrives. It is supported when the client advertises `capabilities.elicitation` during `initialize`.

## Server Behavior
- On initialize, the server records whether the client supports elicitation.
- While tools run, the server polls for tool-written request files (`elicit.<key>.request`) and forwards them to the client as `elicitation/create` requests.
- Client responses are normalized to `{"action": "...", "content": ...}` and written to `elicit.<key>.response`.
- Requests pending per-worker are tracked so cancellation/cleanup can discard stale requests and late responses.

## Tool SDK
The SDK exposes helpers in `sdk/tool-sdk.sh`:
- `mcp_elicit <message> <schema_json> [timeout_secs]`
- `mcp_elicit_string <message> [field_name]`
- `mcp_elicit_confirm <message>`
- `mcp_elicit_choice <message> option1 option2 ...`

Environment variables set for tools:
- `MCP_ELICIT_SUPPORTED` – `"1"` when the client supports elicitation, `"0"` otherwise.
- `MCP_ELICIT_REQUEST_FILE` – path to write a request (JSON: `{"message": "...", "schema": {...}}`).
- `MCP_ELICIT_RESPONSE_FILE` – where the normalized response appears.

The SDK handles writing/reading these files, timeouts, and cancellation. Tools should branch on `.action` (`accept`, `decline`, `cancel`, `error`) and only use `.content` when `action=accept`.

## Examples
- `examples/07-elicitation` — minimal confirm + choice flow with fallback when elicitation is unsupported.
- `examples/advanced/ffmpeg-studio/transcode.sh` — uses elicitation (when available) to confirm overwriting an existing output; otherwise refuses to overwrite.

### Running via MCP Inspector
From the repo root, launch the example with the inspector’s stdio transport:
```bash
npx @modelcontextprotocol/inspector --transport stdio -- ./examples/run 07-elicitation
```
The `--` separator is required so the inspector doesn’t parse `./examples/run` as a flag.
