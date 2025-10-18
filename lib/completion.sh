#!/usr/bin/env bash
# Spec §8 completions handler helpers.

set -euo pipefail

mcp_completion_suggestions=""
mcp_completion_has_more=false
mcp_completion_cursor=""

mcp_completion_suggestions_count() {
  local py
  if ! py="$(mcp_tools_python 2>/dev/null)"; then
    printf '0'
    return 0
  fi
  printf '%s' "$(
    SUGGESTIONS="${mcp_completion_suggestions}" "${py}" <<'PY'
import json, os
try:
    print(len(json.loads(os.environ.get("SUGGESTIONS", "[]"))))
except Exception:
    print(0)
PY
  )"
}

mcp_completion_reset() {
  mcp_completion_suggestions="[]"
  mcp_completion_has_more=false
  mcp_completion_cursor=""
}

mcp_completion_add_text() {
  local text="$1"
  local py
  local count
  count="$(mcp_completion_suggestions_count)"
  if [ "${count}" -ge 100 ]; then
    mcp_completion_has_more=true
    return 1
  fi
  if ! py="$(mcp_tools_python 2>/dev/null)"; then
    mcp_completion_suggestions="[]"
    return 1
  fi
  mcp_completion_suggestions="$(
    SUGGESTIONS="${mcp_completion_suggestions}" TEXT="${text}" "${py}" <<'PY'
import json, os
suggestions = json.loads(os.environ.get("SUGGESTIONS", "[]"))
text = os.environ.get("TEXT", "")
suggestions.append({"type": "text", "text": text})
print(json.dumps(suggestions, ensure_ascii=False, separators=(',', ':')))
PY
  )"
  return 0
}

mcp_completion_add_json() {
  local json_payload="$1"
  local py
  local count
  count="$(mcp_completion_suggestions_count)"
  if [ "${count}" -ge 100 ]; then
    mcp_completion_has_more=true
    return 1
  fi
  if ! py="$(mcp_tools_python 2>/dev/null)"; then
    mcp_completion_suggestions="[]"
    return 1
  fi
  mcp_completion_suggestions="$(
    SUGGESTIONS="${mcp_completion_suggestions}" PAYLOAD="${json_payload}" "${py}" <<'PY'
import json, os
suggestions = json.loads(os.environ.get("SUGGESTIONS", "[]"))
payload = json.loads(os.environ.get("PAYLOAD", "{}"))
suggestions.append(payload)
print(json.dumps(suggestions, ensure_ascii=False, separators=(',', ':')))
PY
  )"
  return 0
}

mcp_completion_finalize() {
  local py
  if ! py="$(mcp_tools_python 2>/dev/null)"; then
    printf '{"suggestions":[],"hasMore":false}'
    return 0
  fi
  local has_more_json="false"
  if [ "${mcp_completion_has_more}" = true ]; then
    has_more_json="true"
  fi
  printf '%s' "$(
    SUGGESTIONS="${mcp_completion_suggestions}" HAS_MORE="${has_more_json}" CURSOR="${mcp_completion_cursor}" "${py}" <<'PY'
import json, os
suggestions = json.loads(os.environ.get("SUGGESTIONS", "[]"))
has_more = os.environ.get("HAS_MORE", "false") == "true"
cursor = os.environ.get("CURSOR", "")
result = {"suggestions": suggestions, "hasMore": has_more}
if cursor:
    result["cursor"] = cursor
print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))
PY
  )"
}
