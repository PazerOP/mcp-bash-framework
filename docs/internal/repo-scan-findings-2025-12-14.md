## Repo scan findings (2025-12-14)

Scope: quick “health scan” for bugs, inefficiencies, MCP spec incompatibilities (esp. with common MCP clients), docs vs code mismatches, and DX issues.

### 1) MCP 2025-11-25 incompatibility: `completion/complete` request schema is legacy-only

- **Status**: ✅ Implemented (spec compatible; legacy removed)
- **Rationale**: Common MCP clients that target newer protocol versions will send the 2025-11-25 `completion/complete` shape (`params.ref` + `params.argument`), not the older `params.name` + `params.arguments` shape.
- **Spec reference**: `https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/completion`
- **Implementation notes**:
  - **Runtime**: request parsing and handler logic were updated to accept the MCP 2025-11-25 shape (`params.ref` + `params.argument`, optional `context.arguments`) and reject the legacy `name`/`arguments` shape.
  - **Tests**: integration + strict-shape conformance tests were updated to use the spec request shape.
  - **Docs/examples**: completion docs and the completions example were updated to show only the spec request shape.
  - **Changelog**: recorded as a breaking change (legacy completion request shape removed).

### 2) Potential client incompatibility: completion `values` are content objects, not strings

- **Status**: ✅ Implemented (spec compliant)
- **Rationale**: MCP 2025-11-25 defines `result.completion.values` as a list of suggested completion **strings**. This repo returns an array of **objects** (e.g., `{type:"text", text:"..."}`), which is outside the spec shape and likely to be rejected by strict clients.
- **Spec reference**: `https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/completion`
- **Implementation notes**:
  - **Runtime**: `mcp_completion_finalize()` now normalizes provider suggestions and emits `result.completion.values` as **`string[]`** on the wire (mapping `{type:"text",text}` → `text`; dropping non-text entries).
  - **Tests**: integration + strict conformance assertions were updated to expect `string[]`.
  - **Docs**: completion docs now call out the on-the-wire `string[]` requirement while still allowing providers to emit `{type:"text",text:"..."}` internally.

- **Impact**:
  - Completion may silently fail in UIs that expect `string[]` suggestions.
  - Even if accepted, mixed client ecosystems will have inconsistent behavior.
- **Suggested fix**:
  - Emit `values` as `string[]` on the wire (map `{type:"text",text}` → `text`; drop non-text or stringify conservatively).
  - If you need richer typed values, attach them via an extension mechanism (e.g., `result._meta[...]`) while keeping `values` spec-shaped.
  - Tighten conformance tests to assert the intended element type for the target protocol.

### 3) Docs mismatch: `llms-full.txt` has incorrect error-code mapping and provider mapping

- **Status**: ✅ Implemented (aligned with runtime + `docs/ERRORS.md`)
- **Rationale**: `llms-full.txt` appears intended as a “contract” for LLM-assisted work; incorrect codes here increase the odds of regressions and wrong troubleshooting advice.
- **Evidence**:
  - Previously, it claimed `-32002` is “server not initialized”:

```214:217:/Users/yaniv/Documents/code/mcpbash/llms-full.txt
- `-32002` → server not initialized (`initialize` not completed).
```

  - But runtime uses `-32000` for not-initialized (and explicitly reserves `-32002` for resource-not-found):

```1034:1045:/Users/yaniv/Documents/code/mcpbash/lib/core.sh
mcp_core_emit_not_initialized() {
	...
	# MCP reserves -32002 for resources/read "Resource not found" (spec 2025-11-25).
	# Use a distinct server error for pre-init gating.
	rpc_send_line "$(mcp_core_build_error_response "${id_json}" -32000 "Server not initialized" "")"
}
```

  - Previously, it also claimed `file.sh` missing-file maps to `-32601`:

```222:225:/Users/yaniv/Documents/code/mcpbash/llms-full.txt
- `file.sh`: exit `2` (outside allowed roots) → `-32603`; exit `3` (missing file) → `-32601`.
```

  - But runtime maps provider exit `3` (missing file) to `-32002 "Resource not found"` (see also `docs/ERRORS.md`):

```1419:1426:/Users/yaniv/Documents/code/mcpbash/lib/resources.sh
	case "${status}" in
	2)
		mcp_resources_error -32603 "Resource outside allowed roots"
		;;
	3)
		mcp_resources_error -32002 "Resource not found"
		;;
```

- **Impact**:
  - Confusing/wrong troubleshooting guidance.
  - Increased risk of tests/docs drifting further from code.
- **Suggested fix**:
  - Align `llms-full.txt` with `docs/ERRORS.md` and actual code behavior.
  - Add a small “generated from source” note or a check to prevent drift (even just a grep-based CI assertion for the key codes).
- **Implementation notes**:
  - Updated `llms-full.txt` to map `-32000` → not initialized, `-32002` → resource not found, and `file.sh` missing-file exit `3` → `-32002` (commit `03c1dc9`).

