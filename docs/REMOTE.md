# Remote Connectivity Options

- For streamable HTTP/SSE transports, pair mcp-bash with a gateway (e.g., Microsoft MCP Gateway or Docker MCP Gateway) as described in Spec §19.
- Maintain session headers (`Mcp-Session-Id`, `MCP-Protocol-Version`) when bridging stdio to HTTP; our tests include placeholders to verify compliance.
- OAuth/SSE proxies remain out of scope for the core runtime; consult gateway documentation before exposing mcp-bash beyond localhost.
