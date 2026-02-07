# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Synth is a native macOS text editor (macOS 13+) with AI integration. SwiftUI/AppKit frontend with a Rust core linked via FFI. Press `Cmd+K` to invoke AI assistance via `kiro-cli` subprocess.

## Build Commands

```bash
# Build Rust core (must be done first)
cd synth-core && cargo build --release

# Build MCP server
cd synth-mcp-server && swift build -c release

# Build Swift app (from SynthApp/)
cd SynthApp && swiftc *.swift -import-objc-header BridgingHeader.h \
  -L ../synth-core/target/release -I ../synth-core -lsynth_core -o Synth

# Run
./SynthApp/Synth

# Rust tests
cd synth-core && cargo test

# Lint fixes
cd synth-core && cargo fmt
swiftlint lint --fix SynthApp/
```

There is also an Xcode project (`Synth.xcodeproj`) for building via Xcode.

## Architecture

**Hybrid Swift + Rust**: The Swift frontend calls into a Rust static library (`synth-core`) through C FFI. The bridge is defined in `synth-core/synth_core.h` and imported via `SynthApp/BridgingHeader.h`.

**Key Swift files in `SynthApp/`**:
- `SynthApp.swift` — App entry point, scene setup, global keyboard shortcuts
- `ContentView.swift` — Main UI: NavigationSplitView with file sidebar, editor tabs, chat panel
- `DocumentStore.swift` — Central state management (@StateObject, MVVM). Manages workspace path, file tree, open documents, persists via UserDefaults
- `Document.swift` — File model with load/save (.docx via Rust FFI, .md, .txt)
- `MarkdownEditor.swift` — NSViewRepresentable wrapping FormattingTextView (NSTextView subclass) with live markdown rendering, wiki links, @mentions, #tags
- `DailyNotesView.swift` — Chronological daily notes scroll view with inline FormattingTextView editors per day
- `DailyNoteManager.swift` — Daily note lifecycle: entry scanning, virtual note materialization, debounced auto-save
- `CalendarSidebarView.swift` — Monthly calendar widget for the daily notes right sidebar
- `DailyNoteResolver.swift` — Daily note file resolution (today/yesterday/tomorrow tokens)
- `ACPClient.swift` — JSON-RPC 2.0 client for Kiro CLI (ACP protocol)
- `FileLauncher.swift` — Cmd+P fuzzy file search

**Rust core (`synth-core/src/lib.rs`)**:
- `extract_text()` — Parses .docx files via docx-rs, returns plain text
- `kiro_chat()` — Invokes `kiro-cli chat` subprocess
- `free_string()` — Frees C strings returned to Swift

**MCP server (`synth-mcp-server/`)**:
- Swift CLI tool providing 8 workspace tools via MCP protocol (JSON-RPC 2.0)
- Supports stdio transport (for kiro-cli) and HTTP+SSE on localhost (for external agents)
- Tools: `read_note`, `list_notes`, `global_search`, `manage_tags`, `update_note`, `get_backlinks`, `get_people`, `create_note`
- Auto-started by `MCPServerManager` when workspace opens

**UI communication** uses NotificationCenter for cross-component events (toggleChat, toggleSidebar, showFileLauncher, showDailyNotes).

**View switching pattern**: `DocumentStore` has boolean flags (`isLinksTabSelected`, `isDailyNotesViewActive`) that `ContentView` checks in the detail column to render the appropriate view (LinksView, DailyNotesView, or editor). These flags are mutually exclusive — setting one clears the others via `open()`, `switchTo()`, `selectLinksTab()`, `selectDailyNotesTab()`.

**Daily Notes architecture**: Notes stored in `{workspace}/daily/YYYY-MM-DD.md`. `DailyNoteManager` generates entries for 30 past + 7 future days, auto-creates today+7 files on workspace load. Virtual notes (no file) are materialized on first edit. Each day gets a bare `FormattingTextView` (no NSScrollView wrapper) to avoid nested scroll issues. Debounced 1-second auto-save with `saveAll()` also called on app deactivation.

**Xcode project**: When adding new Swift files, they must be registered in `Synth.xcodeproj/project.pbxproj` in 4 places: PBXBuildFile, PBXFileReference, PBXGroup children, and PBXSourcesBuildPhase. Without this, Xcode builds will fail and SourceKit will show "Cannot find type in scope" errors.

## Code Style

### Swift
- Variable names must be 3+ characters (use `index` not `i`, `first` not `a`)
- No force unwrap (`!`) or force try (`try!`) without explicit disable comment
- Lines under 120 characters
- Use trailing closure syntax
- Group with `// MARK:` comments
- Fix ALL swiftlint warnings, not just errors

### Rust
- Run `cargo fmt` before committing
- Avoid `.unwrap()` in library code — use `Result`/`Option`
- Document FFI functions with `///` comments
- Minimize unsafe blocks

## Pre-commit Hooks

Every commit runs `cargo fmt --check` and `swiftlint`. Never bypass with `--no-verify`. Fix all issues including pre-existing warnings in files you didn't modify.

## Commit Messages

Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`
