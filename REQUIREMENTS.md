# Synth Requirements Document (Code-Based Baseline)

## 1. Metadata
- Product: Synth
- Platform: Native macOS application (SwiftUI + AppKit + optional Rust static library)
- Document date: 2026-02-13
- Document intent: Define the true requirements implied by the current implemented application, not a speculative roadmap.

## 2. Product Definition
Synth is a workspace-based macOS knowledge editor focused on:
- Markdown-first writing
- Linked notes (`[[...]]`), date references (`@...`), people mentions (`@Person`), and tags (`#tag`)
- Daily note timeline editing
- Backlinks and related-note discovery
- Workspace search and capture workflows
- Embedded AI collaboration through `kiro-cli` ACP and a local MCP server

## 3. Product Goals
- G1: Let users manage a local markdown knowledge base with low-friction navigation and editing.
- G2: Preserve plain-text markdown while rendering rich inline UI affordances.
- G3: Keep all indexing and workspace operations local-first and responsive.
- G4: Make AI assistance workspace-aware with explicit permission handling for edits.
- G5: Support keyboard-first workflows across core features.

## 4. Non-Goals (Current Scope)
- NG1: No cloud sync, account system, or multi-device collaboration.
- NG2: No graph visualization UI.
- NG3: No plugin marketplace or third-party extension host.
- NG4: No guaranteed cross-workspace aggregation for links/tags/people (except global people name memory in UserDefaults).

## 5. Primary Users and Jobs
- U1: Knowledge worker maintaining linked project notes.
- U2: Writer/researcher using markdown and daily journal workflows.
- U3: User employing AI to rewrite, summarize, and edit local files with review controls.

Primary jobs:
- J1: Open a workspace and quickly find/edit notes.
- J2: Create semantic links between notes, people, tags, and dates.
- J3: Traverse incoming/outgoing context (backlinks, related notes).
- J4: Capture external links and meeting notes into the workspace.
- J5: Run AI-assisted edits without losing local control.

## 6. System and Architecture Requirements

### 6.1 Runtime Architecture
- AR-001: The app must run as a native macOS SwiftUI application with `NavigationSplitView` layout.
- AR-002: AppKit use is required for rich text editing (`NSTextView` subclass `FormattingTextView`) and popover autocomplete.
- AR-003: Workspace indexes must be maintained in-memory via:
  - `NoteIndex`
  - `BacklinkIndex`
  - `TagIndex`
  - `PeopleIndex`
- AR-004: Index rebuilds must use unified single-pass file reads via `UnifiedIndexer` for markdown/text files.
- AR-005: The app must remain functional without the Rust FFI path; Rust linkage is build-time dependency, not a required runtime code path in current implementation.

### 6.2 Workspace Boundary Model
- AR-010: All destructive file operations (delete file/folder/media) must be constrained to allowed workspace scopes.
- AR-011: Workspace-relative safety checks must canonicalize and resolve symlinks before boundary decisions.
- AR-012: MCP tools must reject path traversal outside workspace.

## 7. Functional Requirements

### 7.1 Workspace Lifecycle
- FR-WS-001: User must be able to pick a workspace folder via system file importer.
- FR-WS-002: Last opened workspace path must persist in `UserDefaults` and auto-restore if path still exists.
- FR-WS-003: Setting a workspace must:
  - reset editor and modal state
  - load file tree
  - start filesystem watcher
  - initialize `.kiro` context state
  - ensure daily note files for today + 7 days
  - start MCP server manager
- FR-WS-004: Sidebar tree scanning must exclude hidden paths and exclude `daily/` and `media/`.
- FR-WS-005: Workspace watcher must ignore `.kiro/`, `daily/`, and `media/` events for sidebar refresh decisions.

### 7.2 File Tree, Tabs, and Document Lifecycle
- FR-DOC-001: Supported openable/editable file types:
  - `.md`
  - `.txt`
  - `.docx`
- FR-DOC-002: Oversized files (>50 MB) must be rejected for open.
- FR-DOC-003: Opening an already-open file must focus its existing tab.
- FR-DOC-004: App must support multi-tab editing with command switching (`Cmd+1` to `Cmd+9`).
- FR-DOC-005: Save operations:
  - `Cmd+S` saves current tab
  - autosave on timers and app lifecycle (`resign active`, editor debounced save)
  - `saveAll` must persist all dirty files and daily notes
- FR-DOC-006: Untitled draft files must auto-rename from first heading/line when saved, with collision protection.
- FR-DOC-007: App must provide commands for:
  - New draft
  - New meeting note
  - Close tab
  - Open workspace
