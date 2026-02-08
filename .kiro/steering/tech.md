# Technology Stack

## Frontend
- macOS 26 deployment target — use modern SwiftUI APIs exclusively
- AppKit only for FormattingTextView (NSTextView subclass) and WikiLinkPopover (NSPopover) — no SwiftUI equivalents exist
- NavigationSplitView with sidebar + detail columns
- `@Observable` macro for all model classes (not `ObservableObject`)
- `@Environment(Type.self)` for dependency injection (not `@EnvironmentObject`)
- `.fileImporter()` for file pickers (not NSOpenPanel), `.alert()` for dialogs (not NSAlert)
- `@Environment(\.openURL)` for opening URLs (not NSWorkspace.shared.open)

## Core
- Rust for document processing (synth-core)
- FFI bridge via C headers (synth_core.h)
- docx-rs for Word document handling

## AI Integration
- Kiro CLI subprocess invocation
- Custom agents in `.kiro/agents/`

## Build Tools
- Xcode / swiftc for Swift compilation
- Cargo for Rust builds
- Pre-commit hooks for quality gates (cargo fmt --check, swiftlint)

## Key Patterns
- **State management**: DocumentStore (`@Observable`) is the single source of truth
- **View switching**: `DetailViewMode` enum (`.editor`, `.dailyNotes`, `.links`, `.media`) on DocumentStore controls detail column content
- **Modals**: `ActiveModal` enum on DocumentStore for modal presentation
- **Events**: Direct method calls on DocumentStore for UI events. NotificationCenter only for AppKit↔SwiftUI bridging (wiki link signals, `.reloadEditor`, `.showDailyDate`)
- **Indexes**: NoteIndex, BacklinkIndex, TagIndex, PeopleIndex — all `@Observable` classes rebuilt from file tree
- **Editor**: FormattingTextView wraps NSTextView with wiki link state machine, markdown formatting, autocomplete
- **Daily notes**: DailyNoteManager handles file lifecycle with virtual note materialization and debounced auto-save
- **NSTextView in ScrollView**: Use bare NSTextView (no NSScrollView wrapper) when embedding in SwiftUI ScrollView to avoid nested scroll conflicts
