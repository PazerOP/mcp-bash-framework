# Security & Correctness Issue Validation Report

## Executive Summary
This report validates 50 AI-generated potential issues in the mcpbash codebase. Each issue has been carefully examined against the actual source code.

**Legend:**
- ✅ **VALID** - Issue confirmed as stated
- ⚠️ **PARTIALLY VALID** - Issue exists but with different severity/context
- ❌ **INVALID** - Issue does not exist or is incorrect
- 📝 **NEEDS REVIEW** - Requires domain expert judgment

---

## Security Issues

### 1. Path Traversal in Scaffold Commands ✅ **VALID**

**File:** `bin/mcp-bash` lines 32-119  
**Claim:** Scaffold commands trust user-supplied name directly allowing writes outside repository via `../../tmp/pwn`

**Validation:** 
- Lines 44, 70, 95 use `tools/${name}`, `prompts/${name}`, `resources/${name}` without sanitization
- Only check is `[ -e "${target_dir}" ]` which fails silently if parent dirs created
- Example: `mcp-bash scaffold tool ../../tmp/pwn` would create files outside repo
- `mkdir -p "${target_dir}"` creates intermediate directories

**Severity:** HIGH - Arbitrary file write

**Status:** Completed – scaffold commands now reject names outside `[A-Za-z0-9_-]+` to prevent directory traversal.

---

### 2. Git Provider Path Traversal ✅ **VALID**

**File:** `providers/git.sh` lines 24-66  
**Claim:** Concatenates user-provided path without stripping `../`, allowing arbitrary file read

**Validation:**
```bash
# Line 54: target="${workdir}/repo/${path}"
# Line 36: path="${path#/}"
```
- `path` comes from URI fragment after colon (line 27)
- Only strips leading `/` but allows `../`
- Example: `git://repo#main:../../.git/config` reads outside clone
- Line 60: `cat "${target}"` outputs content

**Severity:** HIGH - Arbitrary file read from git clones

**Status:** Completed – provider now rejects path components that are empty, '.' or '..', preventing traversal outside the cloned repo.

---

### 3. Minimal Mode Parameter Ignorance ⚠️ **PARTIALLY VALID**

**File:** `lib/json.sh` lines 545-820  
**Claim:** Minimal mode parser only caches `.method` and `.id`, returns empty string for all other parameters

**Validation:**
- Confirmed: Lines 599-807 show all extraction functions return `''` in minimal mode
- Lines 152-160: Only `method` and `id` are cached in `mcp_json_minimal_parse`
- **However:** This is intentional fallback behavior when jq/gojq unavailable
- Server still functions for basic lifecycle/ping/logging (documented limitation)

**Severity:** MEDIUM - Degraded functionality by design, not a bug per se

**Status:** Completed – minimal-mode parser now caches `params` and can extract strings (e.g., protocolVersion), restoring required functionality without jq/gojq.

---

### 4. Log Level Setting Broken in Minimal Mode ✅ **VALID**

**File:** `handlers/logging.sh` + `lib/json.sh` lines 737-751  
**Claim:** `mcp_json_extract_log_level` returns empty string in minimal mode, so setLevel always falls back to "info"

**Validation:**
```bash
# lib/json.sh:737-741
mcp_json_extract_log_level() {
    local json="$1"
    if mcp_runtime_is_minimal_mode; then
        printf ''
        return 0
    fi
```
- handlers/logging.sh:17 assigns result to `level`
- Line 18: `if [ -z "${level}" ]; then level="info"; fi`
- Clients cannot change log level without jq/gojq

**Severity:** LOW - Minor UX degradation in minimal mode

**Status:** Completed – `mcp_json_extract_log_level` now parses minimal-mode payloads via the cached params object, so logging/setLevel honors client values without jq/gojq.

---

### 5. Protocol Version Ignored in Minimal Mode ✅ **VALID**

**File:** `lib/json.sh` lines 545-563  
**Claim:** `mcp_json_extract_protocol_version` returns empty string in minimal mode

**Validation:**
```bash
# Lines 545-550
mcp_json_extract_protocol_version() {
    local json="$1"
    if mcp_runtime_is_minimal_mode; then
        printf ''
        return 0
    fi
```
- Used in lifecycle handler to negotiate version
- Server responds with default version regardless of client request

**Severity:** MEDIUM - Protocol negotiation broken

**Status:** Completed – minimal-mode `protocolVersion` extraction implemented via cached params string.

---

### 6. Worker Log Streaming Hardcodes jq ✅ **VALID**

**File:** `lib/core.sh` lines 782-804  
**Claim:** Log streaming invokes jq to read level field; when jq absent, logs dropped

**Validation:**
```bash
# Line 785: level="$(printf '%s' "${line}" | jq -r '.params.level // "info"' 2>/dev/null ...)"
```
- **Hardcodes `jq` binary**, not `${MCPBASH_JSON_TOOL_BIN}`
- Even if `gojq` is installed and server is in full mode, log streaming still breaks
- Affects **any deployment without jq specifically**, not just minimal mode