- FR-DOC-008: File/folder rename and delete must be available from context menus.
- FR-DOC-009: Folder delete must require explicit confirmation dialog.
- FR-DOC-010: File delete may execute immediately from context action.

### 7.3 Note Creation Workflows
- FR-NOTE-001: Creating a new draft must create files under `drafts/` with incremental `Untitled` naming.
- FR-NOTE-002: Meeting note creation must create files under `meetings/` named as `<yyyy-MM-dd> <meeting name>.md` with uniqueness suffixes.
- FR-NOTE-003: `createNoteIfNeeded(title:)` must sanitize titles and create `<title>.md` in workspace root when absent.
- FR-NOTE-004: Wiki-link-driven note creation must support non-opening creation for background materialization.

### 7.4 Editor Rendering and Interaction
- FR-ED-001: Markdown rendering must support:
  - headings (`#`, `##`, `###`) with hidden markers
  - bullets (`-`, `*`) rendered as `•` with round-trip preservation
  - bold, italic (`*` and `_`), underline, inline code
  - wiki links, date links, people mentions, tags
  - inline images with markdown source preservation
- FR-ED-002: Editor must preserve raw markdown in saved file while hiding selected syntax markers visually.
- FR-ED-003: Editor must support keyboard formatting shortcuts:
  - `Cmd+B`
  - `Cmd+I`
  - `Cmd+U`
- FR-ED-004: Bullet behavior must support:
  - auto conversion from `- ` / `* ` to bullet glyph
  - newline continuation for bullet lines
  - tab/shift-tab indent behavior for bullet lines
- FR-ED-005: Line number gutter and scroll-sync must remain active in main editor mode.
- FR-ED-006: Selection metadata (selected text and line range) must be available to AI chat prompt context.

### 7.5 Linking, Mentions, Tags, Templates (Autocomplete)
- FR-AUTO-001: Autocomplete state machine must support modes:
  - wiki link (`[[`)
  - mention/date (`@`)
  - hashtag (`#`)
  - template slash (`/`)
- FR-AUTO-002: Arrow, Enter, Escape navigation must work when autocomplete popover is active.
- FR-AUTO-003: Wiki completion must insert `[[Title]]`.
- FR-AUTO-004: Mention completion must branch:
  - person mention as `@Name `
  - date mention as `@yyyy-MM-dd `
- FR-AUTO-005: Hashtag completion must insert `#tag `.
- FR-AUTO-006: Template completion must insert expanded template content, including variable expansion and optional cursor placement.
- FR-AUTO-007: Completing a wiki link to a missing note must auto-create file (without forced open) so link renders as existing.
- FR-AUTO-008: Completing date mentions must ensure corresponding `daily/yyyy-MM-dd.md` exists.

### 7.6 Link Click Routing
- FR-LINK-001: Clicking `synth://wiki/...` links must open existing note or offer/create missing note.
- FR-LINK-002: Clicking `synth://daily/...` links must resolve token/date, ensure file existence, and activate daily notes view for that date.
- FR-LINK-003: Clicking `synth://tag/...` must open Tag Browser pre-filtered to tag.
- FR-LINK-004: Clicking `synth://person/...` must open People Browser pre-filtered to person.

### 7.7 Daily Notes
- FR-DN-001: Daily notes must use file convention `daily/YYYY-MM-DD.md`.
- FR-DN-002: Daily note manager load range must include:
  - 30 past days
  - today
  - 7 future days
- FR-DN-003: Future day files for today + 7 must be proactively created on workspace set.
- FR-DN-004: Daily notes view must present a chronological timeline with inline editing per day.
- FR-DN-005: Virtual entries must materialize to file on first edit.
- FR-DN-006: Daily note edits must autosave with 1-second debounce.
- FR-DN-007: Daily notes view must include calendar sidebar with month navigation and note-day indicators.
- FR-DN-008: Daily entries must include backlinks section for incoming references.

### 7.8 Backlinks and Related Notes
- FR-KG-001: Backlink index must track incoming/outgoing wiki links and `@yyyy-MM-dd` references.
- FR-KG-002: Editor sidebar must show backlinks for current note with snippet context and navigation.
- FR-KG-003: Related notes must be computed from:
  - shared tags
  - mutual links
  - shared outgoing targets
  - shared incoming sources
- FR-KG-004: Related notes UI must be collapsible and navigable.

