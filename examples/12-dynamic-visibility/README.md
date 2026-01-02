# Dynamic Visibility Example

This example demonstrates the dynamic tool visibility feature, which allows tools
and resources to conditionally appear in MCP discovery responses based on runtime
conditions.

## Tools in this example

### 1. always-visible
A standard tool with no visibility restrictions - it always appears in the tools list.

### 2. env-controlled-admin
A tool that only appears when the `ENABLE_ADMIN_TOOLS` environment variable is set.
This is useful for admin/debug tools that should only be visible in certain environments.

**Visibility configuration:**
```json
{
  "visibility": {
    "env": "ENABLE_ADMIN_TOOLS"
  }
}
```

To make this tool visible:
```bash
export ENABLE_ADMIN_TOOLS=1
```

### 3. script-controlled-tool
A tool whose visibility is controlled by a custom script. In this example, the tool
is only visible during business hours (9 AM - 5 PM).

**Visibility configuration:**
```json
{
  "visibility": "./visibility.sh"
}
```

The `visibility.sh` script returns exit code 0 (visible) or 1 (hidden).

## Visibility Configuration Options

The `visibility` field in `tool.meta.json` or `resource.meta.json` supports:

### 1. Script path (string)
```json
{
  "visibility": "./visibility.sh"
}
```

### 2. Environment variable check
```json
{
  "visibility": {
    "env": "MY_FEATURE_FLAG"
  }
}
```

### 3. Inline shell command
```json
{
  "visibility": {
    "command": "[ -f /etc/my-feature-enabled ]"
  }
}
```

### 4. Script with options
```json
{
  "visibility": {
    "script": "./check-visibility.sh",
    "cacheTtl": 30
  }
}
```

## Testing

Run the server with this example:
```bash
cd examples/12-dynamic-visibility
../../bin/mcp-bash
```

Then test with different configurations:
```bash
# Default: only 'always-visible' and possibly 'script-controlled-tool' appear
../../bin/mcp-bash

# With admin tools enabled: 'env-controlled-admin' also appears
ENABLE_ADMIN_TOOLS=1 ../../bin/mcp-bash
```
