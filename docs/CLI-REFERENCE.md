# CLI Reference

Complete reference for all mcp-bash CLI commands.

## Server Commands

### mcp-bash (server mode)

Start the MCP server. Reads stdin for JSON-RPC messages, writes to stdout.

```bash
mcp-bash
```

**Required Environment:**
- `MCPBASH_PROJECT_ROOT`: Path to project directory
- `MCPBASH_TOOL_ALLOWLIST`: Allowed tool names (`*` for all)

**Example:**
```bash
MCPBASH_PROJECT_ROOT=/path/to/project MCPBASH_TOOL_ALLOWLIST="*" mcp-bash
```

### mcp-bash debug

Start server with full payload logging to stderr.

```bash
mcp-bash debug
```

### mcp-bash --version

Show version number.

```bash
mcp-bash --version
# Output: 0.8.4
```

### mcp-bash --help

Show help message.

```bash
mcp-bash --help
```

### mcp-bash --health / --ready

Health check for load balancers. Returns exit code:
- `0`: Ready
- `1`: Unhealthy
- `2`: Misconfigured

```bash
mcp-bash --health
mcp-bash --ready
mcp-bash --health --timeout 10
```

## Project Management

### mcp-bash new

Create a new project directory with full scaffold.

```bash
mcp-bash new <name> [options]
```

**Options:**
- `--no-hello`: Skip creating the example hello tool

**Example:**
```bash
mcp-bash new my-server
mcp-bash new my-server --no-hello
```

**Creates:**
```
my-server/
├── tools/
│   └── hello/
│       ├── tool.sh
│       └── tool.meta.json
├── resources/
├── prompts/
├── completions/
├── server.d/
│   └── server.meta.json
└── .registry/
```

### mcp-bash init

Initialize MCP project in current directory.

```bash
mcp-bash init [options]
```

**Options:**
- `--name <name>`: Server name (defaults to directory name)
- `--no-hello`: Skip creating example tool

**Example:**
```bash
cd existing-project
mcp-bash init --name my-server
```

### mcp-bash scaffold

Generate component templates.

```bash
mcp-bash scaffold <type> <name>
```

**Types:**
- `tool`: Create tool.sh and tool.meta.json
- `resource`: Create resource file and metadata
- `prompt`: Create prompt template and metadata
- `completion`: Create completion provider
- `test`: Create test harness

**Examples:**
```bash
mcp-bash scaffold tool my-tool
mcp-bash scaffold resource config
mcp-bash scaffold prompt code-review
mcp-bash scaffold completion branch-names
mcp-bash scaffold test
```

**Tool scaffold creates:**
```
tools/my-tool/
├── tool.sh
├── tool.meta.json
└── smoke.sh
```

## Validation and Diagnostics

### mcp-bash validate

Validate project structure and metadata.

```bash
mcp-bash validate [options]
```

**Options:**
- `--project-root <path>`: Override project root
- `--fix`: Auto-fix common issues
- `--json`: Machine-readable output
- `--explain-defaults`: Show applied default values
- `--strict`: Strict MCP spec validation
- `--inspector`: Print MCP Inspector command

**Examples:**
```bash
# Basic validation
mcp-bash validate

# Show what defaults are applied
mcp-bash validate --explain-defaults

# Auto-fix issues
mcp-bash validate --fix

# Strict spec compliance
mcp-bash validate --strict

# Get MCP Inspector command
mcp-bash validate --inspector
```

### mcp-bash doctor

Environment diagnostics and repair.

```bash
mcp-bash doctor [options]
```

**Options:**
- `--json`: Machine-readable output
- `--dry-run`: Show proposed repairs without applying
- `--fix`: Apply repairs (managed installations only)

**Checks:**
- Shell version and features
- JSON tool availability (jq/gojq)
- Framework installation
- PATH configuration
- Required dependencies

**Examples:**
```bash
mcp-bash doctor
mcp-bash doctor --json
mcp-bash doctor --dry-run
mcp-bash doctor --fix
```

## Tool Invocation

### mcp-bash run-tool

Invoke a tool directly without starting the server.

```bash
mcp-bash run-tool <tool-name> [options]
```

**Options:**
- `--args <json>`: Tool arguments as JSON
- `--dry-run`: Validate without execution
- `--roots <paths>`: Comma-separated root paths
- `--timeout <seconds>`: Override timeout
- `--verbose`: Stream stderr output
- `--print-env`: Show tool environment
- `--allow-self`: Add self to allowlist
- `--allow <tools>`: Comma-separated additional tools

