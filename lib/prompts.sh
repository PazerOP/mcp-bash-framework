#!/usr/bin/env bash
# Spec §8/§9 prompts discovery and rendering.

set -euo pipefail

MCP_PROMPTS_REGISTRY_JSON=""
MCP_PROMPTS_REGISTRY_HASH=""
MCP_PROMPTS_REGISTRY_PATH=""
# shellcheck disable=SC2034
MCP_PROMPTS_TOTAL=0
# shellcheck disable=SC2034
MCP_PROMPTS_ERR_CODE=0
# shellcheck disable=SC2034
MCP_PROMPTS_ERR_MESSAGE=""
MCP_PROMPTS_TTL="${MCP_PROMPTS_TTL:-5}"
MCP_PROMPTS_LAST_SCAN=0
MCP_PROMPTS_CHANGED=false
MCP_PROMPTS_LOGGER="${MCP_PROMPTS_LOGGER:-mcp.prompts}"
MCP_PROMPTS_MANUAL_ACTIVE=false
MCP_PROMPTS_MANUAL_BUFFER=""
MCP_PROMPTS_MANUAL_DELIM=$'\036'

mcp_prompts_log_python_warnings() {
	local warn_file="$1"
	if [ ! -f "${warn_file}" ]; then
		return 0
	fi
	if [ ! -s "${warn_file}" ]; then
		rm -f "${warn_file}"
		return 0
	fi
	while IFS= read -r warn_line || [ -n "${warn_line}" ]; do
		[ -n "${warn_line}" ] || continue
		mcp_logging_warning "${MCP_PROMPTS_LOGGER}" "${warn_line}"
	done <"${warn_file}"
	rm -f "${warn_file}"
}

mcp_prompts_manual_begin() {
	MCP_PROMPTS_MANUAL_ACTIVE=true
	MCP_PROMPTS_MANUAL_BUFFER=""
}

mcp_prompts_manual_abort() {
	MCP_PROMPTS_MANUAL_ACTIVE=false
	MCP_PROMPTS_MANUAL_BUFFER=""
}

mcp_prompts_register_manual() {
	local payload="$1"
	if [ "${MCP_PROMPTS_MANUAL_ACTIVE}" != "true" ]; then
		return 0
	fi
	if [ -z "${payload}" ]; then
		return 0
	fi
	if [ -n "${MCP_PROMPTS_MANUAL_BUFFER}" ]; then
		MCP_PROMPTS_MANUAL_BUFFER="${MCP_PROMPTS_MANUAL_BUFFER}${MCP_PROMPTS_MANUAL_DELIM}${payload}"
	else
		MCP_PROMPTS_MANUAL_BUFFER="${payload}"
	fi
	return 0
}

