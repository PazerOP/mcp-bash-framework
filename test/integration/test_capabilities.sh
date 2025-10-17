#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

cat <<'JSON' >"${TMP}/requests.ndjson"
{"jsonrpc":"2.0","id":"1","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":"2","method":"tools/list"}
JSON

./examples/run 00-hello-tool <"${TMP}/requests.ndjson" >"${TMP}/responses.ndjson" || true

if ! grep -q '"id":"2"' "${TMP}/responses.ndjson"; then
  echo "tools/list response missing" >&2
  exit 1
fi
