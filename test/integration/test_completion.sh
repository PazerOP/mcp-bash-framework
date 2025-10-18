#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"
# shellcheck source=../common/assert.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/assert.sh"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

cat <<'JSON' >"${TMP}/requests.ndjson"
{"jsonrpc":"2.0","id":"1","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"2","method":"completion/complete","params":{"name":"example","arguments":{"query":"plan roadmap"},"limit":1}}
JSON

"${MCPBASH_ROOT}/examples/run" 00-hello-tool <"${TMP}/requests.ndjson" >"${TMP}/responses.ndjson" || true

if ! grep -q '"id":"2"' "${TMP}/responses.ndjson"; then
	test_fail "completion/complete response missing"
fi

python3 - "${TMP}/responses.ndjson" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as fh:
    responses = [json.loads(line) for line in fh if line.strip()]
resp = next((item for item in responses if item.get('id') == '2'), None)
if resp is None:
    raise SystemExit("completion response missing")
result = resp.get('result')
if not result:
    raise SystemExit("missing result field")
suggestions = result.get('suggestions', [])
if len(suggestions) != 1:
    raise SystemExit(f"expected 1 suggestion, got {len(suggestions)}")
item = suggestions[0]
if item.get('type') != 'text':
    raise SystemExit(f"unexpected suggestion type: {item}")
text = item.get('text', '')
if 'plan roadmap' not in text:
    raise SystemExit(f"suggestion text mismatch: {text!r}")
if not result.get('hasMore'):
    raise SystemExit("hasMore should be true when limit truncates")
PY
