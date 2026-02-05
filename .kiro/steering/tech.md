# Technology Stack

## Frontend
- SwiftUI for UI components
- AppKit bridging for NSTextView and system integration
- macOS 13+ target

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
- Pre-commit hooks for quality gates
