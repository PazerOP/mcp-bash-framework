#!/usr/bin/env bash
# Dynamic visibility evaluation for tools and resources.
# Allows tools/resources to specify a visibility script that determines
# whether they should be listed in discovery responses.

set -euo pipefail

MCP_VISIBILITY_LOGGER="${MCP_VISIBILITY_LOGGER:-mcp.visibility}"
MCP_VISIBILITY_CACHE_TTL="${MCP_VISIBILITY_CACHE_TTL:-5}"
MCP_VISIBILITY_TIMEOUT="${MCP_VISIBILITY_TIMEOUT:-2}"

# Cache for visibility results: key -> "timestamp:result"
declare -gA MCP_VISIBILITY_CACHE 2>/dev/null || true

# Evaluate a visibility script/condition for a tool or resource.
# Args:
#   $1 - visibility spec (script path, inline command, or JSON object)
#   $2 - base directory for relative script paths
#   $3 - item name (for logging)
#   $4 - item type ("tool" or "resource")
# Returns: 0 if visible, 1 if hidden, 2 on error
mcp_visibility_evaluate() {
	local visibility_spec="$1"
	local base_dir="$2"
	local item_name="${3:-unknown}"
	local item_type="${4:-tool}"

	# Empty/null visibility means always visible
	if [ -z "${visibility_spec}" ] || [ "${visibility_spec}" = "null" ]; then
		return 0
	fi

	local cache_key="${item_type}:${item_name}:${visibility_spec}"
	local now
	now="$(date +%s)"

	# Check cache
	if [ -n "${MCP_VISIBILITY_CACHE[${cache_key}]+x}" ]; then
		local cached="${MCP_VISIBILITY_CACHE[${cache_key}]}"
		local cached_time="${cached%%:*}"
		local cached_result="${cached#*:}"
		if [ $((now - cached_time)) -lt "${MCP_VISIBILITY_CACHE_TTL}" ]; then
			return "${cached_result}"
		fi
	fi

	local result=0
	local script_path=""
	local inline_command=""
	local env_var=""
	local cache_ttl="${MCP_VISIBILITY_CACHE_TTL}"

	# Parse visibility spec
	if [ "${MCPBASH_JSON_TOOL:-none}" != "none" ]; then
		local spec_type
		spec_type="$(printf '%s' "${visibility_spec}" | "${MCPBASH_JSON_TOOL_BIN}" -r 'type' 2>/dev/null || echo "string")"

		if [ "${spec_type}" = "object" ]; then
			# Object format: {"script": "./check.sh"} or {"command": "[ -n \"$VAR\" ]"} or {"env": "VAR"}
			script_path="$(printf '%s' "${visibility_spec}" | "${MCPBASH_JSON_TOOL_BIN}" -r '.script // empty' 2>/dev/null || true)"
			inline_command="$(printf '%s' "${visibility_spec}" | "${MCPBASH_JSON_TOOL_BIN}" -r '.command // empty' 2>/dev/null || true)"
			env_var="$(printf '%s' "${visibility_spec}" | "${MCPBASH_JSON_TOOL_BIN}" -r '.env // empty' 2>/dev/null || true)"
			local custom_ttl
			custom_ttl="$(printf '%s' "${visibility_spec}" | "${MCPBASH_JSON_TOOL_BIN}" -r '.cacheTtl // empty' 2>/dev/null || true)"
			if [ -n "${custom_ttl}" ]; then
				case "${custom_ttl}" in
				'' | *[!0-9]*) ;;
				*) cache_ttl="${custom_ttl}" ;;
				esac
			fi
		else
			# String format: treat as script path
			script_path="${visibility_spec//\"/}"
		fi
	else
		# No JSON tool: treat as script path
		script_path="${visibility_spec}"
	fi

	# Evaluate visibility
	if [ -n "${env_var}" ]; then
		# Environment variable check
		if [ -n "${!env_var:-}" ]; then
			result=0
		else
			result=1
		fi
	elif [ -n "${inline_command}" ]; then
		# Inline command evaluation (run in subshell for safety)
		if ( eval "${inline_command}" ) >/dev/null 2>&1; then
			result=0
		else
			result=1
		fi
	elif [ -n "${script_path}" ]; then
		# Script execution
		local full_path="${script_path}"
		if [[ "${script_path}" != /* ]]; then
			full_path="${base_dir}/${script_path}"
		fi

		if [ -f "${full_path}" ]; then
			# Security check: validate script ownership/permissions
			if ! mcp_visibility_check_script_security "${full_path}"; then
				mcp_logging_warning "${MCP_VISIBILITY_LOGGER}" "Visibility script rejected (insecure): ${full_path}"
				result=2
			else
				# Execute with timeout
				local script_runner=("${full_path}")
				if [ ! -x "${full_path}" ]; then
					# Fallback for Windows/non-executable scripts
					case "${full_path}" in
					*.sh | *.bash) script_runner=(bash "${full_path}") ;;
					*)
						local first_line=""
						IFS= read -r first_line <"${full_path}" 2>/dev/null || first_line=""
						case "${first_line}" in
						'#!'*) script_runner=(bash "${full_path}") ;;
						*) script_runner=() ;;
						esac
						;;
					esac
				fi

				if [ "${#script_runner[@]}" -gt 0 ]; then
					local env_pairs=(
						"MCPBASH_HOME=${MCPBASH_HOME}"
						"MCPBASH_PROJECT_ROOT=${MCPBASH_PROJECT_ROOT:-}"
						"MCP_ITEM_NAME=${item_name}"
						"MCP_ITEM_TYPE=${item_type}"
					)

					if command -v mcp_env_run_curated >/dev/null 2>&1; then
						if mcp_env_run_curated visibility "${env_pairs[@]}" -- "${script_runner[@]}" >/dev/null 2>&1; then
							result=0
						else
							result=1
						fi
					else
						# Fallback: direct execution with timeout
						if timeout "${MCP_VISIBILITY_TIMEOUT}" "${script_runner[@]}" >/dev/null 2>&1; then
							result=0
						else
							result=1
						fi
					fi
				else
					mcp_logging_warning "${MCP_VISIBILITY_LOGGER}" "Cannot execute visibility script: ${full_path}"
					result=2
				fi
			fi
		else
			mcp_logging_debug "${MCP_VISIBILITY_LOGGER}" "Visibility script not found: ${full_path}"
			result=1
		fi
	fi

	# Cache result
	MCP_VISIBILITY_CACHE["${cache_key}"]="${now}:${result}"

	return "${result}"
}

# Check if a visibility script meets security requirements.
# Similar to policy.sh security checks.
mcp_visibility_check_script_security() {
	local script_path="$1"

	# Basic existence check
	[ -f "${script_path}" ] || return 1

	# Never source symlinks
	[ ! -L "${script_path}" ] || return 1

	# Check permissions (reject group/world writable)
	local perm_mask=""
	if command -v stat >/dev/null 2>&1; then
		perm_mask="$(stat -c '%a' "${script_path}" 2>/dev/null || true)"
		if [ -z "${perm_mask}" ]; then
			perm_mask="$(stat -f '%Lp' "${script_path}" 2>/dev/null || true)"
		fi
	fi

	if [ -n "${perm_mask}" ]; then
		local perm_bits=$((8#${perm_mask}))
		if [ $((perm_bits & 0020)) -ne 0 ] || [ $((perm_bits & 0002)) -ne 0 ]; then
			return 1
		fi
	fi

	# Check ownership (must be owned by current user)
	local uid_gid=""
	if command -v stat >/dev/null 2>&1; then
		uid_gid="$(stat -c '%u:%g' "${script_path}" 2>/dev/null || true)"
		if [ -z "${uid_gid}" ]; then
			uid_gid="$(stat -f '%u:%g' "${script_path}" 2>/dev/null || true)"
		fi
	fi

	if [ -n "${uid_gid}" ]; then
		local cur_uid
		cur_uid="$(id -u 2>/dev/null || printf '0')"
		case "${uid_gid}" in
		"${cur_uid}:"*) return 0 ;;
		*) return 1 ;;
		esac
	fi

	# If we can't verify, allow by default (for compatibility)
	return 0
}

# Filter an array of items based on visibility.
# Args:
#   $1 - items JSON array
#   $2 - base directory for relative paths
#   $3 - item type ("tool" or "resource")
# Output: filtered JSON array
mcp_visibility_filter_items() {
	local items_json="$1"
	local base_dir="$2"
	local item_type="${3:-tool}"

	if [ "${MCPBASH_JSON_TOOL:-none}" = "none" ]; then
		printf '%s' "${items_json}"
		return 0
	fi

	# Check if any items have visibility defined
	local has_visibility
	has_visibility="$(printf '%s' "${items_json}" | "${MCPBASH_JSON_TOOL_BIN}" -r '[.[] | select(.visibility != null and .visibility != "")] | length' 2>/dev/null || echo "0")"

	if [ "${has_visibility}" = "0" ]; then
		# No visibility checks needed
		printf '%s' "${items_json}"
		return 0
	fi

	# Process each item
	local filtered_items=()
	local item_count
	item_count="$(printf '%s' "${items_json}" | "${MCPBASH_JSON_TOOL_BIN}" 'length' 2>/dev/null || echo "0")"

	local i=0
	while [ "${i}" -lt "${item_count}" ]; do
		local item
		item="$(printf '%s' "${items_json}" | "${MCPBASH_JSON_TOOL_BIN}" -c ".[$i]" 2>/dev/null)"

		local item_name visibility_spec item_path
		item_name="$(printf '%s' "${item}" | "${MCPBASH_JSON_TOOL_BIN}" -r '.name // ""' 2>/dev/null)"
		visibility_spec="$(printf '%s' "${item}" | "${MCPBASH_JSON_TOOL_BIN}" -c '.visibility // null' 2>/dev/null)"
		item_path="$(printf '%s' "${item}" | "${MCPBASH_JSON_TOOL_BIN}" -r '.path // ""' 2>/dev/null)"

		# Determine base directory for this item
		local item_base_dir="${base_dir}"
		if [ -n "${item_path}" ]; then
			local item_dir
			item_dir="$(dirname "${item_path}")"
			if [ -n "${item_dir}" ] && [ "${item_dir}" != "." ]; then
				item_base_dir="${base_dir}/${item_dir}"
			fi
		fi

		# Evaluate visibility
		local vis_result=0
		if [ "${visibility_spec}" != "null" ] && [ -n "${visibility_spec}" ]; then
			mcp_visibility_evaluate "${visibility_spec}" "${item_base_dir}" "${item_name}" "${item_type}" || vis_result=$?
		fi

		if [ "${vis_result}" -eq 0 ]; then
			# Strip visibility field from output (internal-only)
			local clean_item
			clean_item="$(printf '%s' "${item}" | "${MCPBASH_JSON_TOOL_BIN}" -c 'del(.visibility)' 2>/dev/null || printf '%s' "${item}")"
			filtered_items+=("${clean_item}")
		else
			mcp_logging_debug "${MCP_VISIBILITY_LOGGER}" "Hidden ${item_type}: ${item_name} (visibility check returned ${vis_result})"
		fi

		i=$((i + 1))
	done

	# Reconstruct JSON array
	if [ "${#filtered_items[@]}" -eq 0 ]; then
		printf '[]'
	else
		printf '[%s]' "$(
			IFS=,
			printf '%s' "${filtered_items[*]}"
		)"
	fi
}

# Clear the visibility cache (useful for testing or forcing re-evaluation)
mcp_visibility_cache_clear() {
	MCP_VISIBILITY_CACHE=()
}
