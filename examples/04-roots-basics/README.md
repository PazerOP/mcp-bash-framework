# 04-roots-basics

**What you'll learn**
- How MCP Roots scope tool filesystem access
- Using the SDK roots helpers (`mcp_roots_contains`, `MCP_ROOTS_*` env)
- Fallback roots via `config/roots.json` and `MCPBASH_ROOTS`
- **Error handling best practices**: Protocol Errors vs Tool Execution Errors

**Prereqs**
- Bash 3.2+
- jq or gojq

**Run**
```
# From repo root
./examples/run 04-roots-basics
```

**Try it**
```
> tools/call example.roots.read {"arguments":{"path":"./data/sample.txt"}}
< {"result":{"content":[{"type":"text","text":"Contents of /.../data/sample.txt\nHello from roots example!\n"}]}}

> tools/call example.roots.read {"arguments":{"path":"/etc/passwd"}}
< {"result":{"content":[{"type":"text","text":"{\"error\":\"Path is outside allowed roots\",\"path\":\"/etc/passwd\",\"hint\":\"Try a path within: ./data\"}"}],"isError":true}}
```

**Error Handling Pattern**

This example demonstrates the MCP best practice for error handling:

| Scenario | Error Type | Why |
|----------|------------|-----|
| Missing `path` argument | Protocol Error (`-32602`) | Request structure issue |
| Path outside roots | Tool Execution Error (`isError: true`) | LLM can choose a valid path |
| File not found | Tool Execution Error (`isError: true`) | LLM can try a different file |

Tool Execution Errors include actionable hints so the LLM can self-correct:
```json
{"error": "Path is outside allowed roots", "path": "/etc/passwd", "hint": "Try a path within: ./data"}
```

See `docs/ERRORS.md` for full guidance on when to use each error type.

**Roots configuration**
- Default fallback: `config/roots.json` includes `./data` so the example works out of the box.
- Override via env: `MCPBASH_ROOTS="/tmp/myroot:/var/tmp/other" ./examples/run 04-roots-basics`
- Client-provided roots: if your MCP client supports roots, the server will request them and use those instead of the fallback.

**Success criteria**
- Reading `./data/sample.txt` succeeds; paths outside configured roots are denied with actionable error messages.
