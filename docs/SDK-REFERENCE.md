# SDK Reference

Complete reference for all SDK functions available to tools via `tool-sdk.sh`.

## Loading the SDK

Every tool must source the SDK at the start:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "${MCP_SDK:?MCP_SDK environment variable not set}/tool-sdk.sh"
```

The `MCP_SDK` environment variable is automatically set by the framework when running tools.

## Argument Parsing

### mcp_args_require

Extract a required value from tool arguments. Fails with `-32602` if missing or null.

```bash
mcp_args_require '<jq-filter>' [error-message]
```

**Parameters:**
- `jq-filter`: jq expression to extract value (e.g., `.name`, `.config.path`)
- `error-message`: Optional custom error message

**Examples:**
```bash
# Required string
name="$(mcp_args_require '.name')"

# Required with custom message
path="$(mcp_args_require '.path' "Path argument is required")"

# Nested value
host="$(mcp_args_require '.server.host')"
```

### mcp_args_get

Extract a value using jq filter. Returns empty string if missing (does not fail).

```bash
mcp_args_get '<jq-filter>'
```

**Examples:**
```bash
# Optional with jq default
name="$(mcp_args_get '.name // "World"')"

# Check if present
count="$(mcp_args_get '.count')"
if [ -z "$count" ]; then
    count=10
fi

# Array element
first="$(mcp_args_get '.items[0]')"
```

### mcp_args_bool

Extract a boolean value with optional default.

```bash
mcp_args_bool '<jq-filter>' [--default true|false]
```

**Returns:** `true` or `false` (string)

**Examples:**
```bash
# With default
verbose="$(mcp_args_bool '.verbose' --default false)"

# Required boolean (no default)
enabled="$(mcp_args_bool '.enabled')"

# Usage in conditionals
if [ "$(mcp_args_bool '.dryRun' --default false)" = "true" ]; then
    echo "Dry run mode"
fi
```

### mcp_args_int

Extract an integer value with optional default and bounds.

```bash
mcp_args_int '<jq-filter>' [--default N] [--min N] [--max N]
```

**Examples:**
```bash
# With default
limit="$(mcp_args_int '.limit' --default 10)"

# With bounds
count="$(mcp_args_int '.count' --default 10 --min 1 --max 100)"

# Required with bounds (no default)
port="$(mcp_args_int '.port' --min 1 --max 65535)"
```

### mcp_args_raw

Get the raw JSON arguments string. Use when jq is unavailable or for custom parsing.

```bash
raw_json="$(mcp_args_raw)"
```

## Path Validation

### mcp_require_path

Extract and validate a path against configured MCP roots.

```bash
mcp_require_path '<jq-filter>' [options]
```

**Options:**
- `--default-to-single-root`: Use the single root as default when exactly one root is configured
- `--allow-empty`: Allow empty/missing path without error

**Examples:**
```bash
# Required path, validated against roots
path="$(mcp_require_path '.path')"

# Default to single root
path="$(mcp_require_path '.path' --default-to-single-root)"

# Optional path
path="$(mcp_require_path '.path' --allow-empty)"
```

## JSON Helpers

### mcp_json_obj

Build a JSON object from key-value pairs. All values are treated as strings.

```bash
mcp_json_obj key1 value1 [key2 value2 ...]
```

**Examples:**
```bash
# Simple object
mcp_json_obj message "Hello" status "ok"
# Output: {"message":"Hello","status":"ok"}

# With variables
mcp_json_obj name "$name" count "$count"

# Nested (value is already JSON)
inner="$(mcp_json_obj foo "bar")"
mcp_json_obj outer "$inner"  # Note: inner is stringified
```

### mcp_json_arr

Build a JSON array from values. All values are treated as strings.

```bash
mcp_json_arr value1 [value2 ...]
```

**Examples:**
```bash
# Simple array
mcp_json_arr "one" "two" "three"
# Output: ["one","two","three"]

# Empty array
mcp_json_arr
# Output: []
```

### mcp_json_escape

Escape a string for safe JSON inclusion. Returns a quoted JSON string.

```bash
mcp_json_escape '<string>'
```

**Examples:**
```bash
# Escape dangerous content
escaped="$(mcp_json_escape "$user_input")"

