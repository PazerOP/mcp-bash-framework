# 00-hello-tool

## Prerequisites
- Bash 3.2+
- Optional: jq/gojq for richer JSON tooling

## SDK Helpers
`examples/run` sets `MCP_SDK` automatically so the tool can source the shared helpers. If you execute `tools/hello.sh` directly, export `MCP_SDK` first (see [SDK Discovery](../../README.md#sdk-discovery)).

## Run
```
./examples/run 00-hello-tool
```
From another terminal, send a minimal sequence:
```
printf '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{}}\n{"jsonrpc":"2.0","method":"notifications/initialized"}\n{"jsonrpc":"2.0","id":"2","method":"tools/list"}\n{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"example.hello"}}\n' | ./examples/run 00-hello-tool
```

## Transcript (abridged)
```
> initialize
< {"result":{"capabilities":{...}}}
> tools/call example.hello
< {"result":{"content":[{"type":"text","text":"Hello from example tool"}]}}
```

## Troubleshooting
- Ensure the example directory is executable: `chmod +x examples/run`.
- If you see minimal-mode warnings, install `jq`.