mcp_prompts_manual_finalize() {
	if [ "${MCP_PROMPTS_MANUAL_ACTIVE}" != "true" ]; then
		return 0
	fi
	local py
	py="$(mcp_prompts_python)" || {
		mcp_prompts_manual_abort
		mcp_prompts_error -32603 "Manual registration requires python"
		return 1
	}

	local registry_json
	if ! registry_json="$(
		ITEMS="${MCP_PROMPTS_MANUAL_BUFFER}" ROOT="${MCPBASH_ROOT}" DELIM="${MCP_PROMPTS_MANUAL_DELIM}" "${py}" <<'PY'
import json, os, hashlib, time, pathlib

def normalize_path(entry_path, root):
    if not entry_path:
        raise ValueError("Prompt entry missing path")
    root_path = pathlib.Path(root).resolve()
    candidate = pathlib.Path(entry_path)
    if candidate.is_absolute():
        resolved = candidate.resolve()
    else:
        resolved = (root_path / candidate).resolve()
    try:
        rel = resolved.relative_to(root_path)
    except ValueError:
        raise ValueError(f"Prompt path {entry_path!r} must be inside server root")
    return str(rel).replace("\\", "/")

buffer = os.environ.get("ITEMS", "")
delimiter = os.environ.get("DELIM", "\x1e")
root = os.environ.get("ROOT", "")
if delimiter:
    raw_entries = [entry for entry in buffer.split(delimiter) if entry]
else:
    raw_entries = [buffer] if buffer else []
items = []
seen = set()
for raw in raw_entries:
    data = json.loads(raw)
    name = str(data.get("name") or "").strip()
    if not name:
        raise ValueError("Prompt entry missing name")
    if name in seen:
        raise ValueError(f"Duplicate prompt name {name!r} in manual registration")
    seen.add(name)
    description = str(data.get("description") or "")
    path = normalize_path(str(data.get("path") or ""), root)
    arguments = data.get("arguments")
    if not isinstance(arguments, dict):
        arguments = {"type": "object", "properties": {}}
    role = data.get("role")
    if role is not None:
        role = str(role)
    metadata = data.get("metadata")
    if metadata is not None and not isinstance(metadata, dict):
        metadata = None
    entry = dict(data)
    entry["name"] = name
    entry["description"] = description
    entry["path"] = path
    entry["arguments"] = arguments
    if role is not None:
        entry["role"] = role
    if metadata is not None:
        entry["metadata"] = metadata
    items.append(entry)

items.sort(key=lambda x: x.get("name", ""))

hash_source = json.dumps(items, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
hash_value = hashlib.sha256(hash_source.encode('utf-8')).hexdigest()
registry = {
    "version": 1,
    "generatedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    "items": items,
    "hash": hash_value,
    "total": len(items)
}
print(json.dumps(registry, ensure_ascii=False, separators=(',', ':')))
PY
	)"; then
		mcp_prompts_manual_abort
		mcp_prompts_error -32603 "Manual registration parsing failed"
		return 1
	fi

	local previous_hash="${MCP_PROMPTS_REGISTRY_HASH}"
	MCP_PROMPTS_REGISTRY_JSON="${registry_json}"
	MCP_PROMPTS_REGISTRY_HASH="$(
		REGISTRY_JSON="${registry_json}" "${py}" <<'PY'
import json, os
print(json.loads(os.environ.get("REGISTRY_JSON", "{}")).get('hash', ''))
PY
	)"
	MCP_PROMPTS_TOTAL="$(
		REGISTRY_JSON="${registry_json}" "${py}" <<'PY'
import json, os
print(json.loads(os.environ.get("REGISTRY_JSON", "{}")).get('total', 0))
PY
	)"

	if ! mcp_prompts_enforce_registry_limits "${MCP_PROMPTS_TOTAL}" "${registry_json}"; then
		mcp_prompts_manual_abort
		return 1
	fi

	MCP_PROMPTS_LAST_SCAN="$(date +%s)"
	if [ "${previous_hash}" != "${MCP_PROMPTS_REGISTRY_HASH}" ]; then
		MCP_PROMPTS_CHANGED=true
	fi
	printf '%s' "${registry_json}" >"${MCP_PROMPTS_REGISTRY_PATH}"
	MCP_PROMPTS_MANUAL_ACTIVE=false
	MCP_PROMPTS_MANUAL_BUFFER=""
	return 0
}