# Use in manual JSON construction
printf '{"message":%s}' "$(mcp_json_escape "$msg")"
```

## Output Functions

### mcp_emit_json

Emit a JSON result. Validates and compacts JSON if jq is available.

```bash
mcp_emit_json '<json-string>'
```

**Examples:**
```bash
# Literal JSON
mcp_emit_json '{"status":"ok"}'

# Built JSON
mcp_emit_json "$(mcp_json_obj message "Done" count "42")"

# Complex result
result="$(some_command | jq '{data: .}')"
mcp_emit_json "$result"
```

### mcp_emit_text

Emit plain text result.

```bash
mcp_emit_text '<text>'
```

**Examples:**
```bash
mcp_emit_text "Operation completed successfully"

mcp_emit_text "$(cat /path/to/file)"
```

## Error Functions

### mcp_fail

Exit with a structured error.

```bash
mcp_fail <code> <message> [data]
```

**Common codes:**
- `-32602`: Invalid params (arguments issue)
- `-32603`: Internal error
- `-32001`: Request cancelled

**Examples:**
```bash
# Simple error
mcp_fail -32603 "Operation failed"

# With data
mcp_fail -32603 "Parse error" '{"line":42}'

# Cancellation
mcp_fail -32001 "Cancelled by user"
```

### mcp_fail_invalid_args

Shorthand for argument validation errors (code -32602).

```bash
mcp_fail_invalid_args <message> [data]
```

**Examples:**
```bash
mcp_fail_invalid_args "Missing required: name"

mcp_fail_invalid_args "Invalid format" '{"expected":"email"}'
```

## Progress and Logging

### mcp_progress

Report progress to the client.

```bash
mcp_progress <percent> <message> [total]
```

**Parameters:**
- `percent`: 0-100 completion percentage
- `message`: Human-readable status message
- `total`: Optional total value for context

**Examples:**
```bash
mcp_progress 0 "Starting..."
mcp_progress 50 "Halfway done" 100
mcp_progress 100 "Complete"
```

### mcp_log_info / mcp_log_warn / mcp_log_error / mcp_log_debug

Send structured log messages to the client.

```bash
mcp_log_info <logger> <message>
mcp_log_warn <logger> <message>
mcp_log_error <logger> <message>
mcp_log_debug <logger> <message>
```

**Examples:**
```bash
mcp_log_info "my-tool" "Processing started"
mcp_log_warn "my-tool" "File not found, using default"
mcp_log_error "my-tool" "Connection failed"
mcp_log_debug "my-tool" "Variable x=$x"
```

### mcp_log

Low-level logging with explicit level.

```bash
mcp_log <level> <logger> <json-payload>
```

**Levels:** debug, info, notice, warning, error, critical, alert, emergency

### mcp_debug

Write to per-invocation debug log file (when `MCPBASH_DEBUG_LOG` is set).

```bash
mcp_debug <message>
```

**Example:**
```bash
mcp_debug "Checkpoint: args parsed"
mcp_debug "Value of x: $x"
```

## Cancellation

### mcp_is_cancelled

Check if the request has been cancelled by the client.

```bash
if mcp_is_cancelled; then
    # handle cancellation
fi
```

**Returns:** Exit code 0 if cancelled, 1 otherwise

**Example:**
```bash
for i in {1..100}; do
    if mcp_is_cancelled; then
        mcp_fail -32001 "Cancelled"
    fi
    # do work
done
```

## Roots (Filesystem Scoping)

### mcp_roots_list

Get newline-separated list of configured roots.

```bash
roots="$(mcp_roots_list)"
```

### mcp_roots_count

Get the number of configured roots.

```bash
count="$(mcp_roots_count)"
```

### mcp_roots_contains

Check if a path is within configured roots.

```bash
if mcp_roots_contains '<path>'; then
    # path is allowed
