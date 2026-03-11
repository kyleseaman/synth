# Implementation Plan — QMD Integration (Optional Add-on)

## Problem Statement
Synth's current search is a hand-rolled in-memory keyword scorer (`NoteIndex`) with basic stemming and a small hardcoded synonym map. The MCP `global_search` tool is regex-based grep. Both work but lack semantic understanding. QMD (tobi/qmd) is an on-device hybrid search engine for markdown that provides BM25 via FTS5, vector search, and LLM re-ranking — all local. We want to integrate it as an optional enhancement: when QMD is installed and configured, search quality improves across the launcher and AI context retrieval. When it's not installed, everything works exactly as before.

## Requirements
- QMD is optional — Synth must work identically without it
- Settings UI: "Set up QMD" button that runs `qmd collection add <workspace>` + `qmd embed`; manual, user-initiated
- Settings UI: detect QMD availability, show status
- Launcher (Cmd+P): when QMD is enabled, pressing Enter triggers QMD-backed search with a loading indicator; keystroke filtering stays in-memory via `NoteIndex`
- AI context: `global_search` MCP tool transparently delegates to `qmd search --json` when QMD is available, falls back to regex grep when not
- Additionally register QMD's MCP server in `.kiro/settings/mcp.json` so the AI also has access to `qmd_deep_search` for semantic queries

## Background
- QMD is a Node.js/Bun CLI tool installed via npm (`npm install -g @tobilu/qmd`)
- It indexes markdown into SQLite (`~/.cache/qmd/index.sqlite`), supports BM25 (`qmd search`), vector (`qmd vsearch`), and hybrid+reranking (`qmd query`)
- It exposes an MCP server via `qmd mcp` (stdio or HTTP)
- QMD's `--json` output format is designed for programmatic consumption
- Synth already has a pattern for binary resolution (`KiroCliResolver` in `ACPTypes.swift`) and MCP server config writing (`MCPServerManager.writeMcpConfig`)

## Task Breakdown

### Task 1: QmdResolver — detect QMD binary on the system ✅
- **Objective:** Create a `QmdResolver` enum (following `KiroCliResolver` pattern) that checks common paths and `which qmd` to find the binary
- **Implementation:** New file `SynthApp/QmdResolver.swift`. Check `/usr/local/bin/qmd`, `/opt/homebrew/bin/qmd`, `~/.local/bin/qmd`, `~/.bun/bin/qmd`, then fall back to `which qmd`. Cache the result.

### Task 2: QmdClient — shell wrapper for QMD CLI ✅
- **Objective:** Create a `QmdClient` class that shells out to `qmd` for search, status, collection management, and embed commands
- **Implementation:** New file `SynthApp/QmdClient.swift`. Methods: `search(query:collection:limit:)`, `status()`, `collectionAdd(path:name:)`, `embed()`. All methods run `Process` async on a background queue. Parse `--json` output.

### Task 3: Settings UI — QMD section in Settings ✅
- **Objective:** Add QMD configuration to the Settings view with status display and setup button
- **Implementation:** Add a "Search" tab to `SettingsView`. Show detected QMD path, workspace collection status, "Set up QMD" button.

### Task 4: Launcher integration — QMD-backed search on Enter ✅
- **Objective:** When QMD is available and the user presses Enter in the launcher, run a QMD search and display results with a loading state
- **Implementation:** In `FileLauncher.swift`: on Enter with a query, if QMD is enabled, call `QmdClient.search(query)` async. Show loading indicator. Blend results.

### Task 5: MCP global_search transparent upgrade ✅
- **Objective:** When QMD is available, `global_search` in the synth-mcp-server delegates to `qmd search --json` for better results
- **Implementation:** In `GlobalSearch.swift`, check if `qmd` binary exists. If available, shell out. Fall back to existing regex on failure.

### Task 6: Register QMD MCP server in .kiro config ✅
- **Objective:** When QMD is detected, register QMD's MCP server in `.kiro/settings/mcp.json`
- **Implementation:** In `MCPServerManager.writeMcpConfig()`, add a `qmd` entry when `QmdResolver.resolve()` finds the binary.

### Task 7: Wire everything together — lifecycle integration ✅
- **Objective:** Connect QMD detection and status into the workspace lifecycle
- **Implementation:** In `DocumentStore`, add `qmdClient` property. On workspace set, instantiate if QMD is available.

## Key Design Decisions
- **QMD v2.0 hybrid pipeline** — uses `qmd query` (BM25 + vector + LLM re-ranking) instead of `qmd search` (BM25-only) for significantly better search quality
- **Write minimal code** — QMD does the heavy lifting; Synth just shells out and parses JSON
- **Graceful degradation** — every QMD call has a fallback path; timeouts, missing binary, parse errors all fall back silently
- **Follow existing patterns** — `QmdResolver` mirrors `KiroCliResolver`, MCP config follows `MCPServerManager.writeMcpConfig()`
- **No new dependencies** — integration is purely via `Process` (shell out to `qmd` CLI)
