# 01-args-and-validation

## Goal
Demonstrates argument parsing and validation errors.

## Run
```
./examples/run 01-args-and-validation
```
Send requests with the argument:
```
printf '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{}}\n{"jsonrpc":"2.0","method":"notifications/initialized"}\n{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"example.echoArg","arguments":{"value":"hi"}}}\n' | ./examples/run 01-args-and-validation
```

## SDK Helpers
`examples/run` sets `MCP_SDK` automatically so the tool can source the shared helpers. If you invoke `tools/echo-arg.sh` directly, export `MCP_SDK` yourself (see [SDK Discovery](../../README.md#sdk-discovery)).

## Transcript
```
> tools/call example.echoArg {"value":"hi"}
< {"result":{"content":[{"type":"text","text":"You sent: hi"}]}}
```

To see validation failure:
```
printf '{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"example.echoArg"}}\n' | ./examples/run 01-args-and-validation
```

## Troubleshooting
- Ensure scripts are executable: `chmod +x examples/01-args-and-validation/tools/*.sh`
- Install `jq` for nicer JSON handling.
