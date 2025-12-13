# 09-registry-overrides

**What you’ll learn**
- Replacing auto-discovery with curated registry entries via `server.d/register.json`
- Custom provider example (`echo://`) and a progress demo tool
- Optional live progress streaming (`MCPBASH_ENABLE_LIVE_PROGRESS=true`)

**Prereqs**
- Bash 3.2+
- jq or gojq required; otherwise the server enters minimal mode and manual registry entries are not exposed

**Run**
```bash
./examples/run 09-registry-overrides
```

**Transcript (abridged)**
```
> tools/list
< {"result":{"items":[{"name":"manual.progress",...}]}}
> tools/call manual.progress {"_meta":{"progressToken":"p1"}}
< notifications/progress ... "25%"
< {"result":{"content":[{"type":"text","text":"Done"}]}}
```

**Success criteria**
- Registry overrides are sourced from `server.d/register.json`.
- `manual.progress` emits progress (and streams live if env var set).
- `echo.hello` returns the echoed payload via custom provider; `manual.prompt` renders with optional `topic`.

**Troubleshooting**
- `server.d/register.json` is strict JSON: no comments/JSON5, UTF-8, no BOM.
- Ensure tool scripts are executable (`chmod +x examples/09-registry-overrides/tools/*.sh`).
- Live progress requires `MCPBASH_ENABLE_LIVE_PROGRESS=true`; otherwise notifications flush at completion.
- If you see minimal-mode warnings, install jq/gojq; minimal mode disables tools/resources/prompts.
- Avoid CRLF in requests; send LF-only NDJSON.
