# mcp-bash Framework - Claude Code Reference

This is **mcp-bash**, a production-ready Model Context Protocol (MCP) server implementation in pure Bash 3.2+ with zero runtime dependencies.

**Version:** 0.8.4
**MCP Protocol:** 2025-11-25 (with negotiated downgrades)

## Quick Start

```bash
# Create new project
mcp-bash new my-server && cd my-server

# Add a tool
mcp-bash scaffold tool my-tool

# Test directly
mcp-bash run-tool my-tool --args '{"param":"value"}'

# Validate project
mcp-bash validate
```

## Documentation References

For detailed information, see:

@docs/QUICK-REFERENCE.md - Common operations and patterns
@docs/TOOL-AUTHORING.md - Complete guide to writing tools
@docs/SDK-REFERENCE.md - All SDK functions with examples
@docs/CLI-REFERENCE.md - All CLI commands and options
@docs/ENV_REFERENCE.md - All environment variables

## Project Structure

```
my-mcp-server/
├── tools/                    # Tool implementations
│   └── my-tool/
│       ├── tool.sh           # Tool script (executable)
│       └── tool.meta.json    # Tool metadata (name, schema, timeout)
├── resources/                # Static resources
│   ├── data.txt              # Resource file
│   └── data.meta.json        # Resource metadata
├── prompts/                  # Prompt templates
│   ├── template.txt          # Prompt text with {{var}} placeholders
│   └── template.meta.json    # Prompt metadata
├── completions/              # Completion providers (optional)
├── providers/                # Custom resource providers (optional)
├── server.d/                 # Server configuration
│   ├── server.meta.json      # Server metadata (optional)
│   ├── register.json         # Declarative registration (optional)
│   └── env.sh                # Environment overrides (optional)
└── .registry/                # Auto-generated cache (gitignore this)
```

## Essential Patterns

### Minimal Tool Template

**tools/my-tool/tool.sh:**
```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

# Get arguments
name="$(mcp_args_get '.name // "World"')"

# Return JSON result
mcp_emit_json "$(mcp_json_obj message "Hello ${name}")"
```

**tools/my-tool/tool.meta.json:**
```json
{
  "name": "my-tool",
  "description": "What this tool does",
  "inputSchema": {
    "type": "object",
    "properties": {
      "name": {"type": "string", "description": "Name to greet"}
    }
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "message": {"type": "string"}
    }
  }
}
```

### Tool with Required Arguments

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

# Required argument - fails if missing
value="$(mcp_args_require '.value')"

# Optional with default
count="$(mcp_args_int '.count' --default 10 --min 1 --max 100)"

mcp_emit_json "$(mcp_json_obj value "$value" count "$count")"
```

### Tool with Path Validation (Roots)

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

# Path validated against MCP roots
path="$(mcp_require_path '.path' --default-to-single-root)"

content="$(cat "$path")"
mcp_emit_json "$(mcp_json_obj content "$content")"
```

### Tool with Progress and Cancellation

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

for i in {1..10}; do
    if mcp_is_cancelled; then
        mcp_fail -32001 "Cancelled"
    fi
    mcp_progress $((i * 10)) "Step $i of 10" 100
    sleep 1
done

mcp_emit_json "$(mcp_json_obj status "complete")"
```

### Tool with User Confirmation (Elicitation)

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

resp="$(mcp_elicit_confirm "Proceed with operation?")"
action="$(echo "$resp" | jq -r '.action')"

if [ "$action" != "accept" ]; then
    mcp_fail -32001 "User declined"
fi

# Continue with operation...
mcp_emit_json "$(mcp_json_obj status "completed")"
```

### Embedding Resources in Tool Output

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

# Write to MCP_TOOL_RESOURCES_FILE (TSV format: path<TAB>mimeType)
if [ -n "${MCP_TOOL_RESOURCES_FILE:-}" ]; then
    printf '%s\ttext/plain\n' "/path/to/file.txt" >>"${MCP_TOOL_RESOURCES_FILE}"
fi

mcp_emit_json "$(mcp_json_obj message "See embedded resource")"
```

## Resource Definition

**resources/config.meta.json:**
```json
{
  "name": "app-config",
  "description": "Application configuration",
  "uri": "file://./resources/config.json",
  "mimeType": "application/json",
  "provider": "file"
}
```

## Prompt Template

**prompts/review.txt:**
```
Review this code for {{focus}}:

{{code}}

Provide specific suggestions.
```

**prompts/review.meta.json:**
```json
{
  "name": "code-review",
  "description": "Code review prompt",
  "path": "review.txt",
  "arguments": {
    "type": "object",
    "required": ["code", "focus"],
    "properties": {
      "code": {"type": "string", "description": "Code to review"},
      "focus": {"type": "string", "description": "Review focus area"}
    }
  }
}
```

## Server Metadata

**server.d/server.meta.json:**
```json
{
  "name": "my-server",
  "title": "My MCP Server",
  "version": "1.0.0",
  "description": "Server description"
}
```

## Client Configuration

```bash
# Show config for all clients
mcp-bash config --show

# Client-specific (claude-desktop, cursor, windsurf)
mcp-bash config --client cursor
```

**Claude Desktop (~/Library/Application Support/Claude/claude_desktop_config.json):**
```json
{
  "mcpServers": {
    "my-server": {
      "command": "mcp-bash",
      "env": {
        "MCPBASH_PROJECT_ROOT": "/path/to/my-server",
        "MCPBASH_TOOL_ALLOWLIST": "*"
      }
    }
  }
}
```

## Key Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `MCPBASH_PROJECT_ROOT` | (required) | Path to project directory |
| `MCPBASH_TOOL_ALLOWLIST` | (required) | Allowed tools (`*` for all) |
| `MCPBASH_DEFAULT_TOOL_TIMEOUT` | `30` | Tool timeout in seconds |
| `MCPBASH_LOG_LEVEL` | `info` | Log level (debug for traces) |
| `MCPBASH_TOOL_ENV_MODE` | `minimal` | Tool env isolation |

## Error Handling

```bash
# Invalid arguments (protocol error)
mcp_fail_invalid_args "Missing required: path"

# Generic failure with code
mcp_fail -32603 "Operation failed"

# Tool execution error (LLM can retry)
mcp_emit_json "$(mcp_json_obj error "File not found" hint "Check path")"
exit 1
```

## Testing Tools

```bash
# Direct invocation
mcp-bash run-tool my-tool --args '{"name":"test"}'

# With roots simulation
mcp-bash run-tool my-tool --roots /path/one,/path/two

# Dry run (validate only)
mcp-bash run-tool my-tool --dry-run

# Verbose output
mcp-bash run-tool my-tool --verbose
```

## Debugging

```bash
# Run with debug logging
MCPBASH_LOG_LEVEL=debug mcp-bash

# Full payload logging
mcp-bash debug

# Doctor diagnostics
mcp-bash doctor

# Validate project
mcp-bash validate --explain-defaults
```
