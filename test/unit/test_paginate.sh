#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source ./lib/paginate.sh
cursor=$(mcp_paginate_encode tools 10 hash 2025-01-01T00:00:00Z)
offset=$(mcp_paginate_decode "${cursor}" tools hash)
if [ "${offset}" != "10" ]; then
	echo "Unexpected offset ${offset}" >&2
	exit 1
fi
