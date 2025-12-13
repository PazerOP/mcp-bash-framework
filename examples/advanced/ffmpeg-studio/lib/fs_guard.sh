#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# Guard helpers that confine media access to configured roots.

declare -ga MCP_FFMPEG_ROOTS=()
declare -ga MCP_FFMPEG_MODES=()
declare -g MCP_FFMPEG_GUARD_READY=0
declare -g MCP_FFMPEG_GUARD_BASE=""

mcp_ffmpeg_guard_realpath() {
	local target="$1"
	if command -v realpath >/dev/null 2>&1; then
		if realpath -m "${target}" 2>/dev/null; then
			return
		fi
		if realpath "${target}" 2>/dev/null; then
			return
		fi
	fi
	if (cd "$(dirname "${target}")" 2>/dev/null && pwd -P >/dev/null); then
		(
			cd "$(dirname "${target}")" 2>/dev/null || exit 1
			printf '%s/%s\n' "$(pwd -P)" "$(basename "${target}")"
		)
		return
	fi
	printf 'mcp_ffmpeg_guard: realpath is required\n' >&2
	return 1
}

mcp_ffmpeg_guard_path_contains() {
	local root="$1"
	local candidate="$2"
	if [[ "${candidate}" == "${root}" ]] || [[ "${candidate}" == "${root}/"* ]]; then
		return 0
	fi
	return 1
}

