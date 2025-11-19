#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if "${SCRIPT_DIR}/test_examples.sh"; then
	printf '✅ examples/test_examples.sh\n'
else
	printf '❌ examples/test_examples.sh\n' >&2
	exit 1
fi
