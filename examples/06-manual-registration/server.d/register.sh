#!/usr/bin/env bash
set -euo pipefail

cat <<'JSON'
{
  "tools": [
    {
      "name": "manual.progress",
      "description": "Emit progress updates from a manual registry entry",
      "path": "progress-demo.sh",
      "timeoutSecs": 8
    }
  ],
  "resources": [
    {
      "name": "echo.hello",
      "description": "Echo provider demo for manual registry entries",
      "path": "echo-placeholder.txt",
      "uri": "echo://Hello-from-manual-registry",
      "mimeType": "text/plain",
      "provider": "echo"
    }
  ],
  "prompts": [
    {
      "name": "manual.prompt",
      "description": "Explain how manual registration overrides discovery",
      "path": "manual.prompt.txt",
      "arguments": {
        "type": "object",
        "properties": {
          "topic": {
            "type": "string"
          }
        }
      }
    }
  ]
}
JSON
