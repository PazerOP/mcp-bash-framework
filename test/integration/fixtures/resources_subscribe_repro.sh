#!/usr/bin/env bash
# Spec §8 resources handler & §18.1 fixture guidance: minimal subscribe handshake reproducer.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mcp-subscribe.XXXXXX")"
cleanup() {
  if [ -n "${TMP_ROOT:-}" ] && [ -d "${TMP_ROOT}" ]; then
    rm -rf "${TMP_ROOT}"
  fi
}
trap cleanup EXIT

stage_workspace() {
  local dest="$1"
  mkdir -p "${dest}"
  cp -a "${REPO_ROOT}/bin" "${dest}/"
  cp -a "${REPO_ROOT}/lib" "${dest}/"
  cp -a "${REPO_ROOT}/handlers" "${dest}/"
  cp -a "${REPO_ROOT}/providers" "${dest}/"
  cp -a "${REPO_ROOT}/sdk" "${dest}/"
}

WORKSPACE="${TMP_ROOT}/workspace"
stage_workspace "${WORKSPACE}"
mkdir -p "${WORKSPACE}/resources"
export WORKSPACE

cat <<EOF >"${WORKSPACE}/resources/live.txt"
original
EOF

cat <<EOF >"${WORKSPACE}/resources/live.meta.yaml"
{"name": "file.live", "description": "Live file", "uri": "file://${WORKSPACE}/resources/live.txt", "mimeType": "text/plain"}
EOF

printf 'Repro workspace: %s\n' "${WORKSPACE}"
printf 'Enable payload logging via MCPBASH_DEBUG_PAYLOADS=true for stdout traces.\n'

python3 <<'PY'
import json
import os
import subprocess
import sys
import time

workspace = os.environ["WORKSPACE"]
env = os.environ.copy()
proc = subprocess.Popen(
    ["./bin/mcp-bash"],
    cwd=workspace,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)

def send(obj):
    line = json.dumps(obj, separators=(",", ":")) + "\n"
    proc.stdin.write(line)
    proc.stdin.flush()
    print(">>", line.strip())

def recv(deadline):
    while True:
        if time.time() > deadline:
            raise SystemExit("timeout waiting for server output")
        line = proc.stdout.readline()
        if not line:
            raise SystemExit("server exited unexpectedly")
        line = line.strip()
        if not line:
            continue
        print("<<", line)
        return json.loads(line)

send({"jsonrpc": "2.0", "id": "init", "method": "initialize", "params": {}})
deadline = time.time() + 5
while True:
    msg = recv(deadline)
    if msg.get("id") == "init":
        break

send({"jsonrpc": "2.0", "method": "notifications/initialized"})
send({"jsonrpc": "2.0", "id": "sub", "method": "resources/subscribe", "params": {"name": "file.live"}})
deadline = time.time() + 5
while True:
    msg = recv(deadline)
    if msg.get("id") == "sub":
        break

recv(time.time() + 5)

proc.stdin.close()
try:
    proc.wait(timeout=2)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()

if proc.returncode not in (0, None):
    sys.stderr.write(f"mcp-bash exited with {proc.returncode}\n")
    sys.stderr.write(proc.stderr.read())
PY
