# Synth

AI-first collaborative text editor for macOS, powered by Kiro CLI.

## Structure

```
synth/
├── .kiro/
│   └── agents/
│       ├── synth-editor.json   # Editing assistance
│       └── synth-writer.json   # Content generation
├── SynthApp/                   # Swift/AppKit frontend
│   ├── main.swift
│   └── BridgingHeader.h
└── synth-core/                 # Rust core library
    ├── src/lib.rs
    ├── Cargo.toml
    └── synth_core.h
```

## Agents

**synth-editor** - Document editing assistant
- Grammar, spelling, punctuation fixes
- Restructuring and reformatting
- Inline suggestions and improvements
- Minimal changes, preserves author voice

**synth-writer** - Content generation
- Draft documents from descriptions
- Expand outlines into prose
- Write in various styles (technical, creative, business)
- Create structured documents

Usage:
```bash
kiro-cli chat --agent synth-editor
kiro-cli chat --agent synth-writer
```

## Build

### 1. Build Rust library

```bash
cd synth-core
cargo build --release
```

### 2. Build Swift app

```bash
cd SynthApp
swiftc main.swift \
  -import-objc-header BridgingHeader.h \
  -L ../synth-core/target/release \
  -I ../synth-core \
  -lsynth_core \
  -o Synth
```

### 3. Run

```bash
./Synth
```

## Features

- [x] Native macOS app (AppKit)
- [x] Open .docx files
- [x] Rich text editing via NSTextView
- [x] Kiro AI integration (Cmd+K)
- [x] Specialized agents (editor, writer)
- [ ] Save .docx
- [ ] Markdown support
- [ ] Streaming AI responses
- [ ] Context-aware AI (selected text, document content)

## AI Integration

Press `Cmd+K` to open the Kiro AI panel. The app invokes `kiro-cli` as a subprocess:

```
kiro-cli chat --no-interactive -a '<your prompt>'
```

Requires `kiro-cli` to be installed and in your PATH.