mcp_prompts_run_manual_script() {
	if [ ! -x "${MCPBASH_REGISTER_SCRIPT}" ]; then
		return 1
	fi

	mcp_prompts_manual_begin

	local script_output_file
	script_output_file="$(mktemp "${MCPBASH_TMP_ROOT}/mcp-prompts-manual-output.XXXXXX")"
	local script_status=0

	set +e
	# shellcheck disable=SC1090
	. "${MCPBASH_REGISTER_SCRIPT}" >"${script_output_file}" 2>&1
	script_status=$?
	set -e

	local script_output
	script_output="$(cat "${script_output_file}" 2>/dev/null || true)"
	rm -f "${script_output_file}"

	if [ "${script_status}" -ne 0 ]; then
		mcp_prompts_manual_abort
		mcp_prompts_error -32603 "Manual registration script failed"
		if [ -n "${script_output}" ]; then
			mcp_logging_error "${MCP_PROMPTS_LOGGER}" "Manual registration script output: ${script_output}"
		fi
		return 1
	fi

	if [ -z "${MCP_PROMPTS_MANUAL_BUFFER}" ] && [ -n "${script_output}" ]; then
		mcp_prompts_manual_abort
		if ! mcp_prompts_apply_manual_json "${script_output}"; then
			return 1
		fi
		return 0
	fi

	if [ -n "${script_output}" ]; then
		mcp_logging_warning "${MCP_PROMPTS_LOGGER}" "Manual registration script output: ${script_output}"
	fi

	if ! mcp_prompts_manual_finalize; then
		return 1
	fi
	return 0
}
mcp_prompts_registry_max_bytes() {
	local limit="${MCPBASH_REGISTRY_MAX_BYTES:-104857600}"
	case "${limit}" in
	'' | *[!0-9]*) limit=104857600 ;;
	esac
	printf '%s' "${limit}"
}

mcp_prompts_enforce_registry_limits() {
	local total="$1"
	local json_payload="$2"
	local limit
	local size
	limit="$(mcp_prompts_registry_max_bytes)"
	size="$(LC_ALL=C printf '%s' "${json_payload}" | wc -c | tr -d ' ')"
	if [ "${size}" -gt "${limit}" ]; then
		MCP_PROMPTS_ERR_CODE=-32603
		MCP_PROMPTS_ERR_MESSAGE="Prompts registry exceeds ${limit} byte cap"
		return 1
	fi
	if [ "${total}" -gt 500 ]; then
		mcp_logging_warning "${MCP_PROMPTS_LOGGER}" "Prompts registry contains ${total} entries; consider manual registration"
	fi
	return 0
}

mcp_prompts_error() {
	MCP_PROMPTS_ERR_CODE="$1"
	MCP_PROMPTS_ERR_MESSAGE="$2"
}

mcp_prompts_python() {
	if command -v python3 >/dev/null 2>&1; then
		printf 'python3'
		return 0
	fi
	if command -v python >/dev/null 2>&1; then
		printf 'python'
		return 0
	fi
	return 1
}

mcp_prompts_init() {
	if [ -z "${MCP_PROMPTS_REGISTRY_PATH}" ]; then
		MCP_PROMPTS_REGISTRY_PATH="${MCPBASH_REGISTRY_DIR}/prompts.json"
	fi
	mkdir -p "${MCPBASH_REGISTRY_DIR}"
	mkdir -p "${MCPBASH_ROOT}/prompts" >/dev/null 2>&1 || true
}

mcp_prompts_apply_manual_json() {
	local manual_json="$1"
	local py
	py="$(mcp_prompts_python)" || {
		MCP_PROMPTS_ERR_CODE=-32603
		MCP_PROMPTS_ERR_MESSAGE="Manual registration requires python"
		return 1
	}
	local registry_json
	if ! registry_json="$(
		INPUT="${manual_json}" "${py}" <<'PY'
import json, os, hashlib, time
manual = json.loads(os.environ.get("INPUT", "{}"))
prompts = manual.get("prompts", [])
if not isinstance(prompts, list):
    prompts = []
now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
hash_source = json.dumps(prompts, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
hash_value = hashlib.sha256(hash_source.encode('utf-8')).hexdigest()
registry = {
    "version": 1,
    "generatedAt": now,
    "items": prompts,
    "hash": hash_value,
    "total": len(prompts)
}
print(json.dumps(registry, ensure_ascii=False, separators=(',', ':')))
PY
	)"; then
		return 1
	fi
	local new_hash
	new_hash="$(
		REGISTRY_JSON="${registry_json}" "${py}" <<'PY'
import json, os
print(json.loads(os.environ.get("REGISTRY_JSON", "{}")).get('hash', ''))
PY
	)"
	if [ "${new_hash}" != "${MCP_PROMPTS_REGISTRY_HASH}" ]; then
		MCP_PROMPTS_CHANGED=true
	fi
	MCP_PROMPTS_REGISTRY_JSON="${registry_json}"
	MCP_PROMPTS_REGISTRY_HASH="${new_hash}"
	# shellcheck disable=SC2034
	MCP_PROMPTS_TOTAL="$(
		REGISTRY_JSON="${registry_json}" "${py}" <<'PY'