### 7.9 Search and Discovery
- FR-SRCH-001: Launcher (`Cmd+P`) must search notes with ranked semantics + fuzzy matching.
- FR-SRCH-002: Search parser must support:
  - quoted phrases
  - `tag:` filters
  - `person:` / `people:` / `mention:` filters
  - `path:` / `in:` filters
  - shorthand `#tag` and `@person`
- FR-SRCH-003: Search ranking must include token matches, phrase matches, fuzzy title score, recency boost, and semantic token expansion.
- FR-SRCH-004: Search preview must return best matching line-level snippets, cleaned for markdown noise.
- FR-SRCH-005: Launcher must also support person-only mode via leading `@` query.

### 7.10 Tag and People Browsers
- FR-BROWSE-001: Tag Browser (`Cmd+Shift+T`) must support:
  - fuzzy filter over tags
  - multi-tag intersection
  - note list navigation/open
- FR-BROWSE-002: People Browser (`Cmd+Shift+P`) must support:
  - fuzzy filter over people
  - multi-person intersection
  - note list navigation/open

### 7.11 Media Management
- FR-MEDIA-001: Pasted images must be saved in `media/` with timestamped unique file names.
- FR-MEDIA-002: Inserted markdown must use relative path from note directory to media asset.
- FR-MEDIA-003: Inline image rendering must support:
  - async thumbnail loading with cache
  - overlay actions (copy, delete, open)
  - drag-resize with width persisted as markdown metadata (`=WIDTHx`)
- FR-MEDIA-004: Media tab must list screenshot assets.
- FR-MEDIA-005: Media deletion must be restricted to `media/` scope and update in-memory lists immediately.
- FR-MEDIA-006: Orphaned media cleanup may run on workspace open by scanning markdown references.

### 7.12 Link Capture
- FR-CAP-001: Global hotkey `Cmd+Shift+L` must invoke link capture modal even when app is not focused.
- FR-CAP-002: Link capture must validate/normalize URLs (allow `http`/`https`, infer `https://` where possible).
- FR-CAP-003: Saved links must deduplicate by URL and move recaptured links to top.
- FR-CAP-004: Links view must allow open, copy, delete operations.

### 7.13 Templates
- FR-TPL-001: Template store must support CRUD, duplicate, search, category metadata, usage counts, and optional shortcut slots.
- FR-TPL-002: Variable expansion must support:
  - date/time/datetime with optional custom format
  - year/month/day/weekday
  - title/filename
  - cursor placement marker
  - UUID
  - random numbers
- FR-TPL-003: Templates must be insertable by slash autocomplete and by menu shortcuts (`Opt+Cmd+1..9` when configured).

### 7.14 AI Chat and ACP Session
- FR-AI-001: Chat state must be per-document tab.
- FR-AI-002: Chat tray must support:
  - streaming assistant output
  - tool-call status bubbles
  - permission prompts with diff display
  - quick prompts and agent selection
- FR-AI-003: Prompt payload must include:
  - selected text context when present
  - otherwise full current document content
  - user prompt text block
- FR-AI-004: ACP client must:
  - launch `kiro-cli acp`
  - initialize protocol
  - create session with workspace cwd
  - send prompts/cancel
  - process tool-call updates and turn completion
- FR-AI-005: File read/write callbacks from ACP must be workspace-scoped.
- FR-AI-006: On AI edit tool completion, affected files must reload from disk when open.
- FR-AI-007: Undo snapshot for AI writes must be available and expire after timeout.

### 7.15 MCP Server Integration
- FR-MCP-001: App must resolve `synth-mcp-server` binary from bundle/dev/install/`which` paths.
- FR-MCP-002: On workspace start, app must write/merge `.kiro/settings/mcp.json` preserving user servers and adding `synth-mcp`.
- FR-MCP-003: MCP manager must support:
  - optional durable HTTP bridge (`mcpHttpBridgeEnabled`)
  - stdio config for ACP sessions regardless of HTTP bridge
  - runtime lease persistence per workspace in Application Support
  - health checks and restart backoff
- FR-MCP-004: MCP server must expose tools:
  - `read_note`
  - `list_notes`
  - `global_search`
  - `manage_tags`
  - `update_note`
  - `get_backlinks`
  - `get_people`
  - `create_note`

### 7.16 Settings and Workspace Context
- FR-SET-001: Settings UI must provide tabs for General, Fonts, Context, Agents, Templates.
- FR-SET-002: Users must be able to configure `kiro-cli` path and HTTP bridge toggle.
- FR-SET-003: Users must be able to override editor/terminal/sidebar font candidate lists.
- FR-SET-004: Context tab must surface steering files and custom agents from `.kiro`.
- FR-SET-005: App must support bootstrapping `.kiro` with starter steering and default `doc-writer` agent.

