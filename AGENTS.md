# AGENTS.md

## Project Overview
Synth is a minimal, fast, native macOS 26 text editor with AI integration. Modern SwiftUI frontend, Rust core.

## Build Commands
```bash
# Rust library
cd synth-core && cargo build --release

# Swift app (from SynthApp/)
swiftc *.swift -import-objc-header BridgingHeader.h -L ../synth-core/target/release -lsynth_core -o Synth
```

## Testing
```bash
# Rust tests
cd synth-core && cargo test

# Build and run app to verify
./SynthApp/Synth
```

Write tests first, then implementation. Tests prevent hallucination and scope drift.

## Code Style

### Swift
- Variable names must be 3+ characters (no `i`, `x`, `a`, `b`)
- Use `index`, `offset`, `first`, `second` instead
- No force unwrap (`!`) or force try (`try!`) without disable comment
- Lines under 120 characters
- Fix ALL swiftlint warnings, not just errors

### Rust
- Run `cargo fmt` before committing
- Avoid `.unwrap()` in library code—use `Result`/`Option`
- Document FFI functions with `///`

## Pre-commit Hooks
Every commit runs:
- `cargo fmt --check` (Rust)
- `swiftlint` (Swift)

**Never bypass with `--no-verify`.** Fix ALL issues first, including pre-existing warnings.

## Commit Messages
Use conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`

## Structure
- `SynthApp/` - Swift/SwiftUI frontend
- `synth-core/` - Rust FFI library
- `.kiro/agents/` - Custom AI agents
- `.kiro/steering/` - Project context

## Architecture Patterns

### Modern SwiftUI (macOS 26)
- All model classes use `@Observable` (never `ObservableObject`/`@Published`)
- Views use `@Environment(Type.self)` (never `@EnvironmentObject`), `@State` (never `@StateObject`), plain `var` for passed-in observables (never `@ObservedObject`)
- Use `@Bindable` when creating `$` bindings to `@Environment`-injected objects
- Use `.fileImporter()` (not NSOpenPanel), `.alert()` (not NSAlert), `@Environment(\.openURL)` (not NSWorkspace.shared.open)
- AppKit exceptions: FormattingTextView (NSTextView) and WikiLinkPopover (NSPopover) only — no SwiftUI equivalents exist

### View Switching
`DocumentStore` uses a `DetailViewMode` enum (`.editor`, `.dailyNotes`, `.links`, `.media`) to control the detail column content. Modal presentation uses an `ActiveModal` enum on DocumentStore.

### UI Events
Direct method calls on `DocumentStore` for all UI events (toggle sidebar, show modals, switch views). NotificationCenter is only used for AppKit↔SwiftUI bridging: wiki link signals between FormattingTextView and AutocompleteCoordinator, `.reloadEditor`, `.showDailyDate`.

### Daily Notes
- Files: `{workspace}/daily/YYYY-MM-DD.md`
- `DailyNoteManager` scans 30 past + 7 future days, auto-creates today+7 on workspace load
- Virtual notes materialized on first edit
- Each day uses bare `FormattingTextView` (no NSScrollView wrapper) inside a SwiftUI ScrollView to avoid nested scroll issues
- Debounced 1s auto-save; `dailyNoteManager.saveAll()` called in `DocumentStore.saveAll()` for app deactivation safety

### Xcode Project
New Swift files must be added to `Synth.xcodeproj/project.pbxproj` in 4 sections: PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase. SourceKit "Cannot find type in scope" errors usually mean the file isn't in the Xcode project.

### Key Files
- `ContentView.swift` — Main NavigationSplitView, tab bar, modals, ~600 lines
- `DocumentStore.swift` — Central state, indexes, file ops, ~460 lines
- `MarkdownEditor.swift` — FormattingTextView (NSTextView subclass) with live markdown, wiki links, @mentions, ~1200 lines
- `DailyNotesView.swift` — Chronological daily notes + inline editors
- `DailyNoteManager.swift` — Daily note lifecycle management
- `CalendarSidebarView.swift` — Month calendar widget
- `DailyNoteResolver.swift` — Daily note file resolution