import json, os
print(json.loads(os.environ.get("REGISTRY_JSON", "{}")).get('total', 0))
PY
	)"
	if ! mcp_prompts_enforce_registry_limits "${MCP_PROMPTS_TOTAL}" "${registry_json}"; then
		return 1
	fi
	MCP_PROMPTS_LAST_SCAN="$(date +%s)"
	printf '%s' "${registry_json}" >"${MCP_PROMPTS_REGISTRY_PATH}"
}

mcp_prompts_refresh_registry() {
	mcp_prompts_init
	if [ -x "${MCPBASH_REGISTER_SCRIPT}" ]; then
		if mcp_prompts_run_manual_script; then
			return 0
		fi
		mcp_logging_error "${MCP_PROMPTS_LOGGER}" "Manual registration script returned empty output or non-zero"
		return 1
	fi
	local now
	now="$(date +%s)"
	local py
	py="$(mcp_prompts_python 2>/dev/null)" || true
	if [ -z "${MCP_PROMPTS_REGISTRY_JSON}" ] && [ -f "${MCP_PROMPTS_REGISTRY_PATH}" ]; then
		MCP_PROMPTS_REGISTRY_JSON="$(cat "${MCP_PROMPTS_REGISTRY_PATH}")"
		if [ -n "${py}" ]; then
			MCP_PROMPTS_REGISTRY_HASH="$(
				REGISTRY_JSON="${MCP_PROMPTS_REGISTRY_JSON}" "${py}" <<'PY'
import json, os
print(json.loads(os.environ.get("REGISTRY_JSON", "{}")).get('hash', ''))
PY
			)"
			MCP_PROMPTS_TOTAL="$(
				REGISTRY_JSON="${MCP_PROMPTS_REGISTRY_JSON}" "${py}" <<'PY'
import json, os
print(json.loads(os.environ.get("REGISTRY_JSON", "{}")).get('total', 0))
PY
			)"
			if ! mcp_prompts_enforce_registry_limits "${MCP_PROMPTS_TOTAL}" "${MCP_PROMPTS_REGISTRY_JSON}"; then
				return 1
			fi
		fi
	fi
	if [ -n "${MCP_PROMPTS_REGISTRY_JSON}" ] && [ $((now - MCP_PROMPTS_LAST_SCAN)) -lt "${MCP_PROMPTS_TTL}" ]; then
		return 0
	fi
	local previous_hash="${MCP_PROMPTS_REGISTRY_HASH}"
	mcp_prompts_scan || return 1
	MCP_PROMPTS_LAST_SCAN="${now}"
	if [ "${previous_hash}" != "${MCP_PROMPTS_REGISTRY_HASH}" ]; then
		MCP_PROMPTS_CHANGED=true
	fi
}

