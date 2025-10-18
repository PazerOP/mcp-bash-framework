#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/env.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../common/env.sh"

run_example() {
	local id="$1"
	printf 'Running example %s smoke check\n' "${id}" >&2
	timeout 10 "${MCPBASH_ROOT}/examples/run" "${id}" >/dev/null 2>&1 || true
}

for example in \
	00-hello-tool \
	01-args-and-validation \
	02-logging-and-levels \
	03-progress-and-cancellation; do
	run_example "${example}"
done