### 4) Docs/code mismatch: `lib/tools_policy.sh` header claims “default allow-all” but policy is deny-by-default

- **Status**: ✅ Implemented (comment updated; behavior unchanged)
- **Rationale**: Comment says one thing; runtime behavior is another. This is a classic source of operator confusion.
- **Evidence**:
  - Previously, header comment said:

```1:4:/Users/yaniv/Documents/code/mcpbash/lib/tools_policy.sh
#!/usr/bin/env bash
# Tool-level policy hook (default allow-all; override via server.d/policy.sh).
```

  - But the implemented behavior denies when `MCPBASH_TOOL_ALLOWLIST` is empty and `MCPBASH_TOOL_ALLOW_DEFAULT` is not `allow`:

```137:153:/Users/yaniv/Documents/code/mcpbash/lib/tools_policy.sh
local allow_default="${MCPBASH_TOOL_ALLOW_DEFAULT:-deny}"
local allow_raw="${MCPBASH_TOOL_ALLOWLIST:-}"

if [ -z "${allow_raw}" ]; then
	case "${allow_default}" in
	allow | all)
		allow_raw="*"
		;;
	*)
		_MCP_TOOLS_ERROR_CODE=-32602
		...
		return 1
		;;
	esac
fi
```

- **Impact**:
  - Developers reading the file header will expect allow-by-default and be surprised by `-32602` blocks.
- **Suggested fix**:
  - Update the header comment to reflect deny-by-default.
  - Optionally add a short comment near the deny path that points to `docs/ENV_REFERENCE.md` variables (`MCPBASH_TOOL_ALLOWLIST`, `MCPBASH_TOOL_ALLOW_DEFAULT`) for remediation.
- **Implementation notes**:
  - Updated `lib/tools_policy.sh` header + default-policy comment to reflect deny-by-default, with env var pointers in the comment.

### 5) Windows portability risk (E2BIG): completion provider runner uses external `env`

- **Status**: ✅ Implemented (bash-native env scrubbing; reduced subprocess spawns)
- **Rationale**: Git Bash/MSYS can fail spawning subprocesses when the environment block is large (`E2BIG`). Completion provider execution currently spawns an extra external process (`env`) before spawning the provider script, which can increase failure probability on MSYS. However, the provider still needs to spawn as a subprocess, so removing `env` reduces one process launch but does not remove the underlying “large environment at spawn time” risk.
- **Evidence**:
  - Completion provider runner constructs `runner=( env "K=V" ... )`:

```650:718:/Users/yaniv/Documents/code/mcpbash/lib/completion.sh
local runner=(
	env
	"MCPBASH_JSON_TOOL_BIN=${MCPBASH_JSON_TOOL_BIN}"
	"MCPBASH_JSON_TOOL=${MCPBASH_JSON_TOOL}"
	"MCP_COMPLETION_NAME=${name}"
	...
)
...
"${runner[@]}" "${abs_script}"
```

  - Related internal analysis for Windows env-size mitigation emphasizes avoiding external `env` due to E2BIG:

```20:31:/Users/yaniv/Documents/code/mcpbash/docs/internal/plan-windows-env-size-mitigation-2025-12-14.md
On MSYS, **spawning any external binary** can fail if the environment passed to exec/CreateProcess is too large.
...
Make subprocess launches robust ... `MCPBASH_TOOL_ENV_MODE=minimal|allowlist` no longer depends on spawning `env`.
```

- **Impact**:
  - Completions can fail on Windows Git Bash even when tools/resources/prompts otherwise work.
- **Suggested fix**:
  - Replace external `env` usage with bash-native env setup in a subshell: `export VAR=...; exec "${abs_script}"` (removes one external process launch).
  - Note: `lib/resources.sh` also uses external `env` to run providers; completion is not the only place with this pattern.
  - Keep variable injection explicit (only the variables you intend), consistent with the security posture.
- **Implementation notes**:
  - Introduced a shared curated-env helper (`mcp_env_run_curated`) and replaced external `env` usage in `lib/completion.sh`, `lib/resources.sh`, and `lib/prompts.sh`.
  - CI env snapshot no longer spawns `env` to estimate environment size.
  - Added unit coverage for the helper and a Windows/MSYS integration test that exercises completion/resources/prompts under inflated environments.

### 6) Minor documentation grammar issue in `README.md.in`

- **Status**: ✅ Implemented
- **Rationale**: Small, but it’s on a highly-visible page.
- **Evidence**:

```339:342:/Users/yaniv/Documents/code/mcpbash/README.md.in
Tool names must match `^[a-zA-Z0-9_-]{1,64}$`; Some clients, including Claude Desktop, enforces this and rejects dotted names, so prefer hyphens/underscores for namespaces.
```

- **Impact**:
  - Minor professionalism/readability hit.
- **Suggested fix**:
  - Change to: “Some clients … enforce …” (lowercase “some”, plural verb).
- **Implementation notes**:
  - Updated `README.md.in` and re-rendered `README.md`.
