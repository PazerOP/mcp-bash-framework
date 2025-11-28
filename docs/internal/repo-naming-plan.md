# Repo Naming and Documentation Alignment Plan

## Goals
- Keep the repository name **mcp-bash-framework** (pre-release, no external dependencies yet).
- Keep the CLI/server binary name **mcp-bash**.
- Remove ambiguity by using one repo/clone path everywhere and documenting the mapping explicitly.

## Decisions
- Official repo/clone URL: `https://github.com/yaniv-golan/mcp-bash-framework.git`.
- Official clone path in docs/examples: `~/mcp-bash-framework` (do not mix `~/mcp-bash`).
- CLI/server name: `mcp-bash` (binary remains `bin/mcp-bash`).
- Badges: URL points to `mcp-bash-framework`; label can say `mcp-bash` (CLI name).

## Actions
1) README header: Add a short note near the top clarifying the mapping  
   - “Repository: mcp-bash-framework; CLI/server binary: mcp-bash.”  
   - Standardize all client recipes to use `~/mcp-bash-framework/bin/mcp-bash`.
2) Paths/examples: Replace any `~/mcp-bash` path in docs with `~/mcp-bash-framework` for consistency.  
   - Client configs, scaffold examples, Docker snippets, etc.
3) Optional convenience: Mention that users may create a local symlink (`ln -s ~/mcp-bash-framework ~/mcp-bash`) if they want shorter paths, but do not rely on it in official docs.
4) GitHub metadata: Set description/topics to include both terms (“mcp-bash (CLI) — repository: mcp-bash-framework”) to help search and reduce confusion.
5) Badges: Keep pointing to `mcp-bash-framework`; ensure badge text refers to the CLI/product name `mcp-bash`.
6) FAQ entry: Briefly explain why the repo and CLI names differ (framework vs. binary).