mcp_prompts_scan() {
	local py
	py="$(mcp_prompts_python)" || {
		MCP_PROMPTS_REGISTRY_JSON='{"version":1,"generatedAt":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","items":[],"hash":"","total":0}'
		MCP_PROMPTS_REGISTRY_HASH=""
		MCP_PROMPTS_TOTAL=0
		printf '%s' "${MCP_PROMPTS_REGISTRY_JSON}" >"${MCP_PROMPTS_REGISTRY_PATH}"
		return 0
	}

	local warn_file
	warn_file="$(mktemp "${MCPBASH_TMP_ROOT}/mcp-prompts-scan-warn.XXXXXX")"
	local registry_json
	if ! registry_json="$(
		ROOT="${MCPBASH_ROOT}" PROMPTS_DIR="${MCPBASH_ROOT}/prompts" "${py}" 2>"${warn_file}" <<'PY'
import os, json, hashlib, time, sys
root = os.environ['ROOT']
prompts_dir = os.environ['PROMPTS_DIR']
items = []
warnings = []
try:
    import yaml  # type: ignore
except Exception:
    yaml = None
if os.path.isdir(prompts_dir):
    for dirpath, dirnames, filenames in os.walk(prompts_dir):
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]
        rel_depth = os.path.relpath(dirpath, prompts_dir)
        if rel_depth != '.' and rel_depth.count(os.sep) >= 3:
            dirnames[:] = []
            continue
        for filename in filenames:
            if filename.startswith('.'):
                continue
            if filename.endswith('.meta.yaml'):
                continue
            path = os.path.join(dirpath, filename)
            rel = os.path.relpath(path, root)
            base = os.path.splitext(os.path.basename(path))[0]
            meta = {}
            meta_path = os.path.join(dirpath, f"{base}.meta.yaml")
            text = None
            if os.path.isfile(meta_path):
                try:
                    with open(meta_path, 'r', encoding='utf-8') as fh:
                        text = fh.read()
                except Exception as exc:
                    warnings.append(f"{os.path.relpath(meta_path, root)}: unable to read metadata ({exc})")
                    text = None
            if text:
                parsed = None
                try:
                    parsed = json.loads(text)
                except Exception:
                    parsed = None
                if parsed is None and yaml is not None:
                    try:
                        parsed = yaml.safe_load(text)
                    except Exception as exc:
                        warnings.append(f"{os.path.relpath(meta_path, root)}: YAML parse failed ({exc})")
                        parsed = None
                elif parsed is None and yaml is None:
                    warnings.append(f"{os.path.relpath(meta_path, root)}: PyYAML unavailable; metadata ignored")
                if isinstance(parsed, dict):
                    meta = parsed
                elif parsed is not None:
                    warnings.append(f"{os.path.relpath(meta_path, root)}: metadata is not an object; entry skipped")
            name = str(meta.get('name') or base)
            description = str(meta.get('description') or '')
            arguments = meta.get('arguments')
            if not isinstance(arguments, dict):
                if arguments is not None:
                    warnings.append(f"{name}: arguments metadata ignored; expected object")
                arguments = {"type": "object", "properties": {}}
            role = meta.get('role')
            if role is not None:
                role = str(role)
            metadata = meta.get('metadata')
            if metadata is not None and not isinstance(metadata, dict):
                warnings.append(f"{name}: metadata field ignored; expected object")
                metadata = None
            safe_rel = rel.replace('\\', '/')
            item = {
                "name": name,
                "description": description,
                "path": safe_rel,
                "arguments": arguments
            }
            if role:
                item["role"] = role
            if metadata is not None:
                item["metadata"] = metadata
            items.append(item)
for warning in warnings:
    print(warning, file=sys.stderr)
items.sort(key=lambda x: x["name"])
hash_source = json.dumps(items, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
hash_value = hashlib.sha256(hash_source.encode('utf-8')).hexdigest()
registry = {
    "version": 1,
    "generatedAt": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    "items": items,
    "hash": hash_value,
    "total": len(items)
}
print(json.dumps(registry, ensure_ascii=False, separators=(',', ':')))
PY
	)"; then
		local status=$?
		mcp_prompts_log_python_warnings "${warn_file}"
		return "${status}"
	fi
	mcp_prompts_log_python_warnings "${warn_file}"

	MCP_PROMPTS_REGISTRY_JSON="${registry_json}"
	MCP_PROMPTS_REGISTRY_HASH="$(
		REGISTRY_JSON="${registry_json}" "${py}" <<'PY'