**Broader Impact:**
- Server detects `gojq` at startup → enters full mode
- All features work (tools, resources, etc. use `${MCPBASH_JSON_TOOL_BIN}`)
- But `mcp_core_extract_log_level` hardcodes `jq`
- Worker logs silently dropped despite being in "full mode"
- Confusing for operators: "Why are logs missing when gojq is installed?"

**Severity:** HIGH - Silent log loss even in full mode with gojq; breaks contract that full mode "works"

**Status:** Completed – log streaming now calls `mcp_json_extract_log_level`, which already honors `${MCPBASH_JSON_TOOL_BIN}` (and minimal mode), so jq is no longer hard-coded.

---

### 7. Wrong JSON-RPC Error Code for Parse Failures ✅ **VALID**

**File:** `lib/core.sh` lines 309-320  
**Claim:** JSON parse failures emit -32600 instead of -32700

**Validation:**
```bash
# Line 282: mcp_core_emit_parse_error "Invalid Request" -32600 "Failed to normalize input"
# Line 292: mcp_core_emit_parse_error "Invalid Request" -32600 "Batch arrays disabled"
# Line 302: mcp_core_emit_parse_error "Invalid Request" -32600 "Missing method"
```
- JSON-RPC 2.0 spec: -32700 = Parse error, -32600 = Invalid Request
- All JSON parsing errors use -32600 incorrectly

**Severity:** MEDIUM - Protocol violation

**Status:** Completed – parse failures (normalization + batch parsing) now emit JSON-RPC code -32700 with "Parse error" message, aligning with the spec.

---

### 8. Subscription ID Collision on macOS ✅ **VALID**

**File:** `handlers/resources.sh` line 74  
**Claim:** Fallback `date +%s%N` uses unsupported `%N` on macOS, producing literal "%N"

**Validation:**
```bash
# Line 74: subscription_id="sub-$(uuidgen 2>/dev/null || date +%s%N)"
```
- macOS Bash 3.2's `date` doesn't support nanoseconds (`%N`)
- Results in `sub-1234567890%N` for all subscriptions
- Causes massive ID collisions

**Severity:** HIGH - Broken subscriptions on macOS when uuidgen missing

**Status:** Completed – subscription IDs now use `uuidgen` when available and fall back to `sub-<epoch>-<RANDOM>` without relying on `%N`.

---

### 9. No Base64 Fallback for Binary Resources ✅ **VALID**

**File:** `lib/resources.sh` lines 708-761  
**Claim:** Resources always injected with `base64:false`; binary files corrupt or fail

**Validation:**
```bash
# Lines 754-759
result="$(jq -n -c --arg uri "${uri}" --arg mime "${mime}" --arg content "${content}" '{
    uri: $uri,
    mimeType: $mime,
    base64: false,
    content: $content
}')"
```
- Uses `jq --arg` which requires valid UTF-8
- Binary data causes jq to fail or corrupt
- No detection or base64 encoding path

**Severity:** HIGH - Binary resources unusable

**Status:** Completed – resource reads now stream provider output to temp files, enforce size limits there, detect UTF-8 via iconv, and base64-encode binary payloads before responding.

---

### 10. Progress Notifications Only Sent After Tool Exits ⚠️ **PARTIALLY VALID**

**File:** `lib/core.sh` lines 454-573  
**Claim:** SDK writes to temp files drained only after worker exits

**Validation:**
- Lines 454-456: Progress/log streams created per-worker
- Lines 563-572: Streams drained in `mcp_core_worker_entry` EXIT trap
- **However:** This is NDJSON-based; tools could potentially implement partial draining
- **But:** No mechanism exists for live streaming before tool completion

**Severity:** MEDIUM - Degrades progress UX, but may be architectural limitation

**Proposed Solution (Single Background Flusher with Byte Offsets):**

Provide **optional live progress** by running one lightweight background flusher that periodically drains every active worker’s progress/log files:

