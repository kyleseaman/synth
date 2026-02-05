# Code Conventions

## Defensive Coding

All code changes must pass pre-commit hooks before committing. The hooks run:
- `cargo fmt --check` for Rust
- `swiftlint` for Swift

If a commit fails, fix the issues first. Never bypass hooks with `--no-verify`.

## Swift Style

- Use descriptive variable names (3+ characters). Avoid `i`, `x`, `a`, `b`.
- Prefer `index`, `offset`, `first`, `second` instead.
- No force unwrapping (`!`) or force try (`try!`) without explicit disable comment.
- Keep lines under 120 characters.
- Use trailing closure syntax.
- Group related properties and methods with `// MARK:` comments.

## Rust Style

- Run `cargo fmt` before committing.
- Use `Result` and `Option` properly—avoid `.unwrap()` in library code.
- Document public FFI functions with `///` comments.
- Keep unsafe blocks minimal and well-documented.

## Git Workflow

- Commit early and often.
- Use conventional commit messages: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.
- Never push directly—all changes go through commits locally.
- Build and verify before committing.
- Fix ALL linter warnings before committing, including pre-existing ones in files you didn't modify.

## Testing

- Write tests for new functionality.
- Run `cargo test` for Rust changes.
- Ensure the app builds and runs after changes.
- Write tests first, then implementation. Tests prevent hallucination and scope drift.