mcp_ffmpeg_guard_init() {
	if [[ "${MCP_FFMPEG_GUARD_READY}" == "1" ]]; then
		return 0
	fi

	local json_bin="${MCPBASH_JSON_TOOL_BIN:-}"
	if [[ -z "${json_bin}" ]] || ! command -v "${json_bin}" >/dev/null 2>&1; then
		printf 'mcp_ffmpeg_guard: JSON tool unavailable (MCPBASH_JSON_TOOL_BIN=%s)\n' "${json_bin:-unset}" >&2
		return 1
	fi

	local base="$1"
	if [[ -z "${base}" ]]; then
		base="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	fi
	MCP_FFMPEG_GUARD_BASE="${base}"

	local config="${base}/config/media_roots.json"
	if [[ ! -f "${config}" ]]; then
		printf 'mcp_ffmpeg_guard: missing config %s\n' "${config}" >&2
		return 1
	fi

	local entries_tsv=""
	local jq_script_file
	jq_script_file="$(mktemp "${TMPDIR:-/tmp}/mcp-ffmpeg-jq.XXXXXX")"
	cat <<'JQ' >"${jq_script_file}"
.roots as $roots
| if ($roots | type) != "array" or ($roots | length) == 0 then
    error("media_roots.json must define a non-empty \"roots\" array")
  else
    $roots[]
    | if (.path | type) != "string" or (.path | length) == 0 then
        error("each root entry requires a non-empty \"path\"")
      else
        "\(.path)\t\(.mode // "rw")"
      end
  end
JQ

	if ! entries_tsv="$("${json_bin}" -r -f "${jq_script_file}" "${config}")"; then
		rm -f "${jq_script_file}"
		printf 'mcp_ffmpeg_guard: invalid config in %s\n' "${config}" >&2
		return 1
	fi
	rm -f "${jq_script_file}"

	if [[ -z "${entries_tsv}" ]]; then
		printf 'mcp_ffmpeg_guard: no media roots configured\n' >&2
		return 1
	fi

	MCP_FFMPEG_ROOTS=()
	MCP_FFMPEG_MODES=()
	local seen_list=$'\n'

	while IFS=$'\t' read -r raw_path mode || [[ -n "${raw_path:-}" ]]; do
		[[ -z "${raw_path:-}" ]] && continue
		[[ -n "${mode:-}" ]] || mode="rw"
		case "${mode}" in
		rw | ro) ;;
		*)
			printf 'mcp_ffmpeg_guard: invalid mode "%s" for path %s\n' "${mode}" "${raw_path}" >&2
			return 1
			;;
		esac

		local abs_path
		if [[ "${raw_path}" == /* ]]; then
			abs_path="${raw_path}"
		else
			abs_path="${base}/${raw_path}"
		fi

		if ! abs_path="$(mcp_ffmpeg_guard_realpath "${abs_path}")"; then
			return 1
		fi

		if [[ "${abs_path}" != "/" ]]; then
			abs_path="${abs_path%/}"
		fi

		if [[ ! -d "${abs_path}" ]]; then
			printf 'mcp_ffmpeg_guard: configured root %s does not exist\n' "${abs_path}" >&2
			return 1
		fi

		case "${seen_list}" in
		*$'\n'"${abs_path}"$'\n'*)
			continue
			;;
		esac
		seen_list+="${abs_path}"$'\n'
		MCP_FFMPEG_ROOTS+=("${abs_path}")
		MCP_FFMPEG_MODES+=("${mode}")
	done <<<"${entries_tsv}"

	if [[ "${#MCP_FFMPEG_ROOTS[@]}" -eq 0 ]]; then
		printf 'mcp_ffmpeg_guard: no usable media roots found\n' >&2
		return 1
	fi

	MCP_FFMPEG_GUARD_READY=1
	return 0
}

mcp_ffmpeg_guard_root_index() {
	local candidate="$1"
	for i in "${!MCP_FFMPEG_ROOTS[@]}"; do
		if mcp_ffmpeg_guard_path_contains "${MCP_FFMPEG_ROOTS[$i]}" "${candidate}"; then
			printf '%s' "${i}"
			return 0
		fi
	done
	return 1
}

mcp_ffmpeg_guard_resolve() {
	local desired_mode="$1"
	local user_path="$2"

	if [[ -z "${user_path}" ]]; then
		printf 'mcp_ffmpeg_guard: path cannot be empty\n' >&2
		return 1
	fi

	if [[ "${MCP_FFMPEG_GUARD_READY}" != "1" ]]; then
		if ! mcp_ffmpeg_guard_init "${MCP_FFMPEG_GUARD_BASE}"; then
			return 1
		fi
	fi

	if [[ "${user_path}" == "~"* ]]; then
		user_path="${user_path/#\~/${HOME}}"
	fi

	local canonical=""
	local matched_index=-1

	# Normalize common user inputs: strip leading "./" and an initial "<root-name>/" prefix.
	if [[ "${user_path}" == ./* ]]; then
		user_path="${user_path#./}"
	fi

	if [[ "${user_path}" == /* ]]; then
		if ! canonical="$(mcp_ffmpeg_guard_realpath "${user_path}")"; then
			return 1
		fi
		if ! matched_index="$(mcp_ffmpeg_guard_root_index "${canonical}")"; then
			printf 'mcp_ffmpeg_guard: %s is not within an allowed media root\n' "${canonical}" >&2
			return 1
		fi
	else
		for i in "${!MCP_FFMPEG_ROOTS[@]}"; do
			local root="${MCP_FFMPEG_ROOTS[$i]}"
			local candidate="${user_path}"
			local root_name="${root##*/}"
			if [[ "${candidate}" == "${root_name}/"* ]]; then
				candidate="${candidate#"${root_name}"/}"
			fi
			local attempt
			if ! attempt="$(mcp_ffmpeg_guard_realpath "${root}/${candidate}")"; then
				return 1
			fi
			if mcp_ffmpeg_guard_path_contains "${root}" "${attempt}"; then
				canonical="${attempt}"
				matched_index="${i}"
				break
			fi
		done

		if [[ "${matched_index}" -lt 0 ]]; then
			printf 'mcp_ffmpeg_guard: %s is not within an allowed media root\n' "${user_path}" >&2
			return 1
		fi
	fi

	if [[ -z "${canonical}" ]]; then
		printf 'mcp_ffmpeg_guard: failed to resolve %s\n' "${user_path}" >&2
		return 1
	fi

	local root_mode="${MCP_FFMPEG_MODES[$matched_index]}"
	if [[ "${desired_mode}" == "write" && "${root_mode}" != "rw" ]]; then
		printf 'mcp_ffmpeg_guard: %s is read-only\n' "${MCP_FFMPEG_ROOTS[$matched_index]}" >&2
		return 1
	fi

	if [[ "${desired_mode}" == "write" ]]; then
		local parent
		parent="$(dirname "${canonical}")"
		if ! mcp_ffmpeg_guard_path_contains "${MCP_FFMPEG_ROOTS[$matched_index]}" "${parent}"; then
			printf 'mcp_ffmpeg_guard: parent directory escapes the allowed root\n' >&2
			return 1
		fi
		if [[ ! -d "${parent}" ]]; then
			if ! mkdir -p "${parent}"; then
				printf 'mcp_ffmpeg_guard: unable to create %s\n' "${parent}" >&2
				return 1
			fi
		fi
	fi

	printf '%s' "${canonical}"
	return 0
}

mcp_ffmpeg_guard_read_path() {
	mcp_ffmpeg_guard_resolve "read" "$1"
}

mcp_ffmpeg_guard_write_path() {
	mcp_ffmpeg_guard_resolve "write" "$1"
}
