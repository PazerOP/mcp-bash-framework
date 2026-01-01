# Quick Reference

Fast lookup for common mcp-bash operations.

## Project Commands

```bash
# Create new project
mcp-bash new my-server

# Initialize in existing directory
mcp-bash init --name my-server

# Scaffold components
mcp-bash scaffold tool my-tool
mcp-bash scaffold resource my-resource
mcp-bash scaffold prompt my-prompt
mcp-bash scaffold completion my-completion
mcp-bash scaffold test

# Validate project
mcp-bash validate
mcp-bash validate --fix
mcp-bash validate --explain-defaults
```

## Tool Testing

```bash
# Direct tool invocation
mcp-bash run-tool tool-name
mcp-bash run-tool tool-name --args '{"key":"value"}'
mcp-bash run-tool tool-name --dry-run
mcp-bash run-tool tool-name --verbose
mcp-bash run-tool tool-name --roots /path/one,/path/two
mcp-bash run-tool tool-name --timeout 60
```

## Server Operations

```bash
# Start server (for testing)
MCPBASH_PROJECT_ROOT=/path/to/project MCPBASH_TOOL_ALLOWLIST="*" mcp-bash

# Debug mode (full payloads)
mcp-bash debug

# Registry management
mcp-bash registry refresh
mcp-bash registry status

# Health check
mcp-bash --health
```

## Client Configuration

```bash
# Show all client configs
mcp-bash config --show

# Specific client
mcp-bash config --client claude-desktop
mcp-bash config --client cursor
mcp-bash config --client windsurf

# Generate wrapper script
mcp-bash config --wrapper

# MCP Inspector command
mcp-bash config --inspector
```

## Tool SDK Quick Reference

### Argument Parsing

```bash
source "${MCP_SDK:?}/tool-sdk.sh"

# Required (fails if missing)
value="$(mcp_args_require '.name')"

# Optional with jq filter
value="$(mcp_args_get '.name // "default"')"

# Boolean with default
flag="$(mcp_args_bool '.verbose' --default false)"

# Integer with bounds
count="$(mcp_args_int '.count' --default 10 --min 1 --max 100)"

# Path validated against roots
path="$(mcp_require_path '.path')"
path="$(mcp_require_path '.path' --default-to-single-root)"
```

### JSON Output

```bash
# Emit JSON result
mcp_emit_json '{"key":"value"}'

# Build JSON object (all values as strings)
mcp_emit_json "$(mcp_json_obj key1 "value1" key2 "value2")"

# Build JSON array
mcp_json_arr "item1" "item2" "item3"

# Escape string for JSON
escaped="$(mcp_json_escape "$dangerous_string")"

# Emit plain text
mcp_emit_text "Plain text result"
```

### Errors

```bash
# Invalid arguments (protocol error -32602)
mcp_fail_invalid_args "Missing required: path"

# Generic failure with code
mcp_fail -32603 "Internal error"
mcp_fail -32001 "Cancelled by user"

# Tool error (LLM can retry with different input)
mcp_emit_json "$(mcp_json_obj error "Not found" hint "Check path")"
exit 1
```

### Progress and Logging

```bash
# Report progress (percent, message, total)
mcp_progress 50 "Halfway done" 100

# Structured logging
mcp_log_info "module" "message"
mcp_log_warn "module" "warning message"
mcp_log_error "module" "error message"
mcp_log_debug "module" "debug message"

# Debug log to per-invocation file
mcp_debug "checkpoint reached"
```

### Cancellation

```bash
if mcp_is_cancelled; then
    mcp_fail -32001 "Cancelled"
fi
```

### Elicitation (User Input)