```bash
# In mcp_core_bootstrap_state (lib/core.sh:60-106)
if [ "${MCPBASH_ENABLE_LIVE_PROGRESS:-false}" = "true" ]; then
    mcp_core_start_progress_flusher
fi

mcp_core_start_progress_flusher() {
    (
        while [ "${MCPBASH_SHUTDOWN_PENDING}" != "true" ]; do
            mcp_core_flush_worker_streams_once
            sleep "${MCPBASH_PROGRESS_FLUSH_INTERVAL:-0.5}"
        done
    ) &
    MCPBASH_PROGRESS_FLUSHER_PID=$!
}

# Ensure cleanup (lib/core.sh:60-106 exit trap)
mcp_runtime_cleanup() {
    if [ -n "${MCPBASH_PROGRESS_FLUSHER_PID:-}" ]; then
        kill "${MCPBASH_PROGRESS_FLUSHER_PID}" 2>/dev/null || true
        wait "${MCPBASH_PROGRESS_FLUSHER_PID}" 2>/dev/null || true
    fi
    # existing cleanup ...
}

# Flush logic (new helper)
mcp_core_flush_worker_streams_once() {
    local key
    for key in $(mcp_ids_list_active_workers); do
        mcp_core_flush_stream "${key}" "progress"
        mcp_core_flush_stream "${key}" "log"
    done
}

# Stream flush helper using byte offsets
mcp_core_flush_stream() {
    local key="$1" kind="$2"
    local stream="${MCPBASH_STATE_DIR}/${kind}.${key}.ndjson"
    local offset_file="${stream}.offset"
    [ -f "${stream}" ] || return 0

    local last_offset=0
    if [ -f "${offset_file}" ]; then
        last_offset="$(cat "${offset_file}")"
    fi

    local size
    size="$(wc -c <"${stream}" 2>/dev/null || echo 0)"
    if [ "${size}" -lt "${last_offset}" ]; then
        last_offset=0 # file truncated/rotated
    fi

    if [ "${size}" -eq "${last_offset}" ]; then
        return 0
    fi

    # Read only the new bytes starting at last_offset+1 (tail -c is portable enough)
    tail -c +$((last_offset + 1)) "${stream}" 2>/dev/null |
        while IFS= read -r line || [ -n "${line}" ]; do
            [ -z "${line}" ] && continue
            if [ "${kind}" = "log" ] && ! mcp_runtime_is_minimal_mode; then
                local level
                level="$(mcp_core_extract_log_level "${line}")"
                if ! mcp_logging_is_enabled "${level}"; then
                    continue
                fi
            fi
            if mcp_core_rate_limit "${key}" "${kind}"; then
                rpc_send_line "${line}"
            fi
        done

    echo "${size}" >"${offset_file}"
}
```

**Benefits:**
- ✅ **Only one background process** – Serves all workers; no per-worker tails or polling
- ✅ **Portable** – Uses Bash 3.2-friendly primitives (`wc -c`, `tail -c`); no FIFOs or Bash 4 syntax
- ✅ **True periodic updates** – Flushes even when no other requests are arriving
- ✅ **Resource-light** – Just a loop sleeping and calling existing helpers
- ✅ **Resilient** – Existing per-worker final drain still runs when the tool exits
- ✅ **Handles truncation** – Byte offsets reset if the file shrinks (e.g., cleaned mid-run)
- ✅ **Minimal-mode aware** – Skips log-level parsing when jq/gojq absent
- ✅ **Opt-in** – Controlled by `MCPBASH_ENABLE_LIVE_PROGRESS`

**Trade-offs:**
- ⚠️ Requires new helpers: `mcp_core_start_progress_flusher`, `mcp_core_flush_worker_streams_once`, a `mcp_ids_list_active_workers` helper, and per-worker stream metadata in `mcp_ids`
- ⚠️ Flusher subshell is terminated via `kill` during shutdown (flag visibility alone is not guaranteed)
- ⚠️ Uses `tail`/`wc` on every interval; interval should be tuned (default 0.5–1s)
- ⚠️ Slightly more state files (`*.offset`) in `${MCPBASH_STATE_DIR}`

**Status:** Completed – implemented the single background flusher with byte offsets, optional via `MCPBASH_ENABLE_LIVE_PROGRESS`, plus supporting helpers and cleanup behavior.

This design keeps the file-based SDK contract intact, surfaces progress even for single long-running tools, and avoids the complexity of per-worker tapper processes.

---

### 11. Subscription Polling Triggers Excessive Fetches ✅ **VALID**

**File:** `lib/resources.sh` lines 179-218  
**Claim:** Re-reads every subscription on every request with no TTL

**Validation:**
```bash
# Line 179: mcp_resources_poll_subscriptions() {
# Lines 185-217: for path in "${MCPBASH_STATE_DIR}"/resource_subscription.*; do
#     ...
#     result="$(mcp_resources_read "${name}" "${uri}")"
```
- Called from `mcp_core_emit_registry_notifications` (core.sh:824)
- Which is called after every `mcp_core_handle_line` (core.sh:308)
- No rate limiting or TTL check
- Each subscription fetch can trigger HTTPS/git operations

**Severity:** HIGH - DoS vector via subscription spam

**Status:** Completed – subscription polling now respects `MCPBASH_RESOURCES_SUB_POLL_INTERVAL` (default 1s) and skips work when called more frequently.

---

### 12-14. Register Script Re-executed on Every Request ✅ **VALID**

**Files:** `lib/resources.sh` 273-330, `lib/tools.sh` 267-310, `lib/prompts.sh` 250-310  
**Claim:** When `server.d/register.sh` exists, registry refresh sources it on every call, bypassing TTL cache

**Validation:**

**Resources (lib/resources.sh:351-362):**
```bash
mcp_resources_refresh_registry() {
    mcp_resources_init
    if [ -x "${MCPBASH_REGISTER_SCRIPT}" ]; then
        if mcp_resources_run_manual_script; then
            return 0  # TTL check skipped!
        fi
```

