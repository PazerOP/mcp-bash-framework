#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"

test_create_tmpdir

stage_workspace() {
	local dest="$1"
	mkdir -p "${dest}"
	cp -a "${MCPBASH_ROOT}/bin" "${dest}/"
	cp -a "${MCPBASH_ROOT}/lib" "${dest}/"
	cp -a "${MCPBASH_ROOT}/handlers" "${dest}/"
	cp -a "${MCPBASH_ROOT}/providers" "${dest}/"
	cp -a "${MCPBASH_ROOT}/sdk" "${dest}/"
	cp -a "${MCPBASH_ROOT}/resources" "${dest}/" 2>/dev/null || true
	cp -a "${MCPBASH_ROOT}/prompts" "${dest}/" 2>/dev/null || true
	cp -a "${MCPBASH_ROOT}/server.d" "${dest}/"
}

# --- Auto-discovery prompts ---
AUTO_ROOT="${TEST_TMPDIR}/auto"
stage_workspace "${AUTO_ROOT}"
chmod -x "${AUTO_ROOT}/server.d/register.sh"
mkdir -p "${AUTO_ROOT}/prompts"

cat <<'EOF_PROMPT' >"${AUTO_ROOT}/prompts/alpha.txt"
Hello ${name}!
EOF_PROMPT

cat <<'EOF_META' >"${AUTO_ROOT}/prompts/alpha.meta.yaml"
{"name": "prompt.alpha", "description": "Alpha prompt", "arguments": {"type": "object", "properties": {"name": {"type": "string"}}}, "role": "system"}
EOF_META

cat <<'EOF_PROMPT' >"${AUTO_ROOT}/prompts/beta.txt"
Beta prompt for ${topic}
EOF_PROMPT

cat <<'EOF_META' >"${AUTO_ROOT}/prompts/beta.meta.yaml"
{"name": "prompt.beta", "description": "Beta prompt", "arguments": {"type": "object", "properties": {"topic": {"type": "string"}}}, "role": "system"}
EOF_META

cat <<'JSON' >"${AUTO_ROOT}/requests.ndjson"
{"jsonrpc":"2.0","id":"auto-init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"auto-list","method":"prompts/list","params":{"limit":1}}
{"jsonrpc":"2.0","id":"auto-get","method":"prompts/get","params":{"name":"prompt.alpha","arguments":{"name":"World"}}}
JSON

(
	cd "${AUTO_ROOT}" || exit 1
	./bin/mcp-bash <"requests.ndjson" >"responses.ndjson"
)

python3 - "${AUTO_ROOT}/responses.ndjson" <<'PY'
import json, sys

path = sys.argv[1]
messages = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]

def by_id(msg_id):
    for msg in messages:
        if msg.get("id") == msg_id:
            return msg
    raise SystemExit(f"missing response for {msg_id}")

list_resp = by_id("auto-list")
result = list_resp.get("result") or {}
items = result.get("items") or []
if result.get("total") != 2:
    raise SystemExit(f"expected 2 prompts discovered, found {result.get('total')}")
if "nextCursor" not in result:
    raise SystemExit("expected nextCursor for paginated prompts")
first = items[0]
for field in ("name", "description", "path", "arguments"):
    if field not in first:
        raise SystemExit(f"prompt entry missing {field}")

get_resp = by_id("auto-get")
rendered = get_resp.get("result") or {}
text = rendered.get("text") or ""
if text.strip() != "Hello World!":
    raise SystemExit(f"rendered text mismatch: {text!r}")
messages_field = rendered.get("messages")
if not messages_field or not isinstance(messages_field, list):
    raise SystemExit("messages array missing from prompts/get result")
first_msg = messages_field[0]
content = first_msg.get("content")
if not content:
    raise SystemExit("structured message content mismatch")
content_text = (content[0].get("text") if content else "").strip()
if content_text != "Hello World!":
    raise SystemExit("structured message content mismatch")
arguments = rendered.get("arguments")
if arguments != {"name": "World"}:
    raise SystemExit(f"arguments echo mismatch: {arguments!r}")
PY

# --- Manual registration overrides ---
MANUAL_ROOT="${TEST_TMPDIR}/manual"
stage_workspace "${MANUAL_ROOT}"
mkdir -p "${MANUAL_ROOT}/prompts/manual"

cat <<'EOF_PROMPT' >"${MANUAL_ROOT}/prompts/manual/greet.txt"
Greetings ${name}, welcome aboard.
EOF_PROMPT

cat <<'EOF_PROMPT' >"${MANUAL_ROOT}/prompts/manual/farewell.txt"
Goodbye ${name}, see you soon.
EOF_PROMPT

cat <<'EOF_SCRIPT' >"${MANUAL_ROOT}/server.d/register.sh"
#!/usr/bin/env bash
set -euo pipefail

mcp_register_prompt '{
  "name": "manual.greet",
  "description": "Manual greet prompt",
  "path": "prompts/manual/greet.txt",
  "arguments": {"type": "object", "properties": {"name": {"type": "string"}}},
  "role": "system"
}'

