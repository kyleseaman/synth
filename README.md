# Synth

A native macOS 26 text editor built for writers who think in links, tags, and daily notes — with AI woven into every workflow.

## Features

### Editor
- Live markdown rendering as you type — headings, bold, italic, code, lists, blockquotes, and inline images
- `[[Wiki links]]` with autocomplete and navigation between notes
- `@mentions` for people with autocomplete
- `#tags` with inline highlighting
- Tabbed editing with `Cmd+1`–`9` switching
- Fuzzy file search with `Cmd+P`
- Inline image paste, drag-and-drop, resize, and detail view
- `.md`, `.txt`, and `.docx` file support

### Knowledge Graph
- **Backlinks** — see every note that links to the current one, with context snippets
- **Related notes** — surface connections you didn't explicitly make
- **Tag browser** (`Cmd+Shift+T`) — browse all tags across your workspace
- **People browser** (`Cmd+Shift+P`) — browse all @mentioned people and the notes they appear in

### Daily Notes
- Chronological scroll view with one editor per day (`Cmd+D`)
- Calendar sidebar for quick date navigation
- 30 past + 7 future days, virtual notes materialized on first edit
- Auto-save with 1-second debounce

### AI Chat
- Per-document AI chat panel (`Cmd+J`)
- Three specialized agents: **Editor** (grammar, clarity, restructuring), **Writer** (drafting from descriptions/outlines), **Researcher** (finding and summarizing information)
- Selection-aware — highlight text and chat about just that passage
- File read/write tool use with inline diff review and undo
- MCP server exposing 8 workspace tools (`read_note`, `list_notes`, `global_search`, `manage_tags`, `update_note`, `get_backlinks`, `get_people`, `create_note`) so AI has full workspace context

### Capture
- **Link capture** (`Cmd+Shift+L`) — global hotkey to save URLs from anywhere, even when Synth isn't focused
- **Meeting notes** (`Cmd+Shift+M`) — templated meeting note creation with date and attendees

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+N` | New draft |
| `Cmd+O` | Open workspace |
| `Cmd+S` | Save |
| `Cmd+W` | Close tab |
| `Cmd+P` | Go to file |
| `Cmd+D` | Daily notes |
| `Cmd+J` | Toggle AI chat |
| `Cmd+\` | Toggle sidebar |
| `Cmd+1`–`9` | Switch tabs |
| `Cmd+Shift+T` | Tag browser |
| `Cmd+Shift+P` | People browser |
| `Cmd+Shift+B` | Toggle backlinks |
| `Cmd+Shift+L` | Capture link (global) |
| `Cmd+Shift+M` | New meeting note |

## Architecture

Modern SwiftUI (macOS 26) frontend with a Rust core linked via C FFI.

- **SwiftUI** — all views, state management (`@Observable`), and navigation
- **AppKit** — only for `FormattingTextView` (NSTextView subclass for rich text editing) and `WikiLinkPopover` (NSPopover for positioned autocomplete)
- **Rust** — document processing via `synth-core` static library
- **MCP server** — Swift CLI tool providing workspace tools over JSON-RPC 2.0 (stdio + HTTP/SSE)

## Build

```bash
# Rust core (must be first)
cd synth-core && cargo build --release

# MCP server
cd synth-mcp-server && swift build -c release

# Swift app
cd SynthApp && swiftc *.swift -import-objc-header BridgingHeader.h \
  -L ../synth-core/target/release -I ../synth-core -lsynth_core -o Synth

# Run
./SynthApp/Synth
```

Or open `Synth.xcodeproj` in Xcode.

## Requirements

- macOS 26
- Rust toolchain (for synth-core)
- Xcode 26 or Swift 6 toolchain