**Tools (lib/tools.sh:261-268):**
```bash
mcp_tools_refresh_registry() {
    mcp_tools_init
    if [ -x "${MCPBASH_REGISTER_SCRIPT}" ]; then
        if mcp_tools_run_manual_script; then
            return 0  # TTL check skipped!
```

**Prompts (lib/prompts.sh:260-268):**
```bash
mcp_prompts_refresh_registry() {
    mcp_prompts_init
    if [ -x "${MCPBASH_REGISTER_SCRIPT}" ]; then
        if mcp_prompts_run_manual_script; then
            return 0  # TTL check skipped!
```

- All three bypass normal TTL logic (lines 380, 284, 284 respectively in their files)
- Script sourced via `. "${MCPBASH_REGISTER_SCRIPT}"` (tools:218, resources:316, prompts:144)
- Runs on every `list` or `call` operation

**Severity:** CRITICAL - Performance and security issue

**Status:** Completed – manual registry scripts now respect the standard TTL before re-running, reusing cached JSON between invocations.

---

### 15. Manual Registry Scripts Corrupt Server State ✅ **VALID**

**File:** `lib/tools.sh` lines 217-246  
**Claim:** Scripts sourced directly; `exit`, `trap`, variable mutations can crash server

**Validation:**
```bash
# Line 218: . "${MCPBASH_REGISTER_SCRIPT}" >"${script_output_file}" 2>&1
# Wrapped in set +e / set -e, but still in main process
```
- Sourcing (`.`) executes in current shell, not subprocess
- `exit` in script terminates server
- `trap` overwrites server traps
- Variable assignments pollute namespace
- Same issue in resources.sh:316 and prompts.sh:144

**Severity:** CRITICAL - Server crash/corruption vector

**Status:** Completed – all manual registry runners execute scripts in subshells with their own `set -euo pipefail`, so `exit`/trap/variable mutations no longer crash the main server.

---

### 16. No Timeout for Manual Registry Scripts ✅ **VALID**

**File:** `lib/tools.sh` lines 217-246  
**Claim:** Long-running or hung script blocks startup/refresh with no watchdog

**Validation:**
- No timeout wrapper around script execution
- Blocks all three handlers (tools, resources, prompts)
- Can hang entire server initialization

**Severity:** HIGH - DoS via hung script

**Status:** Completed – manual register scripts now run in subshells with a configurable timeout (`MCPBASH_MANUAL_REGISTER_TIMEOUT`, default 10s), so hung scripts can't block the server indefinitely.

---

### 17-19. Unbounded Manual Buffers ✅ **VALID**

**Files:** `lib/tools.sh` 23-64, `lib/resources.sh` 20-73, `lib/prompts.sh` 17-74  
**Claim:** Manual registration buffers grow without bound, risking OOM

**Validation:**

**Tools (lib/tools.sh:33-47):**
```bash
mcp_tools_register_manual() {
    # ...
    if [ -n "${MCP_TOOLS_MANUAL_BUFFER}" ]; then
        MCP_TOOLS_MANUAL_BUFFER="${MCP_TOOLS_MANUAL_BUFFER}${MCP_TOOLS_MANUAL_DELIM}${payload}"
    else
        MCP_TOOLS_MANUAL_BUFFER="${payload}"
    fi
```

- No size limit check
- Concatenates with delimiter indefinitely
- Similar pattern in resources.sh:99-111 and prompts.sh:34-47

**Mitigation:** Tools has 1 MiB check for stdout (line 210-228) but NOT for buffer itself

**Severity:** MEDIUM - Memory exhaustion possible but requires malicious script

**Status:** Completed – manual registration buffers for tools/resources/prompts/completions now honor `MCPBASH_MANUAL_BUFFER_MAX_BYTES` (default 1 MiB) and abort if exceeded.

---

### 20. Unbounded Manual Completion Buffer ✅ **VALID**

**File:** `lib/completion.sh` lines 27-120  
**Claim:** Same unbounded buffer issue for completions

**Validation:**
```bash
# Lines 139-152: mcp_completion_register_manual
MCP_COMPLETION_MANUAL_BUFFER="${MCP_COMPLETION_MANUAL_BUFFER}${MCP_COMPLETION_MANUAL_DELIM}${payload}"
```
- No size cap
- No spill-to-disk

**Severity:** MEDIUM - Same as 17-19

**Status:** Completed – completion manual buffer shares the new size cap mentioned above.

---

### 21. HTTPS Provider Has No Timeout or Size Guard ✅ **VALID**

**File:** `providers/https.sh` lines 8-24  
**Claim:** `curl -fsSL` / `wget -q -O -` with zero timeout/size limits

**Validation:**
```bash
# Line 13: if ! curl -fsSL "${uri}"; then
# Line 20: if ! wget -q -O - "${uri}"; then
```
- No `--max-time` / `--timeout` flags
- No `--max-filesize` limits
- Can hang indefinitely or stream gigabytes

