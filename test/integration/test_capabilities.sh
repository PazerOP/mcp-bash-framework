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
{"jsonrpc":"2.0","id":"2","method":"tools/list"}
JSON

"${MCPBASH_ROOT}/examples/run" 00-hello-tool <"${TMP}/requests.ndjson" >"${TMP}/responses.ndjson" || true

if ! grep -q '"id":"2"' "${TMP}/responses.ndjson"; then
	test_fail "tools/list response missing"
fi
