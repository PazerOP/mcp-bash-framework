#!/usr/bin/env bash
# Unit: README.md render drift detection.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! bash "${REPO_ROOT}/scripts/render-readme.sh" --check; then
	printf 'README render drift detected. Run:\n'
	printf '  %s\n' "bash ${REPO_ROOT}/scripts/render-readme.sh"
	exit 1
fi

printf 'README render test passed.\n'

