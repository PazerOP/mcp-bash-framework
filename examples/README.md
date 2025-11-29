# Examples

Run any example from the repo root:
```bash
./examples/run <example-id>
```

MCP Inspector (stdio) quickstart:
```bash
npx @modelcontextprotocol/inspector --transport stdio -- ./examples/run 07-elicitation
```
The `--` separator prevents the inspector from treating `./examples/run` as its own flag. Replace `07-elicitation` with any example ID (e.g., `advanced/ffmpeg-studio`).
