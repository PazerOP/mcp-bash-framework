# Dynamic Tool and Resource Visibility

The mcp-bash framework supports dynamic visibility for tools and resources. This feature
allows you to conditionally show or hide tools and resources based on runtime conditions
such as environment variables, time of day, feature flags, or custom logic.

## Overview

When a tool or resource has a `visibility` field defined in its metadata, the framework
evaluates the visibility condition at list time. If the condition returns true (exit code 0),
the item appears in discovery responses. If it returns false (non-zero exit code), the item
is hidden from the list but remains in the internal registry.

## Configuration

Add the `visibility` field to your `tool.meta.json` or `resource.meta.json`:

### Environment Variable Check

The simplest form - check if an environment variable is set:

```json
{
  "name": "admin-tool",
  "description": "Administrative tool",
  "visibility": {
    "env": "ENABLE_ADMIN_TOOLS"
  }
}
```

The tool is visible when `ENABLE_ADMIN_TOOLS` has any non-empty value.

### Visibility Script

Point to a shell script that determines visibility:

```json
{
  "name": "feature-tool",
  "description": "Feature-gated tool",
  "visibility": "./visibility.sh"
}
```

Or with options:

```json
{
  "visibility": {
    "script": "./check-visibility.sh",
    "cacheTtl": 30
  }
}
```

The script should:
- Exit with code 0 if the item should be visible
- Exit with non-zero code if the item should be hidden
- Be owned by the current user (security requirement)
- Not be group/world writable (security requirement)

### Inline Command

For simple conditions, use an inline shell command:

```json
{
  "visibility": {
    "command": "[ -f /etc/feature-enabled ]"
  }
}
```

## Visibility Script Examples

### Time-based Visibility

```bash
#!/usr/bin/env bash
# visible.sh - Only visible during business hours
hour=$(date +%H)
hour=${hour#0}  # Remove leading zero

if [ "$hour" -ge 9 ] && [ "$hour" -lt 17 ]; then
    exit 0  # Visible
else
    exit 1  # Hidden
fi
```

### Feature Flag Check

```bash
#!/usr/bin/env bash
# Check if a feature flag file exists
if [ -f "${HOME}/.config/myapp/feature-x-enabled" ]; then
    exit 0
fi
exit 1
```

### Permission-based Visibility

```bash
#!/usr/bin/env bash
# Only visible to users in the admin group
if groups | grep -qw admin; then
    exit 0
fi
exit 1
```

## Environment Variables

The visibility script receives these environment variables:

| Variable | Description |
|----------|-------------|
| `MCPBASH_HOME` | Path to the mcp-bash framework |
| `MCPBASH_PROJECT_ROOT` | Path to the project root |
| `MCP_ITEM_NAME` | Name of the tool/resource |
| `MCP_ITEM_TYPE` | Type of item ("tool" or "resource") |

## Caching

Visibility results are cached to avoid repeated script executions:

- Default cache TTL: 5 seconds
- Configure per-item: `{"visibility": {"script": "./check.sh", "cacheTtl": 30}}`
- Configure globally: `MCP_VISIBILITY_CACHE_TTL=10`
- Clear cache programmatically: `mcp_visibility_cache_clear`

## Security

Visibility scripts are subject to security checks:

1. **Ownership**: Script must be owned by the current user
2. **Permissions**: Script must not be group/world writable
3. **No symlinks**: Script path must not be a symbolic link
4. **Timeout**: Scripts are killed after 2 seconds (configurable via `MCP_VISIBILITY_TIMEOUT`)

If a script fails security checks, the item is hidden and a warning is logged.

## Best Practices

1. **Keep visibility scripts fast** - They run on every list request
2. **Use caching** - Set appropriate `cacheTtl` for expensive checks
3. **Prefer environment variables** - Simplest and fastest visibility check
4. **Document visibility requirements** - Users should know why tools disappear
5. **Test both states** - Verify tools appear/disappear correctly

## Debugging

Enable debug logging to see visibility decisions:

```bash
MCPBASH_LOG_LEVEL=debug mcp-bash
```

Look for messages from the `mcp.visibility` logger.

## Example Project Structure

```
my-server/
├── tools/
│   ├── public-tool/
│   │   ├── tool.sh
│   │   └── tool.meta.json         # No visibility - always visible
│   ├── admin-tool/
│   │   ├── tool.sh
│   │   └── tool.meta.json         # visibility: {"env": "ADMIN_MODE"}
│   └── beta-feature/
│       ├── tool.sh
│       ├── tool.meta.json         # visibility: "./is-beta-user.sh"
│       └── is-beta-user.sh
└── resources/
    └── debug-log/
        ├── debug.log
        └── debug.log.meta.json    # visibility: {"env": "DEBUG"}
```

## Comparison with Policy

| Feature | Visibility | Policy |
|---------|------------|--------|
| Affects | Discovery (list) | Execution (call) |
| Timing | At list time | At call time |
| Scope | Per tool/resource | Server-wide |
| Purpose | Feature gating, UI control | Security, access control |

Use visibility for feature flags and UI control. Use policy for security and access control.
