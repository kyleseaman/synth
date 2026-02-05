# Project Structure

```
synth/
├── .kiro/
│   ├── agents/           # Custom Kiro agents
│   │   ├── synth-editor.json
│   │   └── synth-writer.json
│   └── steering/         # Project context for Kiro
├── SynthApp/             # Swift/SwiftUI frontend
│   ├── SynthApp.swift    # App entry point
│   ├── ContentView.swift # Main view
│   ├── EditorView.swift  # Text editor component
│   ├── Document.swift    # Document model
│   └── ...
├── synth-core/           # Rust core library
│   ├── src/lib.rs        # FFI exports
│   ├── Cargo.toml
│   └── synth_core.h      # C header for Swift bridging
└── scripts/              # Build scripts
```

## Naming Conventions
- Swift: PascalCase for types, camelCase for functions/variables
- Rust: snake_case for functions/variables, PascalCase for types
- Files: PascalCase for Swift, snake_case for Rust
