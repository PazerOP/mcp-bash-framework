# 07-elicitation

**What you’ll learn**
- How tools invoke the elicitation flow (`mcp_elicit_confirm`, `mcp_elicit_choice`)
- Normalized response handling (`action` + `content`) and fallbacks when the client doesn’t support elicitation

**Prereqs**
- Bash 3.2+
- jq or gojq (required for elicitation helpers)

**Run**
```
./examples/run 07-elicitation
```

**What it does**
- Asks for a confirmation (yes/no)
- If confirmed, asks you to pick a mode from a list
- Always returns a text summary; when the client doesn’t support elicitation it records the decline and exits cleanly

**Success criteria**
- `tools/list` shows `example.elicitation`
- Calling `example.elicitation` emits either a declined message or the chosen mode depending on client support and responses
