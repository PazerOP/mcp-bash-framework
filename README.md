# mcp-bash

[![CI](https://img.shields.io/github/actions/workflow/status/yaniv-golan/mcp-bash-framework/ci.yml?branch=master&label=CI)](https://github.com/yaniv-golan/mcp-bash-framework/actions)
[![License](https://img.shields.io/github/license/yaniv-golan/mcp-bash-framework)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-%3E%3D3.2-green.svg)](https://www.gnu.org/software/bash/)
[![MCP Protocol](https://img.shields.io/badge/MCP-2025--06--18-blue)](https://spec.modelcontextprotocol.io/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#runtime-requirements)

**mcp-bash** is a professional-grade Model Context Protocol (MCP) server implementation written in pure Bash. It allows you to instantly expose shell scripts, binaries, and system commands as secure, AI-ready tools.

- **Zero-Dependency Core**: Runs on standard Bash 3.2+ (macOS default) without heavy runtimes.
- **Production Ready**: Supports concurrency, timeouts, structured logging, and cancellation out of the box.
- **Developer Friendly**: built-in scaffolding generators to write code for you.

## Quick Start

### 1. Configure Your Client
To use mcp-bash with Claude Desktop, add the following to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "bash": {
      "command": "/absolute/path/to/mcp-bash/bin/mcp-bash",
      "args": []
    }
  }
}
```

### 2. Create Your First Tool
Don't write boilerplate. Use the scaffold command:

```bash
# Generate a new tool named "check-disk"
./bin/mcp-bash scaffold tool check-disk
```

This creates `tools/check-disk/` with a ready-to-run script and metadata. Edit `tools/check-disk/tool.sh` to add your logic, and it will automatically appear in your MCP client on the next restart.

## Learn by Example

We provide a comprehensive suite of examples in the [`examples/`](examples/) directory to help you master the framework:

| Example | Concepts Covered |
|---------|------------------|
| [**00-hello-tool**](examples/00-hello-tool/) | Basic "Hello World" tool structure and metadata. |
| [**01-args-and-validation**](examples/01-args-and-validation/) | Handling JSON arguments and input validation. |
| [**02-logging-and-levels**](examples/02-logging-and-levels/) | Sending logs to the client and managing verbosity. |
| [**03-progress-and-cancellation**](examples/03-progress-and-cancellation/) | Long-running tasks, reporting progress, and handling user cancellation. |
| [**04-ffmpeg-studio**](examples/04-ffmpeg-studio/) | Real-world application: Video processing pipeline with media inspection. |

## Features at a Glance

- **Auto-Discovery**: Simply place scripts in `tools/`, `resources/`, or `prompts/`, and the server finds them.
- **Scaffolding**: Generates compliant tool, resource, and prompt templates (`bin/mcp-bash scaffold <type> <name>`).
- **Stdio Transport**: Safe, standard-input/output communication model.
- **Graceful Degradation**: Automatically detects available JSON tools (`gojq`, `jq`) or falls back to a minimal mode if none are present.

## Requirements

### Runtime Requirements
*   **Bash**: version 3.2 or higher (standard on macOS, Linux, and WSL).
*   **JSON Processor**: `gojq` (recommended) or `jq`.
    *   *Note*: If no JSON tool is found, the server runs in "Minimal Mode" (Lifecycle & Ping only).

### Development Requirements
If you plan to contribute to the core framework or run the test suite:
*   `shellcheck`: For static analysis.
*   `shfmt`: For code formatting.

---

## Architecture & Deep Dive

### Scope and Goals
- Bash-only Model Context Protocol server verified on macOS Bash 3.2, Linux Bash ≥3.2, and experimental Git-Bash/WSL environments.
- Stable, versioned core under `bin/`, `lib/`, `handlers/`, `providers/`, and `sdk/` with extension hooks in `tools/`, `resources/`, `prompts/`, and `server.d/`.
- Targets MCP protocol version `2025-06-18` while supporting negotiated downgrades; stdout MUST emit exactly one JSON object per line.
- Repository deliverables include the full codebase, documentation, examples, and CI assets required to operate the server—no omissions.
- Transport support is limited to stdio; HTTP/SSE/OAuth transports remain out of scope for mcp-bash.

### Runtime Detection
- JSON tooling detection order: `gojq` → `jq`. The first match enables the full protocol surface.
- Operators can set `MCPBASH_FORCE_MINIMAL=true` to deliberately enter the minimal capability tier even when tooling is present for diagnostics or compatibility checks.
- When no tooling is found, the core downgrades to minimal mode, exposing lifecycle, ping, and logging only.
- Legacy JSON-RPC batch arrays may be tolerated when `MCPBASH_COMPAT_BATCHES=true`, decomposing batches into individual requests prior to dispatch.

### Diagnostics & Logging
- The server honours the `MCPBASH_LOG_LEVEL` environment variable at startup (default `info`). Set `MCPBASH_LOG_LEVEL=debug` before launching `bin/mcp-bash` to surface discovery and subscription traces.
- Clients can still adjust verbosity dynamically via `logging/setLevel`; both the environment variable and client requests flow through the same log-level gate.
- Deep payload tracing remains opt-in: `MCPBASH_DEBUG_PAYLOADS=true` writes per-message payload logs under `${TMPDIR}/mcpbash.state.*`.
- All diagnostics route through the logging capability instead of raw `stderr`.

### Repository Layout
```
mcp-bash/
├─ bin/mcp-bash       # Entry point
├─ lib/               # Core libraries (JSON, RPC, concurrency)
├─ handlers/          # Protocol method handlers
├─ providers/         # Resource providers
├─ registry/          # Auto-generated registry caches
├─ tools/             # User-defined tools
├─ resources/         # User-defined resources
├─ prompts/           # User-defined prompts
└─ examples/          # Usage examples
```

### Concurrency Model
- Asynchronous requests (`tools/*`, `resources/*`, `prompts/get`, `completion/complete`) spawn background workers with request-aware state files.
- `lib/ids.sh` encodes JSON-RPC ids using base64url.
- `lib/lock.sh` and `lib/io.sh` provide mkdir-based stdout locking to ensure responses write exactly one JSON line even under concurrency.
- `lib/timeout.sh` implements `with_timeout <seconds>` watchdogs for all worker processes.

### Protocol Version Compatibility
This server targets MCP protocol version `2025-06-18` (the current stable specification) and supports negotiated downgrades during `initialize`.

| Version | Status |
|---------|--------|
| `2025-06-18` | ✅ Fully supported (default) |
| `2025-03-26` | ✅ Supported |
| `2024-11-05` | ❌ **Not supported** |

For more details, see:
- [`docs/ERRORS.md`](docs/ERRORS.md)
- [`docs/SECURITY.md`](docs/SECURITY.md)
- [`docs/LIMITS.md`](docs/LIMITS.md)
- [`TESTING.md`](TESTING.md)