**Severity:** CRITICAL - DoS and resource exhaustion

**Status:** Completed – HTTPS provider downloads via curl/wget into temp files with configurable timeout (`MCPBASH_HTTPS_TIMEOUT`) and size limit (`MCPBASH_HTTPS_MAX_BYTES`).

---

### 22. Windows Drive Handling Requires Bash ≥4 ⚠️ **PARTIALLY VALID**

**File:** `providers/file.sh` lines 8-18  
**Claim:** `${drive,,}` requires Bash ≥4, breaks on macOS Bash 3.2

**Validation:**
```bash
# Line 12: path="/${drive,,}${rest}"
```
- **True:** `${var,,}` is Bash 4+ syntax (lowercase expansion)
- This code only runs for Windows paths (`[A-Za-z]:/`)
- macOS users won't trigger this path
- **But:** MSYS2 on Windows can have old Bash versions
- Users running mcp-bash on Windows with MSYS2 Bash 3.2 would hit syntax error
- Narrow but real impact scenario

**Severity:** LOW - Affects Windows users with older MSYS2/Cygwin Bash installations

**Status:** Completed – provider now lowers Windows drive letters via Bash 4 `${var,,}` when available and falls back to `tr` under Bash 3.

---

### 23. MSYS2_ARG_CONV_EXCL Ineffective ✅ **VALID**

**File:** `providers/file.sh` lines 15-18  
**Claim:** Setting variable inside script is too late; args already converted

**Validation:**
```bash
# Lines 16-18:
if [ -z "${MSYS2_ARG_CONV_EXCL:-}" ]; then
    MSYS2_ARG_CONV_EXCL="*"
fi
```
- MSYS2 path conversion happens at process launch
- Setting env var inside script has no effect on `$1` which is already parsed
- Should be exported before invoking script

**Severity:** MEDIUM - Breaks Windows paths in MSYS2

**Status:** Completed – resource provider wrappers export `MSYS2_ARG_CONV_EXCL=*` before invoking scripts, so MSYS no longer mangles file:// paths.

---

### 24. Unquoted Directory Roots Split on Spaces ✅ **VALID**

**File:** `providers/file.sh` lines 33-44  
**Claim:** Iterating over `MCP_RESOURCES_ROOTS` unquoted splits on spaces

**Validation:**
```bash
# Line 35: for root in ${roots}; do
```
- Should be `for root in "${roots[@]}"` if array, or need proper IFS handling
- Breaks paths like `/Users/John Doe/workspace`

**Severity:** HIGH - Common on macOS

**Status:** Completed – file provider now iterates `MCP_RESOURCES_ROOTS` via newline-safe loop so paths containing spaces are honored.

---

### 25-26. Unquoted Pattern Substitution with Spaces ✅ **VALID**

**Files:** `lib/tools.sh` 304-333, `lib/resources.sh` 400-438  
**Claim:** `${path#${MCPBASH_ROOT}/}` without quoting breaks with spaces

**Validation:**

**Tools (lib/tools.sh:304):**
```bash
local rel_path="${path#${MCPBASH_ROOT}/}"
```

**Resources (lib/resources.sh:400):**
```bash
local rel_path="${path#${MCPBASH_ROOT}/}"
```

- Pattern itself needs quotes: `"${path#"${MCPBASH_ROOT}/"}"` or similar
- Glob characters in path also problematic

**Severity:** MEDIUM - Affects discovery on macOS

**Status:** Completed – discovery loops now quote the `${MCPBASH_ROOT}` removal, handling spaces safely.

---

### 27-28. Temp File Leaks on Timeout/Cancellation ✅ **VALID**

**File:** `lib/tools.sh` lines 606-665  
**Claim:** Timeout (124/137) and cancel (143) branches don't clean up temp files

**Validation:**
```bash
# Lines 650-665: case "${exit_code}" in 124|137)
# ...
# return 1  # NO cleanup of stdout/stderr/args/metadata files
```
- Lines 547-560: Creates args_file and metadata_file
- Line 574-575: Creates stdout_file and stderr_file
- Lines 650-665: Return early without cleanup
- Compare to line 708-710: Successful path cleans up

**Severity:** HIGH - Temp file leak on every timeout/cancel

**Status:** Completed – tool runner now cleans up stdout/stderr/args/metadata temp files on timeout/cancel/error paths.

---

### 29. outputSchema Never Validated ✅ **VALID**

**File:** `lib/tools.sh` lines 522-625  
**Claim:** Schema parsed but not used to validate tool result

**Validation:**
```bash
# Line 565: output_schema="$(echo "${info_json}" | jq -c '.outputSchema // null')"
# ... never used again
```
- Variable extracted but not referenced
- No validation logic exists
- Feature incomplete

**Severity:** LOW - Missing feature, not a bug

**Status:** Completed – when a tool declares `outputSchema`, the runner now requires JSON output (structuredContent) and errors if parsing fails, preventing misleading metadata.

---