import json, os
print(json.loads(os.environ.get("REGISTRY_JSON", "{}")).get('hash', ''))
PY
	)"
	# shellcheck disable=SC2034
	MCP_PROMPTS_TOTAL="$(
		REGISTRY_JSON="${registry_json}" "${py}" <<'PY'
import json, os
print(json.loads(os.environ.get("REGISTRY_JSON", "{}")).get('total', 0))
PY
	)"
	if ! mcp_prompts_enforce_registry_limits "${MCP_PROMPTS_TOTAL}" "${registry_json}"; then
		return 1
	fi

	printf '%s' "${registry_json}" >"${MCP_PROMPTS_REGISTRY_PATH}"
}

mcp_prompts_decode_cursor() {
	local cursor="$1"
	local hash="$2"
	local offset
	if ! offset="$(mcp_paginate_decode "${cursor}" "prompts" "${hash}")"; then
		return 1
	fi
	printf '%s' "${offset}"
}

mcp_prompts_list() {
	local limit="$1"
	local cursor="$2"
	# shellcheck disable=SC2034
	MCP_PROMPTS_ERR_CODE=0
	# shellcheck disable=SC2034
	MCP_PROMPTS_ERR_MESSAGE=""

	mcp_prompts_refresh_registry || {
		mcp_prompts_error -32603 "Unable to load prompts registry"
		return 1
	}

	local py
	if ! py="$(mcp_prompts_python)"; then
		mcp_prompts_error -32603 "Python interpreter required for prompts listing"
		return 1
	fi

	local numeric_limit
	if [ -z "${limit}" ]; then
		numeric_limit=50
	else
		case "${limit}" in
		'' | *[!0-9]*) numeric_limit=50 ;;
		0) numeric_limit=50 ;;
		*) numeric_limit="${limit}" ;;
		esac
	fi
	if [ "${numeric_limit}" -gt 200 ]; then
		numeric_limit=200
	fi

	local offset=0
	if [ -n "${cursor}" ]; then
		if ! offset="$(mcp_prompts_decode_cursor "${cursor}" "${MCP_PROMPTS_REGISTRY_HASH}")"; then
			mcp_prompts_error -32602 "Invalid cursor"
			return 1
		fi
	fi

	local result_json
	if ! result_json="$(
		REGISTRY="${MCP_PROMPTS_REGISTRY_JSON}" OFFSET="${offset}" LIMIT="${numeric_limit}" PYTHONIOENCODING="utf-8" "${py}" <<'PY'
import json, os, base64, sys
registry = json.loads(os.environ["REGISTRY"])
items = registry.get("items", [])
offset = int(os.environ["OFFSET"])
limit = int(os.environ["LIMIT"])
slice_items = items[offset:offset + limit]
result = {"items": slice_items, "total": len(items)}
if offset + limit < len(items):
    payload = json.dumps({"ver": 1, "collection": "prompts", "offset": offset + limit, "hash": registry.get("hash", ""), "timestamp": registry.get("generatedAt")}, separators=(',', ':'))
    encoded = base64.urlsafe_b64encode(payload.encode('utf-8')).decode('utf-8').rstrip('=')
    result["nextCursor"] = encoded
print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))
PY
	)"; then
		mcp_prompts_error -32603 "Unable to paginate prompts"
		return 1
	fi

	printf '%s' "${result_json}"
}

mcp_prompts_metadata_for_name() {
	local name="$1"
	mcp_prompts_refresh_registry || return 1
	local py
	py="$(mcp_prompts_python)" || return 1
	local metadata
	if ! metadata="$(
		REGISTRY="${MCP_PROMPTS_REGISTRY_JSON}" TARGET="${name}" "${py}" <<'PY'
import json, os, sys
registry = json.loads(os.environ["REGISTRY"])
target = os.environ["TARGET"]
for item in registry.get("items", []):
    if item.get("name") == target:
        print(json.dumps(item, ensure_ascii=False, separators=(',', ':')))
        sys.exit(0)
sys.exit(1)
PY
	)"; then
		return 1
	fi
	printf '%s' "${metadata}"
}

