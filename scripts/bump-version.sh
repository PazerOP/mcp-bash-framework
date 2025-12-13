#!/usr/bin/env bash
# Bump VERSION and re-render README.md from template.
#
# Usage:
#   scripts/bump-version.sh 0.7.1
#   scripts/bump-version.sh v0.7.1
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ $# -ne 1 ] || [ -z "${1:-}" ]; then
	printf 'Usage: %s <version>\n' "$0" >&2
	exit 2
fi

raw="$1"
case "${raw}" in
v*.*.*)
	version="${raw#v}"
	;;
*)
	version="${raw}"
	;;
esac

if [ -z "${version}" ]; then
	printf 'bump-version: empty version\n' >&2
	exit 2
fi

printf '%s\n' "${version}" >"${REPO_ROOT}/VERSION"
bash "${REPO_ROOT}/scripts/render-readme.sh" --version "${version}"

printf 'Bumped VERSION to %s and rendered README.md\n' "${version}"