**Examples:**
```bash
# Simple invocation
mcp-bash run-tool my-tool

# With arguments
mcp-bash run-tool my-tool --args '{"name":"test","count":5}'

# Simulate roots
mcp-bash run-tool my-tool --roots /home/user/project,/tmp/data

# Validate only
mcp-bash run-tool my-tool --dry-run

# Override timeout
mcp-bash run-tool my-tool --timeout 60

# Debug mode
mcp-bash run-tool my-tool --verbose --print-env
```

## Client Configuration

### mcp-bash config

Generate client configuration snippets.

```bash
mcp-bash config [options]
```

**Options:**
- `--show`: Show all client configurations
- `--json`: Machine-readable descriptor
- `--client <name>`: Specific client (claude-desktop, cursor, windsurf)
- `--wrapper`: Generate wrapper script
- `--wrapper-env`: Login-aware wrapper for macOS
- `--inspector`: Ready-to-run MCP Inspector command

**Examples:**
```bash
# All clients
mcp-bash config --show

# Specific client
mcp-bash config --client claude-desktop
mcp-bash config --client cursor

# JSON descriptor
mcp-bash config --json

# Wrapper scripts
mcp-bash config --wrapper
mcp-bash config --wrapper-env

# MCP Inspector
mcp-bash config --inspector
```

**Client configuration locations:**
- Claude Desktop (macOS): `~/Library/Application Support/Claude/claude_desktop_config.json`
- Claude Desktop (Linux): `~/.config/Claude/claude_desktop_config.json`
- Cursor: `~/.cursor/mcp.json`

**Example Claude Desktop config:**
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

## Registry Management

### mcp-bash registry

Manage the capability registry cache.

```bash
mcp-bash registry <subcommand>
```

**Subcommands:**
- `refresh`: Force registry rebuild
- `status`: Show cache status (hash, mtime, counts)

**Examples:**
```bash
mcp-bash registry refresh
mcp-bash registry status
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error / unhealthy |
| 2 | Misconfiguration |
| 130 | Interrupted (Ctrl+C) |

## Environment Variables

### Required for Server Mode

| Variable | Description |
|----------|-------------|
| `MCPBASH_PROJECT_ROOT` | Project directory path |
| `MCPBASH_TOOL_ALLOWLIST` | Space/comma-separated tool names (`*` for all) |

### Common Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MCPBASH_LOG_LEVEL` | `info` | Log level (debug, info, warning, error) |
| `MCPBASH_DEFAULT_TOOL_TIMEOUT` | `30` | Default timeout in seconds |
| `MCPBASH_MAX_CONCURRENT_REQUESTS` | `16` | Worker concurrency cap |
| `MCPBASH_TOOL_ENV_MODE` | `minimal` | Environment isolation mode |

### Directory Overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `MCPBASH_TOOLS_DIR` | `$PROJECT/tools` | Tools directory |
| `MCPBASH_RESOURCES_DIR` | `$PROJECT/resources` | Resources directory |
| `MCPBASH_PROMPTS_DIR` | `$PROJECT/prompts` | Prompts directory |
| `MCPBASH_SERVER_DIR` | `$PROJECT/server.d` | Server hooks directory |
| `MCPBASH_PROVIDERS_DIR` | `$PROJECT/providers` | Custom providers directory |
| `MCPBASH_REGISTRY_DIR` | `$PROJECT/.registry` | Registry cache directory |

### Security

| Variable | Default | Description |
|----------|---------|-------------|
| `MCPBASH_HTTPS_ALLOW_HOSTS` | (none) | HTTPS provider host allowlist |
| `MCPBASH_REMOTE_TOKEN` | (none) | Shared secret for proxied deployments (32+ chars) |
| `MCPBASH_ALLOW_PROJECT_HOOKS` | `false` | Enable server.d/register.sh execution |

### Debugging

| Variable | Default | Description |
|----------|---------|-------------|
| `MCPBASH_DEBUG_PAYLOADS` | (unset) | Write full payloads to state dir |
| `MCPBASH_PRESERVE_STATE` | (unset) | Keep state dir after exit |
| `MCPBASH_DEBUG_ERRORS` | `false` | Include diagnostics in errors |

See `docs/ENV_REFERENCE.md` for the complete list of 60+ environment variables.
