# 00-hello-tool

**What you’ll learn**
- Basic handshake (`initialize`/`initialized`) and auto-discovered tools
- Structured vs text output depending on jq/gojq availability (no Python fallback)
- Runner sets `MCP_SDK` automatically

**Prereqs**
- Bash 3.2+
- jq or gojq recommended; otherwise minimal mode (text-only output)

**Run**
```
./examples/run 00-hello-tool
```

**Transcript**
```
> initialize
< {"result":{"capabilities":{...}}}
> tools/call example.hello
< {"result":{"content":[{"type":"text","text":"Hello from example tool"}]}}
```

**Success criteria**
- `tools/list` shows `example.hello`
- Calling `example.hello` returns a greeting (text or structured if jq/gojq is present)

**Troubleshooting**
- Ensure scripts are executable (`chmod +x examples/run examples/00-hello-tool/tools/*.sh`).
- If you see minimal-mode warnings, install jq/gojq or accept text-only output.
- Avoid CRLF in requests; send LF-only NDJSON.
