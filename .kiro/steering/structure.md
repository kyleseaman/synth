# Project Structure

```
synth/
├── .kiro/
│   ├── agents/                    # Custom Kiro agents
│   │   ├── synth-editor.json
│   │   ├── synth-writer.json
│   │   └── synth-researcher.json
│   └── steering/                  # Project context for Kiro
├── SynthApp/                      # Swift/SwiftUI frontend (~30 files)
│   ├── SynthApp.swift             # App entry point, keyboard shortcuts
│   ├── ContentView.swift          # Main NavigationSplitView, tabs, modals
│   ├── DocumentStore.swift        # Central state management
│   ├── Document.swift             # File model (load/save)
│   ├── MarkdownEditor.swift       # FormattingTextView with live markdown
│   ├── DailyNotesView.swift       # Chronological daily notes scroll
│   ├── DailyNoteManager.swift     # Daily note lifecycle management
│   ├── CalendarSidebarView.swift  # Calendar widget for daily notes
│   ├── DailyNoteResolver.swift    # Daily note file resolution
│   ├── NoteIndex.swift            # Full-text search index
│   ├── BacklinkIndex.swift        # Wiki link tracking
│   ├── TagIndex.swift             # Tag aggregation
│   ├── PeopleIndex.swift          # @mention tracking
│   ├── FileLauncher.swift         # Cmd+P fuzzy file search
│   ├── BacklinksView.swift        # Right sidebar backlinks
│   ├── LinksView.swift            # Captured links view
│   ├── ACPClient.swift            # Kiro CLI JSON-RPC client
│   └── ...
├── synth-core/                    # Rust core library
│   ├── src/lib.rs                 # FFI exports
│   ├── Cargo.toml
│   └── synth_core.h               # C header for Swift bridging
├── Synth.xcodeproj/               # Xcode project (must register new files)
└── scripts/                       # Build scripts
```

## Naming Conventions
- Swift: PascalCase for types, camelCase for functions/variables
- Rust: snake_case for functions/variables, PascalCase for types
- Files: PascalCase for Swift, snake_case for Rust