fi
```

**Example:**
```bash
path="/some/path"
if ! mcp_roots_contains "$path"; then
    mcp_emit_json "$(mcp_json_obj error "Path outside roots")"
    exit 1
fi
```

## Elicitation (User Input)

### mcp_elicit

Core elicitation function with JSON schema.

```bash
mcp_elicit <message> <schema-json> [timeout] [mode]
```

**Returns:** JSON with `action` and `content` fields:
```json
{"action":"accept","content":{"field":"value"}}
{"action":"decline","content":null}
{"action":"cancel","content":null}
```

### mcp_elicit_confirm

Simple yes/no confirmation.

```bash
resp="$(mcp_elicit_confirm "<message>")"
```

**Returns content:** `{"confirmed": true|false}`

**Example:**
```bash
resp="$(mcp_elicit_confirm "Delete all files?")"
if [ "$(echo "$resp" | jq -r '.action')" = "accept" ]; then
    confirmed="$(echo "$resp" | jq -r '.content.confirmed')"
fi
```

### mcp_elicit_choice

Single selection from options.

```bash
resp="$(mcp_elicit_choice "<message>" "opt1" "opt2" "opt3")"
```

**Returns content:** `{"choice": "selected-option"}`

### mcp_elicit_titled_choice

Single selection with display titles. Format: `value:Display Title`.

```bash
resp="$(mcp_elicit_titled_choice "<message>" "high:High Quality" "low:Low Quality")"
```

**Returns content:** `{"choice": "high"}` (value only, not title)

### mcp_elicit_multi_choice

Multiple selection (checkboxes).

```bash
resp="$(mcp_elicit_multi_choice "<message>" "opt1" "opt2" "opt3")"
```

**Returns content:** `{"choices": ["opt1", "opt3"]}`

### mcp_elicit_titled_multi_choice

Multiple selection with display titles.

```bash
resp="$(mcp_elicit_titled_multi_choice "<message>" "a:Option A" "b:Option B")"
```

### mcp_elicit_string

Free-form string input.

```bash
resp="$(mcp_elicit_string "<message>" [field-name])"
```

**Returns content:** `{"value": "user input"}` or `{"field-name": "user input"}`

### mcp_elicit_url

URL mode for OAuth or external authorization flows.

```bash
resp="$(mcp_elicit_url "<message>" "<url>" [timeout])"
```

**Returns:** `{"action":"accept|decline|cancel","content":null}`

## Request Metadata

### mcp_meta_raw

Get raw _meta JSON from the tools/call request (client-controlled, not LLM-generated).

```bash
meta="$(mcp_meta_raw)"
```

### mcp_meta_get

Extract value from request metadata using jq filter.

```bash
value="$(mcp_meta_get '.auth.token')"
```

## Environment Variables Available to Tools

| Variable | Description |
|----------|-------------|
| `MCP_SDK` | Path to SDK directory |
| `MCP_TOOL_ARGS_JSON` | Tool arguments JSON |
| `MCP_TOOL_ARGS_FILE` | Path to args file (large payloads) |
| `MCP_CANCEL_FILE` | Cancellation marker file |
| `MCP_PROGRESS_STREAM` | Progress notification pipe |
| `MCP_PROGRESS_TOKEN` | Token for progress notifications |
| `MCP_LOG_STREAM` | Log notification pipe |
| `MCP_ROOTS_JSON` | Full roots array JSON |
| `MCP_ROOTS_PATHS` | Newline-separated root paths |
| `MCP_ROOTS_COUNT` | Number of roots |
| `MCP_TOOL_RESOURCES_FILE` | Embedded resources output file |
| `MCP_ELICIT_REQUEST_FILE` | Elicitation request file |
| `MCP_ELICIT_RESPONSE_FILE` | Elicitation response file |
| `MCP_ELICIT_SUPPORTED` | "1" if client supports elicitation |
| `MCPBASH_PROJECT_ROOT` | Project root directory |
| `MCPBASH_DEBUG_LOG` | Per-invocation debug log path |
| `MCPBASH_JSON_TOOL_BIN` | Path to jq/gojq binary |
| `MCPBASH_MODE` | "full" or "minimal" |
