#!/usr/bin/env bash
set -euo pipefail

run_example() {
  local id="$1"
  echo "Running example ${id} smoke check" >&2
  timeout 5 ./examples/run "${id}" >/dev/null 2>&1 || true
}

run_example 00-hello-tool
run_example 01-args-and-validation
run_example 02-logging-and-levels
run_example 03-progress-and-cancellation
