# 01-args-and-validation

**What you’ll learn**
- Reading arguments with `mcp_args_get`
- Validation failures surfacing as `isError=true`
- Structured output when jq/gojq is available; text fallback otherwise

**Prereqs**
- Bash 3.2+
- jq or gojq recommended; otherwise minimal mode (text-only output)

**Run**
```
./examples/run 01-args-and-validation
```

**Transcript**
```
> tools/call example.echoArg {"value":"hi"}
< {"result":{"content":[{"type":"text","text":"You sent: hi"}]}}
> tools/call example.echoArg {}
< {"error":{"code":-32602,"message":"Missing 'value' argument","isError":true}}
```

**Success criteria**
- `tools/list` shows `example.echoArg`
- Valid call echoes the provided value; missing argument yields a validation error

**Troubleshooting**
- Ensure scripts are executable (`chmod +x examples/run examples/01-args-and-validation/tools/*.sh`).
- Install jq/gojq for structured JSON output; otherwise expect text-only responses.
- Avoid CRLF in requests; send LF-only NDJSON.
