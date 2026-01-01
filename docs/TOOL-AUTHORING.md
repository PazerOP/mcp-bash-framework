# Tool Authoring Guide

Complete guide to writing MCP tools with mcp-bash.

## Creating a Tool

### Using Scaffold

```bash
mcp-bash scaffold tool my-tool
```

Creates:
```
tools/my-tool/
├── tool.sh           # Tool implementation
├── tool.meta.json    # Metadata (name, schema, etc.)
└── smoke.sh          # Basic test script
```

### Manual Creation

Create two files in `tools/<name>/`:

1. **tool.sh** - Executable script
2. **tool.meta.json** - Metadata file

## Tool Script Structure

Every tool follows this structure:

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Source SDK
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"

# 2. Parse arguments
# ...

# 3. Implement logic
# ...

# 4. Return result
mcp_emit_json "$(mcp_json_obj key "value")"
```

## Metadata Schema

**tool.meta.json:**
```json
{
  "name": "tool-name",
  "description": "One-line description of what tool does",
  "inputSchema": {
    "type": "object",
    "properties": {
      "param": {
        "type": "string",
        "description": "Parameter description"
      }
    },
    "required": ["param"]
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "result": {
        "type": "string"
      }
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

### Required Fields

- `name`: Unique tool identifier
- `description`: What the tool does

### Optional Fields

- `inputSchema`: JSON Schema for arguments
- `outputSchema`: JSON Schema for result
- `timeoutSecs`: Override default timeout (default: 30)
- `annotations`: Behavioral hints for clients
- `icons`: Array of icon definitions

### Annotations

| Annotation | Default | Meaning |
|------------|---------|---------|
| `readOnlyHint` | false | Tool only reads, doesn't modify |
| `destructiveHint` | false | Tool may delete or modify data |
| `idempotentHint` | false | Safe to retry without side effects |
| `openWorldHint` | false | Tool accesses external systems |

## Argument Patterns

### Required String

```bash
name="$(mcp_args_require '.name')"
```

### Optional with Default

```bash
# Using jq default syntax
name="$(mcp_args_get '.name // "World"')"

# Using SDK default
verbose="$(mcp_args_bool '.verbose' --default false)"
count="$(mcp_args_int '.count' --default 10)"
```

### Integer with Bounds

```bash
limit="$(mcp_args_int '.limit' --default 10 --min 1 --max 100)"
port="$(mcp_args_int '.port' --min 1 --max 65535)"
```

### Boolean Flag

```bash
dry_run="$(mcp_args_bool '.dryRun' --default false)"
if [ "$dry_run" = "true" ]; then
    echo "Dry run mode"
fi
```

### Validated Path

```bash
# Required path
path="$(mcp_require_path '.path')"

# Default to single root
path="$(mcp_require_path '.path' --default-to-single-root)"

# Optional path
path="$(mcp_require_path '.path' --allow-empty)"
```

## Output Patterns

### JSON Object Result

```bash
mcp_emit_json "$(mcp_json_obj \
    status "success" \
    count "42" \
    message "Done")"
```

### Plain Text Result

```bash
mcp_emit_text "Operation completed successfully"
```

### Complex JSON (using jq)

```bash
result="$(some_command | jq '{
    data: .items,
    count: (.items | length),
    timestamp: now
}')"
mcp_emit_json "$result"
```

### Safe JSON Construction

```bash
# Variables are automatically escaped
mcp_emit_json "$(mcp_json_obj \
    content "$user_provided_content" \
    path "$file_path")"
```

## Error Handling

### Argument Validation Error

```bash
if [ -z "$value" ]; then
    mcp_fail_invalid_args "Missing required argument: value"
fi
```

### Generic Error

```bash
mcp_fail -32603 "Operation failed: unable to connect"
```

### Tool Error (LLM Can Retry)

Use regular output with error info - this allows the LLM to understand and retry:

```bash
if [ ! -f "$path" ]; then
    mcp_emit_json "$(mcp_json_obj \
        error "File not found" \
        path "$path" \
        hint "Check path exists and is accessible")"
    exit 1
fi
```

### Error Codes

| Code | Meaning | When to Use |
|------|---------|-------------|
| -32602 | Invalid params | Argument validation failure |
| -32603 | Internal error | Unexpected failures |
| -32001 | Request cancelled | User cancellation |

## Progress Reporting

For long-running operations:

```bash
total=100
for i in $(seq 1 $total); do
    mcp_progress "$i" "Processing item $i" "$total"
    # do work
    sleep 0.1
done
```

## Cancellation Handling

Check periodically in long operations:

```bash
for i in {1..100}; do
    if mcp_is_cancelled; then
        mcp_fail -32001 "Cancelled"
    fi
    # do work
done
```

## Logging

Send structured logs to the client:

```bash
mcp_log_info "my-tool" "Starting operation"
mcp_log_debug "my-tool" "Processing file: $path"
mcp_log_warn "my-tool" "File not found, using default"
mcp_log_error "my-tool" "Connection failed"
```

## Elicitation (User Input)

### Confirmation Dialog

```bash
resp="$(mcp_elicit_confirm "Delete all files in $dir?")"
action="$(echo "$resp" | jq -r '.action')"

if [ "$action" = "accept" ]; then
    confirmed="$(echo "$resp" | jq -r '.content.confirmed')"
    if [ "$confirmed" = "true" ]; then
        # proceed with deletion
    fi
fi
```

### Single Choice

```bash
resp="$(mcp_elicit_choice "Select environment" "dev" "staging" "prod")"
if [ "$(echo "$resp" | jq -r '.action')" = "accept" ]; then
    env="$(echo "$resp" | jq -r '.content.choice')"
fi
```

### Multiple Selection

```bash
resp="$(mcp_elicit_multi_choice "Select features" "logging" "caching" "metrics")"
if [ "$(echo "$resp" | jq -r '.action')" = "accept" ]; then
    features="$(echo "$resp" | jq -r '.content.choices | join(",")')"
fi
```

### Titled Choices

```bash
resp="$(mcp_elicit_titled_choice "Quality" \
    "high:High (1080p, larger file)" \
    "medium:Medium (720p, balanced)" \
    "low:Low (480p, smaller file)")"
```

### OAuth/External URL

```bash
resp="$(mcp_elicit_url "Authorize GitHub Access" "https://github.com/login/oauth/authorize?...")"
if [ "$(echo "$resp" | jq -r '.action')" = "accept" ]; then
    # user authorized
fi
```

## Filesystem Access

### Respecting Roots

Always validate paths against configured roots:

```bash
path="$(mcp_require_path '.path')"

# Manual check
if ! mcp_roots_contains "$path"; then
    mcp_emit_json "$(mcp_json_obj error "Path outside roots")"
    exit 1
fi
```

### List Available Roots

```bash
roots_count="$(mcp_roots_count)"
if [ "$roots_count" -eq 0 ]; then
    mcp_fail_invalid_args "No roots configured"
fi

roots="$(mcp_roots_list)"
```

## Embedding Resources

Include files in tool output:

```bash
# Write to resources file (TSV format)
if [ -n "${MCP_TOOL_RESOURCES_FILE:-}" ]; then
    printf '%s\ttext/plain\n' "/path/to/file.txt" >>"${MCP_TOOL_RESOURCES_FILE}"
    printf '%s\tapplication/json\n' "/path/to/data.json" >>"${MCP_TOOL_RESOURCES_FILE}"
fi

mcp_emit_json "$(mcp_json_obj message "See attached files")"
```

## Running External Commands

### Capture Output

```bash
output="$(some_command 2>&1)" || {
    mcp_fail -32603 "Command failed: $output"
}
mcp_emit_json "$(mcp_json_obj output "$output")"
```

### Stderr Handling

Keep stdout clean for JSON - redirect command output to stderr:

```bash
git status >&2  # Let user see git output
mcp_emit_json "$(mcp_json_obj status "checked")"
```

### With Timeout

Use per-tool timeout in metadata rather than manual timeout handling.

## Testing Tools

### Direct Invocation

```bash
mcp-bash run-tool my-tool
mcp-bash run-tool my-tool --args '{"name":"test"}'
mcp-bash run-tool my-tool --verbose
```

### Smoke Test

Each scaffolded tool includes `smoke.sh`:

```bash
cd tools/my-tool
./smoke.sh
```

### Test Harness

```bash
mcp-bash scaffold test
./test/run.sh
```

## Complete Examples

### File Reader

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
size="$(wc -c < "$path" | tr -d ' ')"

mcp_emit_json "$(mcp_json_obj \
    path "$path" \
    size "$size" \
    content "$content")"
```

### Command Runner

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

command="$(mcp_args_require '.command')"
dry_run="$(mcp_args_bool '.dryRun' --default false)"

if [ "$dry_run" = "true" ]; then
    mcp_emit_json "$(mcp_json_obj \
        status "dry-run" \
        command "$command")"
    exit 0
fi

mcp_log_info "runner" "Executing: $command"
output="$(eval "$command" 2>&1)" || {
    mcp_emit_json "$(mcp_json_obj \
        error "Command failed" \
        output "$output")"
    exit 1
}

mcp_emit_json "$(mcp_json_obj \
    status "success" \
    output "$output")"
```

### Batch Processor

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?}/tool-sdk.sh"

dir="$(mcp_require_path '.directory' --default-to-single-root)"
pattern="$(mcp_args_get '.pattern // "*.txt"')"

files=()
while IFS= read -r -d '' file; do
    files+=("$file")
done < <(find "$dir" -name "$pattern" -type f -print0)

total=${#files[@]}
processed=0

for file in "${files[@]}"; do
    if mcp_is_cancelled; then
        mcp_fail -32001 "Cancelled"
    fi

    ((processed++))
    mcp_progress "$processed" "Processing $file" "$total"

    # process file...
done

mcp_emit_json "$(mcp_json_obj \
    status "complete" \
    processed "$processed")"
```

## Best Practices

1. **Always source the SDK** at the start
2. **Use `set -euo pipefail`** for safety
3. **Validate all arguments** before use
4. **Check roots** for any filesystem access
5. **Check cancellation** in long loops
6. **Report progress** for operations > 1 second
7. **Keep stdout clean** - only JSON output
8. **Use structured logging** via `mcp_log_*`
9. **Return useful errors** that help the LLM retry
10. **Test with `mcp-bash run-tool`** during development
