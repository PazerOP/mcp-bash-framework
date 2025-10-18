#!/usr/bin/env bash
set -euo pipefail

printf 'Running shellcheck...\n'
git ls-files '*.sh' | xargs shellcheck

printf 'Running shfmt...\n'
git ls-files '*.sh' | xargs shfmt -d

printf 'Lint completed successfully.\n'
