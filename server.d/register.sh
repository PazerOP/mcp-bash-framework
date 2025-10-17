#!/usr/bin/env bash
# Manual registration script; invoked when executable (Spec §9 manual overrides).

set -euo pipefail

# Implementers should emit JSON arrays for tools/resources/prompts via stdout
# e.g. echo '{"tools": [...], "resources": [...], "prompts": [...]}'.
# Current placeholder returns nothing, allowing auto-discovery to run.
exit 0