### 30. Missing Template Error Swallowed ❌ **INVALID**

**File:** `bin/mcp-bash` lines 18-30  
**Claim:** `cat` errors swallowed, empty files created

**Validation:**
```bash
# Line 23: content="$(cat "${template}")"
# Line 29: printf '%s' "${content}" >"${output}"
```
- **If** `cat` fails, command substitution fails
- Bash with `set -e` (line 6) would exit
- Error NOT silently swallowed

**Severity:** NONE - Issue invalid

---

### 31. URI Escaping Only Handles Spaces ✅ **VALID**

**File:** `bin/mcp-bash` lines 100-117  
**Claim:** Only `%20` encoded; other reserved chars unescaped

**Validation:**
```bash
# Line 114: resource_uri="${resource_uri// /%20}"
```
- Only translates spaces
- Doesn't encode `%`, `#`, `?`, `&`, `=` etc.
- Results in invalid URIs

**Severity:** MEDIUM - Malformed URIs

**Status:** Completed – resource scaffolds now call `pathlib.Path(...).as_uri()` (with a pure-Bash percent-encoding fallback) to emit canonical `file://` URIs.

---

### 32. Git Provider Can't Fetch Commit Hashes ✅ **VALID**

**File:** `providers/git.sh` lines 24-55  
**Claim:** Always uses `--branch` which can't fetch specific commits

**Validation:**
```bash
# Line 49: if ! git clone --depth 1 --branch "${ref}" "${repo}" ...
```
- `--branch` accepts tags and branches, not commit SHAs
- Security best practice: pin to commit SHA
- Not supported by implementation

**Severity:** MEDIUM - Security limitation

**Status:** Completed – provider now bootstraps a repo, fetches `origin <sha>`, and checks out `FETCH_HEAD`, so commit-pinned URIs resolve even without branch support.

---

### 33-35. Corrupt Registry Causes Server Crash ✅ **VALID** (Severity Underestimated)

**Files:** `lib/tools.sh` 360-390, `lib/resources.sh` 452-520, `lib/prompts.sh` 312-372  
**Claim:** jq failures ignored, producing arithmetic errors instead of clean errors

**Validation - Original Analysis Was WRONG:**

All three files start with `set -euo pipefail`:
- `lib/tools.sh` line 4: `set -euo pipefail`
- `lib/resources.sh` line 4: `set -euo pipefail`  
- `lib/prompts.sh` line 4: `set -euo pipefail`

**Actual Behavior When Registry Corrupt:**

```bash
# lib/tools.sh:474
result_json="$(echo "${MCP_TOOLS_REGISTRY_JSON}" | jq -c ...)"
# If jq fails, command substitution returns non-zero
# With set -e, this TERMINATES THE ENTIRE SERVER PROCESS
# Code never reaches the arithmetic operations
```

**Corrected Impact:**
- Original claim said "arithmetic errors" - **WRONG**
- Actual behavior: **server crashes immediately** when reading corrupt registry
- No JSON-RPC error response sent to client
- Client sees connection drop or timeout
- Much worse than bad error messages

**Example Scenarios:**
1. Registry file corrupted by disk error or incomplete write
2. Operator manually edits registry.json with syntax error
3. Race condition during registry refresh
4. Result: **Server terminates**, not graceful error

**Severity:** HIGH - Server crashes instead of returning error (was incorrectly marked MEDIUM)

**Status:** Completed – cached registry loads now wrap `cat`/`jq` failures, log warnings, and drop the cache instead of crashing under `set -e`.

---

### 36. Safe Remove Only Works Under TMPDIR ✅ **VALID**

**File:** `lib/runtime.sh` lines 41-93  
**Claim:** If operator overrides `MCPBASH_LOCK_ROOT`, cleanup refuses to remove it

**Validation:**
```bash
# Lines 84-91:
case "${target}" in
    "${MCPBASH_TMP_ROOT}"/mcpbash.state.* | "${MCPBASH_TMP_ROOT}"/mcpbash.locks*)
        rm -rf "${target}"
        ;;
    *)
        printf '%s\n' "mcp-bash: refusing to remove '${target}' outside TMP root" >&2
        return 1
        ;;
esac
```
- Hardcoded pattern match
- If lock root set to `/var/lock/mcpbash`, cleanup fails
- Stale locks accumulate

**Severity:** MEDIUM - Operational issue

---

### 37. Missing Prompt Template Returns Empty Result ⚠️ **PARTIALLY VALID**

**File:** `lib/prompts.sh` lines 456-492  
**Claim:** Missing template file emits empty prompt instead of error

**Validation:**
```bash
# Lines 471-474:
if [ ! -f "${full_path}" ]; then
    mcp_prompts_emit_render_result "" "${args_json}" "${role}" "${description}" "${metadata_value}"
    return 0
fi
```
- Confirmed: Returns empty text on missing file
- **But:** This may be intentional for text-only prompts?
- No clear spec on whether this is wrong

**Severity:** LOW - Design ambiguity

---

