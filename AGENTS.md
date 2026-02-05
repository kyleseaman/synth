# AGENTS.md

## Project Overview
Synth is a minimal, fast, native macOS text editor with AI integration. SwiftUI frontend, Rust core.

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
