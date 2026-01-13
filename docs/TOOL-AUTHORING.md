# Tool Authoring Guide

## Creating a Tool

```bash
mcp-bash scaffold tool my-tool
```

Creates `tools/my-tool/` with:
- `tool.sh` - Implementation (executable)
- `tool.meta.json` - Metadata

## Tool Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

# Parse arguments
name="$(mcp_args_get '.name // "World"')"

# Return result
mcp_emit_json "$(mcp_json_obj message "Hello ${name}")"
```

## Metadata (tool.meta.json)

```json
{
  "name": "my-tool",
  "description": "What this tool does",
  "inputSchema": {
    "type": "object",
    "properties": {
      "name": {"type": "string", "description": "Name to greet"}
    },
    "required": ["name"]
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "message": {"type": "string"}
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

---

## SDK Reference

### Argument Parsing

```bash
# Required (fails if missing)
value="$(mcp_args_require '.name')"
value="$(mcp_args_require '.name' "Custom error message")"

# Optional with jq default
value="$(mcp_args_get '.name // "default"')"

# Boolean with default
flag="$(mcp_args_bool '.verbose' --default false)"

# Integer with bounds
count="$(mcp_args_int '.count' --default 10 --min 1 --max 100)"

# Path validated against roots
path="$(mcp_require_path '.path')"
path="$(mcp_require_path '.path' --default-to-single-root)"
path="$(mcp_require_path '.path' --allow-empty)"

# Raw JSON (when jq unavailable)
raw="$(mcp_args_raw)"
```

### JSON Output

```bash
# Emit JSON result
mcp_emit_json '{"key":"value"}'
mcp_emit_json "$(mcp_json_obj key1 "val1" key2 "val2")"

# Build JSON
mcp_json_obj key1 "val1" key2 "val2"  # {"key1":"val1","key2":"val2"}
mcp_json_arr "a" "b" "c"              # ["a","b","c"]
mcp_json_escape "$dangerous"          # Escaped quoted string

# Plain text
mcp_emit_text "Plain text result"
```

### Errors

```bash
# Argument error (-32602)
mcp_fail_invalid_args "Missing required: path"

# Generic error
mcp_fail -32603 "Operation failed"
mcp_fail -32001 "Cancelled"

# Tool error (LLM can retry with different input)
mcp_emit_json "$(mcp_json_obj error "Not found" hint "Check path")"
exit 1
```

### Progress & Logging

```bash
# Progress (percent, message, total)
mcp_progress 50 "Halfway done" 100

# Logging
mcp_log_info "module" "message"
mcp_log_warn "module" "warning"
mcp_log_error "module" "error"
mcp_log_debug "module" "debug info"

# Debug to per-invocation file
mcp_debug "checkpoint reached"
```

### Cancellation

```bash
if mcp_is_cancelled; then
    mcp_fail -32001 "Cancelled"
fi
```

### Roots (Filesystem Scoping)

```bash
mcp_roots_list                    # Newline-separated paths
mcp_roots_count                   # Number of roots
mcp_roots_contains "/path"        # Check if path allowed
```

### Elicitation (User Input)

```bash
# Confirmation
resp="$(mcp_elicit_confirm "Continue?")"
# Returns: {"action":"accept|decline","content":{"confirmed":true|false}}

# Single choice
resp="$(mcp_elicit_choice "Pick one" "opt1" "opt2" "opt3")"
# Returns: {"action":"accept","content":{"choice":"opt1"}}

# Choice with titles (value:Display Title)
resp="$(mcp_elicit_titled_choice "Quality" "high:High (1080p)" "low:Low (480p)")"

# Multi-select
resp="$(mcp_elicit_multi_choice "Select" "a" "b" "c")"
# Returns: {"action":"accept","content":{"choices":["a","c"]}}

# URL mode (OAuth)
resp="$(mcp_elicit_url "Authorize" "https://oauth.example.com/...")"

# Parse response
action="$(echo "$resp" | jq -r '.action')"
choice="$(echo "$resp" | jq -r '.content.choice')"
```

### Embedded Resources

```bash
if [ -n "${MCP_TOOL_RESOURCES_FILE:-}" ]; then
    printf '%s\ttext/plain\n' "/path/to/file" >>"${MCP_TOOL_RESOURCES_FILE}"
fi
```

### Request Metadata

```bash
# Client-controlled metadata (not LLM-generated)
meta="$(mcp_meta_raw)"
token="$(mcp_meta_get '.auth.token')"
```

---

## Complete Examples

### File Reader with Validation

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

path="$(mcp_require_path '.path')"

if [ ! -f "$path" ]; then
    mcp_emit_json "$(mcp_json_obj error "Not found" path "$path")"
    exit 1
fi

content="$(cat "$path")"
mcp_emit_json "$(mcp_json_obj path "$path" content "$content")"
```

### Long-Running with Progress

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

for i in {1..10}; do
    mcp_is_cancelled && mcp_fail -32001 "Cancelled"
    mcp_progress $((i * 10)) "Step $i of 10" 100
    sleep 1
done

mcp_emit_json "$(mcp_json_obj status "complete")"
```

### Destructive with Confirmation

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

path="$(mcp_args_require '.path')"

resp="$(mcp_elicit_confirm "Delete $path?")"
if [ "$(echo "$resp" | jq -r '.action')" != "accept" ]; then
    mcp_emit_json "$(mcp_json_obj status "cancelled")"
    exit 0
fi

rm -rf "$path"
mcp_emit_json "$(mcp_json_obj status "deleted")"
```

---

## Resources & Prompts

### Resource Metadata

```json
{
  "name": "config",
  "description": "App configuration",
  "uri": "file://./resources/config.json",
  "mimeType": "application/json",
  "provider": "file"
}
```

### Prompt Template

**prompts/review.txt:**
```
Review this code for {{focus}}:

{{code}}
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
      "code": {"type": "string"},
      "focus": {"type": "string"}
    }
  }
}
```

---

## Testing

```bash
mcp-bash run-tool my-tool                              # Direct call
mcp-bash run-tool my-tool --args '{"name":"test"}'    # With args
mcp-bash run-tool my-tool --dry-run                    # Validate only
mcp-bash run-tool my-tool --verbose                    # Stream stderr
mcp-bash run-tool my-tool --roots /path/a,/path/b     # Simulate roots
mcp-bash validate                                       # Validate project
```

---

## Environment in Tools

| Variable | Description |
|----------|-------------|
| `MCP_SDK` | SDK directory path |
| `MCP_TOOL_ARGS_JSON` | Arguments JSON |
| `MCP_ROOTS_PATHS` | Newline-separated roots |
| `MCP_ROOTS_COUNT` | Number of roots |
| `MCP_TOOL_RESOURCES_FILE` | Embedded resources output |
| `MCP_ELICIT_SUPPORTED` | "1" if elicitation available |
| `MCPBASH_PROJECT_ROOT` | Project root |
| `MCPBASH_JSON_TOOL_BIN` | jq/gojq path |