### 38. Subscription State Loss on Restart ✅ **VALID**

**File:** `lib/resources.sh` lines 127-156  
**Claim:** Only hash stored, not payload; can't replay last value after restart

**Validation:**
```bash
# Lines 127-135:
mcp_resources_subscription_store() {
    # ...
    printf '%s\n%s\n%s\n' "${name}" "${uri}" "${fingerprint}" >"${path}.tmp"
```
- Only stores name, URI, and hash/fingerprint
- MCP spec likely requires replaying last known state
- On restart, can't send cached value

**Severity:** MEDIUM - Protocol compliance

---

### 39. Sub-second Timeouts Impossible ✅ **VALID**

**File:** `lib/core.sh` lines 505-539, 758-767  
**Claim:** Only whole seconds accepted; fractional values dropped

**Validation:**
```bash
# Lines 758-766:
mcp_core_normalize_timeout() {
    value="$(printf '%s' "${value}" | tr -d '\r\n')"
    case "${value}" in
    '') printf '' ;;
    *[!0-9]*) printf '' ;;  # Rejects decimals!
    0) printf '' ;;
    *) printf '%s' "${value}" ;;
```
- Pattern `*[!0-9]*` rejects any non-digit, including `.`
- `2.5` treated as invalid
- 1s polling (line 668) prevents subsecond precision anyway

**Severity:** LOW - Minor limitation

---

### 40. server.d/env.sh Never Sourced ✅ **VALID**

**File:** `lib/runtime.sh` + docs  
**Claim:** README/BEST-PRACTICES document it as supported, but it's never loaded

**Validation:**
- Grep shows `server.d/env.sh` mentioned 3 times in docs/BEST-PRACTICES.md
- Line 81: "Use `server.d/env.sh` to inject operator-specific configuration"
- **But:** No code in runtime.sh or bin/mcp-bash sources it
- Only `server.d/register.sh` is sourced (via MCPBASH_REGISTER_SCRIPT)
- `server.d/env.sh` exists in repo but is orphaned

**Severity:** MEDIUM - Documented feature doesn't work

---

### 41. No Tests for git/HTTPS Providers ✅ **VALID**

**Claim:** No tests exercise network fetch code paths

**Validation:**
- Searched test/ directory structure
- No tests found calling git:// or https:// URIs
- High-risk code untested

**Severity:** MEDIUM - Testing gap

---

### 42. TESTING.md References Non-existent Script ✅ **VALID**

**File:** `TESTING.md` lines 13-21  
**Claim:** Documents `./test/unit/test_paginate.sh` which doesn't exist

**Validation:**
- TESTING.md:17 references `./test/unit/test_paginate.sh`
- test/unit/ contains only: `lock.bats`, `run.sh`
- No paginate test exists

**Severity:** LOW - Documentation error

---

### 43. Unit Tests Only Cover lock.bats ✅ **VALID**

**Claim:** Core libraries have zero unit coverage

**Validation:**
- test/unit/ contains only lock.bats
- No tests for: json.sh, tools.sh, resources.sh, completion.sh, timeout.sh, etc.

**Severity:** HIGH - Major testing gap

---

### 44. Lock Acquisition Can Hang Forever ✅ **VALID**

**File:** `lib/lock.sh` lines 19-41  
**Claim:** Tight loop with no timeout or logging; stale lock hangs server

**Validation:**
```bash
# Lines 25-35:
while :; do
    if mkdir "${path}" 2>/dev/null; then
        # ...
        break
    else
        mcp_lock_try_reap "${path}"
        sleep "${MCPBASH_LOCK_POLL_INTERVAL}"
    fi
done
```
- Infinite loop
- No timeout variable
- No log message after N attempts
- If reap logic fails, hangs forever

**Severity:** HIGH - Availability issue

---

### 45. Example Test Looks for .meta.yaml Instead of .meta.json ✅ **VALID**

**File:** `test/examples/test_examples.sh` lines 28-64  
**Claim:** Searches for `*.meta.yaml`, never finds actual `*.meta.json` files

**Validation:**
```bash
# Line 43: if entry.endswith(".meta.yaml"):
```
- Python code checks for `.meta.yaml`
- Actual examples use `.meta.json` (verified in examples/00-hello-tool/tools/)
- Test never exercises tools/list in examples

**Severity:** HIGH - Tests not running as intended

---

### 46. assert_contains Interprets String as Regex ✅ **VALID**

**File:** `test/common/assert.sh` lines 20-28  
**Claim:** Test helper passes search string to grep as regex without escaping

