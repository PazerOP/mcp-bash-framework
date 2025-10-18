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

run_server() {
	local workdir="$1"
	local request_file="$2"
	local response_file="$3"
	(
		cd "${workdir}" || exit 1
		./bin/mcp-bash <"${request_file}" >"${response_file}"
	)
}

# --- Auto-discovery pagination and structured output ---
AUTO_ROOT="${TEST_TMPDIR}/auto"
stage_workspace "${AUTO_ROOT}"
chmod -x "${AUTO_ROOT}/server.d/register.sh"
mkdir -p "${AUTO_ROOT}/tools"
cp -a "${MCPBASH_ROOT}/examples/00-hello-tool/tools/." "${AUTO_ROOT}/tools/"

cat <<'METADATA' >"${AUTO_ROOT}/tools/world.meta.yaml"
{
  "name": "world",
  "description": "Structured world tool",
  "arguments": {
    "type": "object",
    "properties": {}
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "message": { "type": "string" }
    },
    "required": ["message"]
  }
}
METADATA

cat <<'SH' >"${AUTO_ROOT}/tools/world.sh"
#!/usr/bin/env bash
printf '{"message":"world"}'
SH
chmod +x "${AUTO_ROOT}/tools/world.sh"

cat <<'JSON' >"${AUTO_ROOT}/requests.ndjson"
{"jsonrpc":"2.0","id":"auto-init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"auto-list","method":"tools/list","params":{"limit":1}}
{"jsonrpc":"2.0","id":"auto-call","method":"tools/call","params":{"name":"world","arguments":{}}}
JSON

run_server "${AUTO_ROOT}" "${AUTO_ROOT}/requests.ndjson" "${AUTO_ROOT}/responses.ndjson"

python3 - "${AUTO_ROOT}/responses.ndjson" <<'PY'
import json, sys

path = sys.argv[1]
messages = []
with open(path, "r", encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        messages.append(json.loads(line))

def by_id(message_id):
    for msg in messages:
        if msg.get("id") == message_id:
            return msg
    raise SystemExit(f"missing response {message_id}")

list_resp = by_id("auto-list")
result = list_resp.get("result") or {}
items = result.get("items") or []
if result.get("total") < 2:
    raise SystemExit("expected at least two tools discovered")
if "nextCursor" not in result:
    raise SystemExit("expected nextCursor for pagination")

call_resp = by_id("auto-call")
call_result = call_resp.get("result") or {}
structured = call_result.get("structuredContent")
if not structured or structured.get("message") != "world":
    raise SystemExit("tool structuredContent missing expected payload")
texts = [entry.get("text") for entry in call_result.get("content", []) if entry.get("type") == "text"]
if not texts or "world" not in texts[0]:
    raise SystemExit("tool text fallback missing expected output")
meta = call_result.get("_meta", {})
if meta.get("exitCode") != 0:
    raise SystemExit("tool exitCode should be 0")
PY

# --- Manual registration overrides ---
MANUAL_ROOT="${TEST_TMPDIR}/manual"
stage_workspace "${MANUAL_ROOT}"
mkdir -p "${MANUAL_ROOT}/tools/manual"

cat <<'SH' >"${MANUAL_ROOT}/tools/manual/alpha.sh"
#!/usr/bin/env bash
printf '{"alpha":"one"}'
SH
chmod +x "${MANUAL_ROOT}/tools/manual/alpha.sh"

cat <<'SH' >"${MANUAL_ROOT}/tools/manual/beta.sh"
#!/usr/bin/env bash
printf 'beta'
SH
chmod +x "${MANUAL_ROOT}/tools/manual/beta.sh"

cat <<'SCRIPT' >"${MANUAL_ROOT}/server.d/register.sh"
#!/usr/bin/env bash
set -euo pipefail

mcp_register_tool '{
  "name": "manual-alpha",
  "description": "Manual alpha tool",
  "path": "tools/manual/alpha.sh",
  "arguments": {"type": "object", "properties": {}},
  "outputSchema": {
    "type": "object",
    "properties": {"alpha": {"type": "string"}},
    "required": ["alpha"]
  }
}'

mcp_register_tool '{
  "name": "manual-beta",
  "description": "Manual beta tool",
  "path": "tools/manual/beta.sh",
  "arguments": {"type": "object", "properties": {}}
}'

return 0
SCRIPT
chmod +x "${MANUAL_ROOT}/server.d/register.sh"

cat <<'JSON' >"${MANUAL_ROOT}/requests.ndjson"
{"jsonrpc":"2.0","id":"manual-init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"manual-list","method":"tools/list","params":{"limit":1}}
{"jsonrpc":"2.0","id":"manual-call","method":"tools/call","params":{"name":"manual-alpha","arguments":{}}}
JSON

run_server "${MANUAL_ROOT}" "${MANUAL_ROOT}/requests.ndjson" "${MANUAL_ROOT}/responses.ndjson"

python3 - "${MANUAL_ROOT}/responses.ndjson" <<'PY'
import json, sys

path = sys.argv[1]
messages = []
with open(path, "r", encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        messages.append(json.loads(line))

def by_id(message_id):
    for msg in messages:
        if msg.get("id") == message_id:
            return msg
    raise SystemExit(f"missing response {message_id}")

list_resp = by_id("manual-list")
result = list_resp.get("result") or {}
items = result.get("items") or []
if result.get("total") != 2:
    raise SystemExit("manual registry should expose exactly two tools")
if "nextCursor" not in result:
    raise SystemExit("manual registry should provide nextCursor for pagination")
names = {item.get("name") for item in items}
if "manual-alpha" not in names:
    raise SystemExit("manual-alpha missing from manual registry")
if any(name == "hello" for name in names):
    raise SystemExit("auto-discovered tools should not appear when manual registry is active")

call_resp = by_id("manual-call")
call_result = call_resp.get("result") or {}
structured = call_result.get("structuredContent")
if not structured or structured.get("alpha") != "one":
    raise SystemExit("manual tool structuredContent missing")
meta = call_result.get("_meta", {})
if meta.get("exitCode") != 0:
    raise SystemExit("manual tool exitCode should be 0")
PY
