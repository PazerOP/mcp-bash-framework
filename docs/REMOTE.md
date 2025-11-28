# Remote Connectivity

mcp-bash implements only the stdio transport. HTTP, SSE, OAuth, and remote access are handled by external gateways and proxies.

## Choose Your Gateway

| Use Case | Recommended Tool |
|----------|------------------|
| Docker Desktop users | [Docker MCP Gateway](https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/) |
| Lightweight standalone proxy | [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) |
| Kubernetes deployments | [Microsoft MCP Gateway](https://github.com/microsoft/mcp-gateway) |
| APISIX API gateway users | [mcp-bridge plugin](https://dev.to/apisix/from-stdio-to-http-sse-host-your-mcp-server-with-apisix-api-gateway-26i2) |

---

## Quick Start: mcp-proxy (Simplest)

[mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) is a lightweight Python-based bidirectional proxy that bridges stdio and HTTP/SSE. Best for standalone deployments without Docker Desktop.

### Installation

```bash
pip install mcp-proxy
```

### Usage

```bash
# Point to your project directory (tools/, resources/, prompts/)
export MCPBASH_PROJECT_ROOT=/path/to/your/project

# Point to where you cloned/installed the mcp-bash framework
mcp-proxy \
  --host 0.0.0.0 \
  --port 8080 \
  --env MCPBASH_PROJECT_ROOT="$MCPBASH_PROJECT_ROOT" \
  /path/to/mcp-bash-framework/bin/mcp-bash
```

Clients connect to `http://<host>:8080/sse`.

### Production Options

| Flag | Purpose |
|------|---------|
| `--allow-origin` | Configure CORS for browser/cross-origin clients |
| `--named-server-config` | Multiplex multiple projects on one proxy |

See the [mcp-proxy README](https://github.com/sparfenyuk/mcp-proxy) for full documentation.

---

## Quick Start: Docker MCP Gateway

[Docker MCP Gateway](https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/) is Docker's official solution for orchestrating MCP servers. It runs servers in isolated containers with built-in secrets management, logging, and access control.

### With Docker Desktop

If you have Docker Desktop with MCP Toolkit enabled, the gateway runs automatically. Configure servers through the Docker Desktop UI.

### With Docker Engine (CLI)

Install the CLI plugin:

```bash
# Download from https://github.com/docker/mcp-gateway/releases
# Place in ~/.docker/cli-plugins/docker-mcp
chmod +x ~/.docker/cli-plugins/docker-mcp
```

Then use:

```bash
docker mcp server enable <server-name>
docker mcp client connect <client-name>
docker mcp gateway run
```

See [Docker MCP Gateway docs](https://docs.docker.com/ai/mcp-catalog-and-toolkit/mcp-gateway/) for details.

---

## Quick Start: Microsoft MCP Gateway (Kubernetes)

[Microsoft MCP Gateway](https://github.com/microsoft/mcp-gateway) is a reverse proxy and management layer for MCP servers in Kubernetes environments. It provides session-aware stateful routing and scalable lifecycle management.

Best for enterprise deployments requiring:
- Horizontal scaling
- Session affinity
- Kubernetes-native orchestration

See the [Microsoft MCP Gateway README](https://github.com/microsoft/mcp-gateway) for setup instructions.

---

## Protocol Notes

When bridging stdio to HTTP, gateways must:

- Maintain session headers (`Mcp-Session-Id`, `MCP-Protocol-Version`)
- Support Streamable HTTP semantics (POST for RPC, GET for SSE)
- Handle backwards-compatible HTTP+SSE for older clients

See the [MCP Transports specification](https://modelcontextprotocol.io/docs/concepts/transports) for wire semantics.

---

## Scope

OAuth, SSE, and HTTP transports remain out of scope for the mcp-bash core runtime. Consult gateway documentation before exposing mcp-bash beyond localhost.
