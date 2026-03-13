# Agent Changelog

## Find and Replace

**Feature:** Native macOS Find and Replace support using NSTextView's built-in NSTextFinder, with standard keyboard shortcuts (Cmd+F, Cmd+G, Cmd+Shift+G, Cmd+Option+F).

### Files Modified
- `SynthApp/MarkdownEditor.swift` - Enabled `usesFindBar = true` and `isIncrementalSearchingEnabled = true` on FormattingTextView in `makeNSView()`. Set `isFindBarVisible = false` on the NSScrollView as the default hidden state. The find bar renders inside the scroll view automatically.
- `SynthApp/SynthApp.swift` - Added `sendFindPanelAction(tag:)` helper that creates an NSMenuItem with the given tag and sends `performFindPanelAction(_:)` to the first responder. Added a `CommandGroup(after: .textEditing)` with four shortcuts: Find (Cmd+F, tag 1), Find and Replace (Cmd+Option+F, tag 12), Find Next (Cmd+G, tag 2), Find Previous (Cmd+Shift+G, tag 3).
- `Synth.xcodeproj/project.pbxproj` - Registered `FindReplaceTests.swift` in all 4 required sections (PBXBuildFile, PBXFileReference, PBXGroup under SynthAppTests, PBXSourcesBuildPhase for tests) with 7A-prefixed IDs.

### Files Added
- `SynthAppTests/FindReplaceTests.swift` - Tests verifying the NSFindPanelAction tag constants (1, 2, 3, 12) map to the correct find operations and are all distinct.

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
