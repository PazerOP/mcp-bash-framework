# 06-manual-registration

**What you’ll learn**
- Replacing auto-discovery with curated registry entries via `server.d/register.sh`
- Custom provider example (`echo://`) and a progress demo tool
- Optional live progress streaming (`MCPBASH_ENABLE_LIVE_PROGRESS=true`)

**Prereqs**
- Bash 3.2+
- jq or gojq recommended; otherwise minimal mode (manual registry still works but capabilities are limited)

**Run**
```
export MCPBASH_PROJECT_ROOT=$(pwd)/examples/06-manual-registration
export MCPBASH_ENABLE_LIVE_PROGRESS=true   # optional
bin/mcp-bash
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
- Registry is sourced from `server.d/register.sh`; changes under tools/resources/prompts alone do not auto-add.
- `manual.progress` emits progress (and streams live if env var set).
- `echo.hello` returns the echoed payload via custom provider; `manual.prompt` renders with optional `topic`.

**Troubleshooting**
- Ensure scripts are executable (`chmod +x examples/06-manual-registration/server.d/register.sh examples/06-manual-registration/tools/*.sh`).
- Live progress requires `MCPBASH_ENABLE_LIVE_PROGRESS=true`; otherwise notifications flush at completion.
- Avoid CRLF in requests; send LF-only NDJSON.
