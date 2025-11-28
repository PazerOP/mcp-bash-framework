# 02-logging-and-levels

**What you’ll learn**
- Emitting structured logs from a tool
- Changing verbosity via `logging/setLevel`
- Text vs structured output depending on jq/gojq (no Python fallback)

**Prereqs**
- Bash 3.2+
- jq or gojq recommended; otherwise minimal mode (text-only output)

**Run**
```
./examples/run 02-logging-and-levels
```

**Transcript**
```
> logging/setLevel {"level":"debug"}
> tools/call example.logger
< notifications/message ... "example.logger" ...
< {"result":{"content":[{"type":"text","text":"Check your logging notifications"}]}}
```

**Success criteria**
- `tools/list` shows `example.logger`
- Setting level to `debug` yields `notifications/message` entries from the tool

**Troubleshooting**
- Ensure scripts are executable (`chmod +x examples/run examples/02-logging-and-levels/tools/*.sh`).
- If no logs appear, confirm `logging/setLevel` to `debug` or `info`.
- Avoid CRLF in requests; send LF-only NDJSON.
