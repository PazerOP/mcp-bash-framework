# CLI Reference

## Server

```bash
mcp-bash                    # Start MCP server (requires MCPBASH_PROJECT_ROOT, MCPBASH_TOOL_ALLOWLIST)
mcp-bash debug              # Start with payload logging
mcp-bash --version          # Show version
mcp-bash --health           # Health check (exit 0=ready, 1=unhealthy, 2=misconfigured)
```

## Project Management

```bash
mcp-bash new <name>                    # Create new project
mcp-bash new <name> --no-hello         # Without example tool
mcp-bash init                          # Initialize in current directory
mcp-bash init --name <name>            # With explicit name
```

## Scaffolding

```bash
mcp-bash scaffold tool <name>          # Create tool template
mcp-bash scaffold resource <name>      # Create resource template
mcp-bash scaffold prompt <name>        # Create prompt template
mcp-bash scaffold completion <name>    # Create completion provider
mcp-bash scaffold test                 # Create test harness
```

## Validation

```bash
mcp-bash validate                      # Validate project
mcp-bash validate --fix                # Auto-fix issues
mcp-bash validate --explain-defaults   # Show applied defaults
mcp-bash validate --strict             # Strict spec compliance
mcp-bash validate --json               # Machine-readable output
```

## Diagnostics

```bash
mcp-bash doctor                        # Environment diagnostics
mcp-bash doctor --fix                  # Apply repairs
mcp-bash doctor --dry-run              # Show proposed repairs
mcp-bash doctor --json                 # Machine-readable output
```

## Tool Invocation

```bash
mcp-bash run-tool <name>                           # Run tool directly
mcp-bash run-tool <name> --args '{"key":"val"}'   # With arguments
mcp-bash run-tool <name> --dry-run                 # Validate only
mcp-bash run-tool <name> --verbose                 # Stream stderr
mcp-bash run-tool <name> --roots /a,/b             # Simulate roots
mcp-bash run-tool <name> --timeout 60              # Override timeout
mcp-bash run-tool <name> --print-env               # Show tool environment
```

## Client Configuration

```bash
mcp-bash config --show                 # All client configs
mcp-bash config --client claude-desktop
mcp-bash config --client cursor
mcp-bash config --client windsurf
mcp-bash config --json                 # Machine-readable
mcp-bash config --wrapper              # Generate wrapper script
mcp-bash config --inspector            # MCP Inspector command
```

## Registry

```bash
mcp-bash registry refresh              # Force rebuild
mcp-bash registry status               # Show cache status
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error / Unhealthy |
| 2 | Misconfiguration |
| 130 | Interrupted |
