# Agent Changelog

## Markdown Table Rendering Support

**Feature:** Live markdown table rendering with monospace font styling, bold headers, dimmed separators/pipes, Tab/Shift+Tab cell navigation, and Cmd+Option+T table insertion.

### Files Added
- `SynthApp/TableNavigator.swift` - Pure utility enum providing table row/separator detection, column counting, cell navigation (next/previous), row generation, and table template creation. Uses precompiled regex patterns.
- `SynthAppTests/TableSupportTests.swift` - Tests covering table row detection, separator detection, column counting, template generation, new row generation, cell navigation (next/previous), and rendering pattern verification.

### Files Modified
- `SynthApp/MarkdownFormat.swift` - Added `tableRowPattern`, `separatorRowPattern`, and `pipePattern` static regex properties. Updated `render()` to detect table blocks (header + separator + data rows) and apply monospace font, bold headers, dimmed separators, and dimmed pipe characters.
- `SynthApp/MarkdownEditor.swift` - Added `formatTableBlock()` method to the Coordinator for incremental table formatting. Updated `formatRange()` to call `formatTableBlock()` before inline formatting. Updated `formatInlineMarkdown()` to skip table ranges. Updated `insertTab()` and `insertBacktab()` to support table cell navigation with Tab/Shift+Tab, including new row insertion at table end.
- `SynthApp/ContentView.swift` - Added `.insertTableNow` notification name to `Notification.Name` extension.
- `SynthApp/SynthApp.swift` - Added "Insert Table" button with Cmd+Option+T keyboard shortcut in the commands section.
- `SynthApp/AutocompleteCoordinator.swift` - Added observer for `.insertTableNow` notification and `handleTableInsertion()` method that inserts a 3-column, 2-row table template.
- `Synth.xcodeproj/project.pbxproj` - Registered `TableNavigator.swift` and `TableSupportTests.swift` in all 4 required sections (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase).

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