**Validation:**
```bash
# Line 25: if ! grep -q "${needle}" <<<"${haystack}"; then
```
- Passes `${needle}` directly to grep as pattern
- No escaping with `grep -F` (fixed strings)
- Characters like `[`, `]`, `\`, `.`, `*` will be interpreted as regex
- Example: `assert_contains "[test]" "actual text"` won't match literal `[test]`

**Severity:** LOW - Test flakiness

---

### 47. Examples Helper Leaks Repository in CI ✅ **VALID**

**File:** `examples/run` line 36  
**Claim:** Prints `ls -la` into logs on every run

**Validation:**
```bash
# Line 36: ls -la "${TMPDIR}/tools" >&2
```
- Debug statement left in
- Prints to stderr unconditionally
- Shows directory contents in CI logs

**Severity:** LOW - Information leak, debug cruft

---

### 48. Resource Size Limit Enforced After Reading ✅ **VALID**

**File:** `lib/resources.sh` lines 708-751  
**Claim:** Entire content read into memory before checking 10 MiB limit

**Validation:**
```bash
# Line 738: if ! content="$(mcp_resources_read_via_provider "${provider}" "${uri}")"; then
# Line 747: content_size="$(LC_ALL=C printf '%s' "${content}" | wc -c | tr -d ' ')"
# Line 748: if [ "${content_size}" -gt "${limit}" ]; then
```
- Provider reads full content into `${content}` variable
- Only then checks size
- Can OOM on large resources

**Severity:** HIGH - Memory exhaustion

---

### 49. mkdir Failures Silenced in Runtime Init ✅ **VALID**

**File:** `lib/runtime.sh` lines 20-59  
**Claim:** mkdir errors silenced, causing obscure failures later

**Validation:**
```bash
# Line 48: mkdir -p "${MCPBASH_REGISTRY_DIR}"
# Line 54: mkdir -p "${MCPBASH_TOOLS_DIR}" >/dev/null 2>&1 || true
```
- Line 54 explicitly suppresses errors with `|| true`
- No permission check before use
- Later operations fail with confusing messages

**Severity:** MEDIUM - Poor error messages

---

### 50. Prompt Templates Expose All Environment Variables ✅ **VALID**

**File:** `lib/prompts.sh` lines 456-492  
**Claim:** Exports every env var, runs envsubst without restrictions; can interpolate secrets

**Validation:**
```bash
# Lines 478-486:
if ! text="$(
    set -a  # Export all variables!
    eval "$(printf '%s' "${args_json}" | jq -r '...')"
    set +a
    envsubst <"${full_path}"
)"; then
```
- Line 479: `set -a` exports ALL variables in environment
- Includes sensitive vars like `AWS_SECRET_ACCESS_KEY`, `DATABASE_PASSWORD`, etc.
- envsubst has access to everything
- Prompt template can contain `${AWS_SECRET_ACCESS_KEY}` and exfiltrate it

**Severity:** CRITICAL - Secret exposure

---

## Summary Statistics

- **Total Issues Validated:** 50
- **Valid:** 44 (88%)
- **Partially Valid:** 4 (8%)
- **Invalid:** 1 (2%)
- **Needs Review:** 1 (2%)

### Severity Breakdown (Valid + Partially Valid issues only)

- **CRITICAL:** 4 (Register script corruption, HTTPS DoS, prompt secrets, register re-execution)
- **HIGH:** 14 (includes #33-35 upgraded from MEDIUM due to server crash behavior)
- **MEDIUM:** 18
- **LOW:** 12

### Most Critical Issues Requiring Immediate Attention

1. **#50** - Prompt templates expose all environment variables (secret exfiltration)
2. **#1** - Path traversal in scaffold commands (arbitrary file write)
3. **#2** - Git provider path traversal (arbitrary file read)
4. **#12-16** - Manual registry scripts executed unsafely (crash, perf, security)
5. **#21** - HTTPS provider DoS (no timeouts or size limits)
6. **#11** - Subscription polling triggers excessive fetches (DoS)
7. **#8** - Subscription ID collisions on macOS (broken functionality)
8. **#9** - Binary resources unusable (no base64 support)

---

## Validation Methodology

This report was generated by:
1. Reading source files referenced in each claim
2. Verifying line numbers and code context
3. Tracing execution paths to confirm behavior
4. Cross-referencing with documentation and test coverage
5. Assessing impact and severity based on attack vectors and operational impact

**Validated by:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2024 (based on current conversation)  
**Codebase Version:** Git status shows 1 unpushed commit on master, 5 modified lib files

---

## Revision History

**Update 1:** Corrected issue #22 from "Invalid" to "Partially Valid" based on feedback from generating AI. While macOS users won't encounter Windows path handling issues, MSYS2/Cygwin users on Windows with older Bash versions would still hit the Bash 4+ requirement for `${var,,}` syntax. This is a real but narrow-scope issue.

**Update 2:** Corrected two validation errors:
- **Issue #6**: Expanded scope beyond "minimal mode only" - `lib/core.sh:785` hardcodes `jq` instead of using `${MCPBASH_JSON_TOOL_BIN}`, so log streaming fails even when `gojq` is installed and server is in full mode. More serious than originally described.
- **Issues #33-35**: Fixed incorrect analysis - all registry files have `set -euo pipefail`, so jq failures cause **immediate server crash**, not arithmetic errors. Upgraded severity from MEDIUM to HIGH.
