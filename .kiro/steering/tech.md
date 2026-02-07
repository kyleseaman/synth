# Technology Stack

## Frontend
- SwiftUI for UI components
- AppKit bridging for NSTextView and system integration
- macOS 13+ target (macOS 26 Liquid Glass where available)
- NavigationSplitView with sidebar + detail columns
- FormattingTextView (NSTextView subclass) for live markdown rendering

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
- **State management**: DocumentStore (@ObservableObject) is the single source of truth
- **View switching**: Boolean flags on DocumentStore control detail column content
- **Events**: NotificationCenter for cross-component communication
- **Indexes**: NoteIndex, BacklinkIndex, TagIndex, PeopleIndex — all ObservableObjects rebuilt from file tree
- **Editor**: FormattingTextView wraps NSTextView with wiki link state machine, markdown formatting, autocomplete
- **Daily notes**: DailyNoteManager handles file lifecycle with virtual note materialization and debounced auto-save
- **NSTextView in ScrollView**: Use bare NSTextView (no NSScrollView wrapper) when embedding in SwiftUI ScrollView to avoid nested scroll conflicts