## 8. Non-Functional Requirements

### 8.1 Performance
- NFR-P-001: File tree scanning and index rebuild must be asynchronous from main UI thread.
- NFR-P-002: Index rebuild must read each source file once for all indexes.
- NFR-P-003: Search response should remain interactive on medium-large workspaces due to in-memory ranking.
- NFR-P-004: Inline image loading must be asynchronous and cached.

### 8.2 Reliability
- NFR-R-001: Dirty content must be persisted on app deactivation and termination hooks.
- NFR-R-002: Watcher-triggered reloads must be debounced to avoid repeated expensive scans.
- NFR-R-003: MCP durable server must recover from failures through health-based restart logic.

### 8.3 Data Safety and Security
- NFR-S-001: Delete operations must enforce workspace/media scope boundaries.
- NFR-S-002: MCP tools must reject path traversal and dangerous regex classes where applicable.
- NFR-S-003: Runtime lease files must live outside workspace and be keyed per workspace path.

### 8.4 UX and Input
- NFR-U-001: Core operations must be keyboard accessible via command menu shortcuts.
- NFR-U-002: Popover and modal workflows must support Enter/Escape semantics.
- NFR-U-003: UI should remain usable at minimum window size `800x500`.

## 9. Data Model and Persistence Requirements

### 9.1 File/Folder Conventions
- `daily/YYYY-MM-DD.md`
- `media/screenshot-<timestamp>.png`
- `drafts/Untitled*.md`
- `meetings/<yyyy-MM-dd> <name>.md`
- `.kiro/steering/*.md`
- `.kiro/agents/*.json`
- `.kiro/settings/mcp.json`

### 9.2 UserDefaults Keys (Current)
- `lastWorkspace`
- `recentFiles`
- `synth.savedLinks`
- `synth.savedTemplates`
- `synth.globalPeople`
- `mcpHttpBridgeEnabled`
- `kiroCliPath`
- `backlinksExpanded`
- `relatedNotesExpanded`
- `hideSyntax` (currently present in settings)
- font candidate keys from `Theme`

### 9.3 Runtime Lease Storage
- MCP lease files must be written under:
  - `~/Library/Application Support/Synth/mcp-runtime/`

## 10. Command and Shortcut Requirements
- `Cmd+N`: New Draft
- `Cmd+O`: Open Workspace
- `Cmd+S`: Save
- `Cmd+W`: Close Tab
- `Cmd+\\`: Toggle Sidebar
- `Cmd+P`: File Launcher
- `Cmd+Shift+T`: Tag Browser
- `Cmd+Shift+P`: People Browser
- `Cmd+Shift+B`: Toggle Backlinks
- `Cmd+D`: Daily Notes
- `Cmd+J`: Toggle Chat
- `Ctrl+\``: Alternate chat toggle
- `Cmd+1...9`: Switch tabs
- `Cmd+Shift+M`: New Meeting Note
- `Cmd+Shift+L`: Global Link Capture
- `Opt+Cmd+1...9`: Template insertion (if slot assigned)

## 11. Known Gaps / Constraints in Current Baseline
- GAP-001: `hideSyntax` setting is exposed but not currently wired to rendering behavior in current code state.
- GAP-002: Rust FFI exports exist and are linked, but no active Swift call sites use them in current baseline.
- GAP-003: Some behavior is preference-driven but lacks explicit UI discoverability (for example durable MCP HTTP bridge implications).

## 12. Acceptance Criteria (Baseline Verification)
- AC-001: App builds successfully for macOS target.
- AC-002: Workspace open -> file tree/indexes/watcher/MCP setup path executes without crashes.
- AC-003: Markdown editor preserves round-trip markdown for links/tags/mentions/images/bullets.
- AC-004: Wiki/date/tag/person/template autocomplete flows function end-to-end.
- AC-005: Daily notes timeline edits persist and calendar date navigation works.
- AC-006: Backlinks and related notes render and navigate correctly.
- AC-007: Launcher query filters (`tag:`, `person:`, `path:`, quotes) produce expected ranked results.
- AC-008: Chat tray can connect to ACP, stream responses, and process permission requests.
- AC-009: Delete and MCP path safety checks prevent operations outside workspace/media bounds.

---

This document is an as-built requirements baseline for the current Synth codebase and should be updated whenever behavior changes in `SynthApp/`, `synth-mcp-server/`, or persistence conventions.
