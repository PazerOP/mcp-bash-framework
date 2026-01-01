# mcp-bash Framework

Production-ready MCP server in pure Bash 3.2+. Zero runtime dependencies.

**Version:** 0.8.4 | **MCP Protocol:** 2025-11-25

## Quick Start

```bash
mcp-bash new my-server && cd my-server
mcp-bash scaffold tool my-tool
mcp-bash run-tool my-tool --args '{"param":"value"}'
```

## Project Structure

```
my-server/
├── tools/<name>/tool.sh + tool.meta.json    # Tools
├── resources/<name>.txt + .meta.json        # Resources
├── prompts/<name>.txt + .meta.json          # Prompts
├── server.d/server.meta.json                # Server metadata
└── .registry/                               # Auto-generated (gitignore)
```

## References

@docs/TOOL-AUTHORING.md
@docs/CLI-REFERENCE.md
@docs/ENV_REFERENCE.md

## Client Configuration

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):
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

Generate config: `mcp-bash config --show` or `mcp-bash config --client cursor`