mcp_register_prompt '{
  "name": "manual.farewell",
  "description": "Manual farewell prompt",
  "path": "prompts/manual/farewell.txt",
  "arguments": {"type": "object", "properties": {"name": {"type": "string"}}},
  "role": "system"
}'

return 0
EOF_SCRIPT
chmod +x "${MANUAL_ROOT}/server.d/register.sh"

cat <<'JSON' >"${MANUAL_ROOT}/requests.ndjson"
{"jsonrpc":"2.0","id":"manual-init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"manual-list","method":"prompts/list","params":{"limit":5}}
{"jsonrpc":"2.0","id":"manual-get","method":"prompts/get","params":{"name":"manual.farewell","arguments":{"name":"Ada"}}}
JSON

(
	cd "${MANUAL_ROOT}" || exit 1
	./bin/mcp-bash <"requests.ndjson" >"responses.ndjson"
)

python3 - "${MANUAL_ROOT}/responses.ndjson" <<'PY'
import json, sys

path = sys.argv[1]
messages = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]

def by_id(msg_id):
    for msg in messages:
        if msg.get("id") == msg_id:
            return msg
    raise SystemExit(f"missing response for {msg_id}")

list_resp = by_id("manual-list")
result = list_resp.get("result") or {}
items = result.get("items") or []
if result.get("total") != 2:
    raise SystemExit("manual registry should expose exactly two prompts")
names = {item.get("name") for item in items}
if names != {"manual.greet", "manual.farewell"}:
    raise SystemExit(f"unexpected manual prompt names: {names}")

get_resp = by_id("manual-get")
rendered = get_resp.get("result") or {}
text = (rendered.get("text") or "").strip()
if text != "Goodbye Ada, see you soon.":
    raise SystemExit("manual prompt render mismatch")
content = (rendered.get("messages", [{}])[0].get("content", [{}])[0].get("text") or "").strip()
if content != "Goodbye Ada, see you soon.":
    raise SystemExit("manual prompt structured content mismatch")
PY

# --- TTL-driven list_changed notifications ---
POLL_ROOT="${TEST_TMPDIR}/poll"
stage_workspace "${POLL_ROOT}"
chmod -x "${POLL_ROOT}/server.d/register.sh"
mkdir -p "${POLL_ROOT}/prompts"

cat <<'EOF_PROMPT' >"${POLL_ROOT}/prompts/live.txt"
Live version 1
EOF_PROMPT

cat <<'EOF_META' >"${POLL_ROOT}/prompts/live.meta.yaml"
{"name": "prompt.live", "description": "Live prompt", "arguments": {"type": "object", "properties": {}}, "role": "system"}
EOF_META

export POLL_ROOT
python3 <<'PY'
import json
import os
import subprocess
import sys
import time

poll_root = os.environ["POLL_ROOT"]
env = os.environ.copy()
env["MCP_PROMPTS_TTL"] = "1"

proc = subprocess.Popen(
    ["./bin/mcp-bash"],
    cwd=poll_root,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
    env=env,
)

def send(message):
    line = json.dumps(message, separators=(",", ":")) + "\n"
    proc.stdin.write(line)
    proc.stdin.flush()

def next_message(deadline):
    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            raise SystemExit("timeout waiting for server output")
        line = proc.stdout.readline()
        if not line:
            raise SystemExit("server exited unexpectedly")
        line = line.strip()
        if not line:
            continue
        return json.loads(line)

try:
    send({"jsonrpc": "2.0", "id": "init", "method": "initialize", "params": {}})
    deadline = time.time() + 10
    while True:
        msg = next_message(deadline)
        if msg.get("id") == "init":
            break

    send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    send({"jsonrpc": "2.0", "id": "list", "method": "prompts/list", "params": {}})
    deadline = time.time() + 10
    while True:
        msg = next_message(deadline)
        if msg.get("id") == "list":
            break

    with open(os.path.join(poll_root, "prompts", "live.txt"), "w", encoding="utf-8") as handle:
        handle.write("Live version 2\n")

    time.sleep(1.2)
    send({"jsonrpc": "2.0", "id": "ping", "method": "ping"})
    seen_update = False
    seen_ping = False
    deadline = time.time() + 10
    while not (seen_update and seen_ping):
        msg = next_message(deadline)
        if msg.get("id") == "ping":
            seen_ping = True
        if msg.get("method") == "notifications/prompts/list_changed":
            seen_update = True

    if not seen_update:
        raise SystemExit("missing prompts/list_changed notification after modification")

    send({"jsonrpc": "2.0", "id": "shutdown", "method": "shutdown"})
    deadline = time.time() + 10
    while True:
        msg = next_message(deadline)
        if msg.get("id") == "shutdown":
            break

    send({"jsonrpc": "2.0", "id": "exit", "method": "exit"})
    deadline = time.time() + 10
    while True:
        msg = next_message(deadline)
        if msg.get("id") == "exit":
            break
finally:
    if proc.stdin:
        try:
            proc.stdin.close()
        except Exception:
            pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
    if proc.returncode not in (0, None):
        raise SystemExit(f"server exited with code {proc.returncode}")
PY
