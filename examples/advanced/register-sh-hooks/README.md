# Advanced: register-sh-hooks

This advanced example demonstrates **project hook registration** via `server.d/register.sh`.

Use this only when you truly need **dynamic/imperative registration** (e.g., generate entries from the filesystem, environment, or other inputs). Prefer `server.d/register.json` for declarative registration.

## What you’ll learn

- How `server.d/register.sh` can register multiple kinds (completions + resource templates) dynamically.
- Why hooks are **opt-in** (`MCPBASH_ALLOW_PROJECT_HOOKS=true`) and treated as privileged code.
- How to avoid side effects: hooks should only emit registrations and avoid network, file writes, and background processes.

## Prereqs

- Bash 3.2+
- jq or gojq (full mode)

## Run

```bash
# Enable project hooks explicitly:
MCPBASH_ALLOW_PROJECT_HOOKS=true ./examples/run advanced/register-sh-hooks
```

## What it does

- Registers two completions:
  - `demo.completion`
  - `demo.completion.alt` (only when `DEMO_ENABLE_ALT_COMPLETION=true`)
- Registers a resource template:
  - `logs-by-date`

## Notes

- If `server.d/register.json` exists, it takes precedence and **this hook will not run**.
- Hook scripts are executed during registry refresh (often during list calls). Treat them as sensitive.