mcp_prompts_render() {
	local metadata="$1"
	local args_json="$2"
	local py
	py="$(mcp_prompts_python)" || return 1
	local sanitized_args
	sanitized_args="$(
		JSON_PAYLOAD="${args_json}" "${py}" <<'PY'
import json, os, sys
def quoted(value):
    if isinstance(value, str):
        return value.replace("$", "$$")
    return value

try:
    raw = json.loads(os.environ.get("JSON_PAYLOAD", "{}"))
except Exception:
    print("{}")
    sys.exit(0)

if not isinstance(raw, dict):
    raw_dict = {"value": raw}
else:
    raw_dict = raw

template_args = {str(key): quoted(value) for key, value in raw_dict.items()}
print(json.dumps({
    "arguments": raw_dict,
    "templateArgs": template_args
}, ensure_ascii=False, separators=(',', ':')))
PY
	)"
	local safe_args_json raw_args_json
	safe_args_json="$(
		INFO="${sanitized_args}" "${py}" <<'PY'
import json, os
print(json.dumps(json.loads(os.environ["INFO"]).get("templateArgs", {}), ensure_ascii=False, separators=(',', ':')))
PY
	)"
	raw_args_json="$(
		INFO="${sanitized_args}" "${py}" <<'PY'
import json, os
print(json.dumps(json.loads(os.environ["INFO"]).get("arguments", {}), ensure_ascii=False, separators=(',', ':')))
PY
	)"
	local result
	if ! result="$(
		TEMPLATE_DIR="${MCPBASH_ROOT}" METADATA="${metadata}" SAFE_ARGS="${safe_args_json}" RAW_ARGS="${raw_args_json}" "${py}" <<'PY'
import json, os
from string import Template
meta = json.loads(os.environ["METADATA"])
args = json.loads(os.environ.get("SAFE_ARGS", "{}"))
raw_args = json.loads(os.environ.get("RAW_ARGS", "{}"))
path = meta.get("path")
description = str(meta.get("description") or "")
role = str(meta.get("role") or "system")
metadata_value = meta.get("metadata")
if metadata_value is not None and not isinstance(metadata_value, dict):
    metadata_value = None
def emit(text_value):
    result = {
        "text": text_value,
        "arguments": raw_args,
        "messages": [
            {
                "role": role,
                "content": [{"type": "text", "text": text_value}]
            }
        ]
    }
    if description:
        result["description"] = description
    if metadata_value is not None:
        result["metadata"] = metadata_value
    print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))

if not path:
    emit("")
    raise SystemExit(0)
full_path = os.path.join(os.environ["TEMPLATE_DIR"], path)
try:
    with open(full_path, 'r', encoding='utf-8') as fh:
        template = Template(fh.read())
except OSError:
    emit("")
    raise SystemExit(0)
text = template.safe_substitute(args)
emit(text)
PY
	)"; then
		return 1
	fi
	printf '%s' "${result}"
}

mcp_prompts_poll() {
	if mcp_runtime_is_minimal_mode; then
		return 0
	fi
	local ttl="${MCP_PROMPTS_TTL:-5}"
	case "${ttl}" in
	'' | *[!0-9]*) ttl=5 ;;
	esac
	local now
	now="$(date +%s)"
	if [ "${MCP_PROMPTS_LAST_SCAN}" -eq 0 ] || [ $((now - MCP_PROMPTS_LAST_SCAN)) -ge "${ttl}" ]; then
		mcp_prompts_refresh_registry || true
	fi
	return 0
}

mcp_prompts_consume_notification() {
	if [ "${MCP_PROMPTS_CHANGED}" = true ]; then
		MCP_PROMPTS_CHANGED=false
		printf '{"jsonrpc":"2.0","method":"notifications/prompts/list_changed","params":{}}'
	else
		printf ''
	fi
}
