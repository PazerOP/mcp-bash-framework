# Project Structure Guide

## Overview

`mcp-bash` follows a strict **framework/project separation** model. The framework is an immutable engine installed once (e.g., `~/mcp-bash` or as a Docker base image), while your server code lives in a separate **project directory**.

## The Model

```
MCPBASH_HOME (Read-Only)              MCPBASH_PROJECT_ROOT (Your Code)
~/mcp-bash/                           ~/my-mcp-server/
├── bin/mcp-bash          ────────>   ├── tools/
├── lib/                               │   └── my-tool/
├── handlers/                          │       ├── tool.sh
└── ...                                │       └── tool.meta.json
                                       ├── prompts/
                                       ├── resources/
                                       ├── server.d/
                                       │   └── register.sh
                                       └── .registry/  (auto-generated cache)
```

## Required Configuration

You **must** set the `MCPBASH_PROJECT_ROOT` environment variable to point to your project directory. Without it, the server will refuse to start.

### Example: Claude Desktop Configuration

```json
{
  "mcpServers": {
    "my-server": {
      "command": "/Users/me/.mcp-bash/bin/mcp-bash",
      "env": {
        "MCPBASH_PROJECT_ROOT": "/Users/me/my-mcp-server"
      }
    }
  }
}
```

### Example: Docker Deployment

```dockerfile
FROM debian:bookworm-slim

# Install framework (read-only layer)
COPY mcp-bash/ /mcp-bash/

# Copy project (writable layer)
COPY my-server/ /app/

ENV MCPBASH_PROJECT_ROOT=/app

CMD ["/mcp-bash/bin/mcp-bash"]
```

## Path Resolution

The framework uses the following precedence to locate content:

| Content Type | Variable | Default |
|--------------|----------|---------|
| Tools | `MCPBASH_TOOLS_DIR` | `$MCPBASH_PROJECT_ROOT/tools` |
| Resources | `MCPBASH_RESOURCES_DIR` | `$MCPBASH_PROJECT_ROOT/resources` |
| Prompts | `MCPBASH_PROMPTS_DIR` | `$MCPBASH_PROJECT_ROOT/prompts` |
| Server Hooks | `MCPBASH_SERVER_DIR` | `$MCPBASH_PROJECT_ROOT/server.d` |
| Registry Cache | `MCPBASH_REGISTRY_DIR` | `$MCPBASH_PROJECT_ROOT/.registry` |

**Advanced**: You can override individual directories for complex layouts:

```bash
export MCPBASH_PROJECT_ROOT=/app
export MCPBASH_TOOLS_DIR=/app/tools-v2      # Override tools location
export MCPBASH_PROMPTS_DIR=/shared/prompts  # Shared prompts
```

## Tool SDK Discovery

Before a tool script runs, `lib/tools.sh` exports `MCP_SDK` pointing at the framework's `sdk/` directory so your script can source `${MCP_SDK}/tool-sdk.sh`. The templates checked into this repository also fall back to resolving `sdk/` relative to the script when you execute them directly during development. When copying tools into a different project tree, set `MCP_SDK` yourself (see [SDK Discovery](../README.md#sdk-discovery)) so the helpers can be located consistently.

## Example Project Layouts

### Minimal Project

```
my-server/
├── tools/
│   └── hello/
│       ├── tool.sh
│       └── tool.meta.json
└── .registry/  (created automatically)
```

To create this structure:

```bash
mkdir -p my-server/tools
export MCPBASH_PROJECT_ROOT=$(pwd)/my-server
~/mcp-bash/bin/mcp-bash scaffold tool hello
```

### Full-Featured Project

```
my-devops-server/
├── tools/
│   ├── check-k8s/
│   ├── deploy-app/
│   └── rollback/
├── prompts/
│   └── incident-response/
├── resources/
│   └── deployment-history/
├── server.d/
│   └── register.sh
├── lib/
│   └── common.sh          # Your shared utilities
└── .registry/             (auto-generated)
```

### Multi-Environment Project

```
company-mcp-servers/
├── dev/
│   ├── tools/
│   └── resources/
├── staging/
│   ├── tools/
│   └── resources/
└── production/
    ├── tools/
    └── resources/
```

Configure each environment separately:

```json
{
  "mcpServers": {
    "dev": {
      "command": "/Users/me/.mcp-bash/bin/mcp-bash",
      "env": {
        "MCPBASH_PROJECT_ROOT": "/projects/company-mcp-servers/dev"
      }
    },
    "production": {
      "command": "/Users/me/.mcp-bash/bin/mcp-bash",
      "env": {
        "MCPBASH_PROJECT_ROOT": "/projects/company-mcp-servers/production"
      }
    }
  }
}
```

## Version Control Strategy

**Best Practice**: Keep your project under version control, but not the framework.

```bash
# Your project repository
my-server/
├── .git/
├── tools/
├── prompts/
├── .gitignore   # Add: .registry/
└── README.md
```

**`.gitignore`**:
```
.registry/
*.log
```

Upgrades are simple:

```bash
# Upgrade framework
cd ~/mcp-bash
git pull

# Your project is unaffected
cd ~/my-server
git status  # Clean
```

## Debugging Path Resolution

Set `MCPBASH_LOG_LEVEL=debug` to see resolved paths at startup:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "/Users/me/.mcp-bash/bin/mcp-bash",
      "env": {
        "MCPBASH_PROJECT_ROOT": "/Users/me/my-server",
        "MCPBASH_LOG_LEVEL": "debug"
      }
    }
  }
}
```

You'll see output like:

```
Resolved paths:
  MCPBASH_HOME=/Users/me/.mcp-bash
  MCPBASH_PROJECT_ROOT=/Users/me/my-server
  MCPBASH_TOOLS_DIR=/Users/me/my-server/tools
  MCPBASH_RESOURCES_DIR=/Users/me/my-server/resources
  MCPBASH_PROMPTS_DIR=/Users/me/my-server/prompts
  MCPBASH_REGISTRY_DIR=/Users/me/my-server/.registry
```

## Benefits of This Model

1. **Clean Upgrades**: Update the framework without touching your code
2. **Version Control**: Track your project separately from the framework
3. **Read-Only Installs**: Framework can live in `/opt`, Docker layers, or NFS mounts
4. **Multi-Project**: Run multiple servers from one framework installation
5. **Security**: Framework and project can have different permissions
