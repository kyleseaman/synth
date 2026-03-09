# Agent Changelog

## Email Drag-and-Drop Note Creation

**Feature:** Users can drag `.eml` files onto the editor detail area to automatically create markdown notes from email content.

### Files Added
- `SynthApp/EmailParser.swift` - Pure utility enum that parses `.eml` file content, extracting From, Subject, Date, and plain-text body. Handles single-part emails and multipart MIME (extracts `text/plain` part). Supports folded headers per RFC 2822.
- `SynthAppTests/EmailParserTests.swift` - Tests covering simple emails, multipart MIME emails, missing Subject header, and empty body.

### Files Modified
- `SynthApp/DocumentStore.swift` - Added `newEmailNote(from:)` method in the File Operations extension. Creates an `emails/` subdirectory in the workspace, sanitizes the subject for filename, writes a markdown template with email metadata, and opens the new note.
- `SynthAppTests/DocumentStoreTests.swift` - Added `testNewEmailNoteCreatesFileFromEml` test verifying email note creation in the `emails/` subdirectory with expected content.
- `SynthApp/ContentView.swift` - Added `.dropDestination(for: URL.self)` modifier on the detail column VStack. Accepts `.eml` file drops and calls `store.newEmailNote(from:)`. Shows a dashed accent-color border overlay when an email is being dragged over.
- `Synth.xcodeproj/project.pbxproj` - Registered `EmailParser.swift` and `EmailParserTests.swift` in all 4 required sections (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase).