```bash
# Confirmation (yes/no)
resp="$(mcp_elicit_confirm "Continue?")"
action="$(echo "$resp" | jq -r '.action')"

# Single choice
resp="$(mcp_elicit_choice "Pick one" "opt1" "opt2" "opt3")"
choice="$(echo "$resp" | jq -r '.content.choice')"

# Choice with titles
resp="$(mcp_elicit_titled_choice "Quality" "high:High (1080p)" "low:Low (480p)")"

# Multi-select
resp="$(mcp_elicit_multi_choice "Select features" "logging" "caching")"
choices="$(echo "$resp" | jq -r '.content.choices | join(",")')"

# URL mode (OAuth/external)
resp="$(mcp_elicit_url "Authorize" "https://oauth.example.com/...")"
```

### Roots (Filesystem Scoping)

```bash
# List configured roots
mcp_roots_list

# Count roots
mcp_roots_count

# Check if path is within roots
if mcp_roots_contains "/some/path"; then
    # path is allowed
fi
```

### Embedded Resources

```bash
# Embed file in tool result
if [ -n "${MCP_TOOL_RESOURCES_FILE:-}" ]; then
    printf '%s\ttext/plain\n' "/path/to/file" >>"${MCP_TOOL_RESOURCES_FILE}"
fi
```

## Metadata Templates

### Tool Metadata (tool.meta.json)

```json
{
  "name": "tool-name",
  "description": "What this tool does",
  "inputSchema": {
    "type": "object",
    "properties": {
      "param": {"type": "string", "description": "Description"}
    },
    "required": ["param"]
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "result": {"type": "string"}
    }
  },
  "timeoutSecs": 30,
  "annotations": {
    "readOnlyHint": true,
    "destructiveHint": false,
    "idempotentHint": true,
    "openWorldHint": false
  }
}
```

### Resource Metadata (resource.meta.json)

```json
{
  "name": "resource-name",
  "description": "What this resource contains",
  "uri": "file://./resources/data.txt",
  "mimeType": "text/plain",
  "provider": "file"
}
```

### Prompt Metadata (prompt.meta.json)

```json
{
  "name": "prompt-name",
  "description": "What this prompt does",
  "path": "prompt.txt",
  "arguments": {
    "type": "object",
    "properties": {
      "var": {"type": "string", "description": "Template variable"}
    },
    "required": ["var"]
  }
}
```

### Server Metadata (server.d/server.meta.json)

```json
{
  "name": "server-name",
  "title": "Server Title",
  "version": "1.0.0",
  "description": "Server description"
}
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `MCPBASH_PROJECT_ROOT` | (required) | Project directory path |
| `MCPBASH_TOOL_ALLOWLIST` | (required) | Tool allowlist (`*` for all) |
| `MCPBASH_DEFAULT_TOOL_TIMEOUT` | `30` | Default timeout (seconds) |
| `MCPBASH_LOG_LEVEL` | `info` | Log level |
| `MCPBASH_TOOL_ENV_MODE` | `minimal` | Tool environment isolation |
| `MCPBASH_MAX_CONCURRENT_REQUESTS` | `16` | Worker concurrency cap |
| `MCPBASH_MAX_TOOL_OUTPUT_SIZE` | `10485760` | Tool stdout limit (bytes) |

## Common Patterns

### Safe File Operations

```bash
path="$(mcp_require_path '.path')"

if [ ! -f "$path" ]; then
    mcp_emit_json "$(mcp_json_obj error "Not found" path "$path")"
    exit 1
fi

content="$(cat "$path")"
mcp_emit_json "$(mcp_json_obj content "$content")"
```

### Long-Running with Progress

```bash
total=100
for i in $(seq 1 $total); do
    mcp_is_cancelled && mcp_fail -32001 "Cancelled"
    mcp_progress "$i" "Processing $i of $total" "$total"
    # do work
done
mcp_emit_json "$(mcp_json_obj status "complete")"
```

### Confirm Before Destructive Action

```bash
resp="$(mcp_elicit_confirm "Delete all files?")"
if [ "$(echo "$resp" | jq -r '.action')" != "accept" ]; then
    mcp_emit_json "$(mcp_json_obj status "cancelled")"
    exit 0
fi
# proceed with deletion
```
