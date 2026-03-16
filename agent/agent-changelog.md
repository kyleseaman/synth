# Agent Changelog

## Table Support

**Feature:** Markdown table support with visual rendering, insertion command (Cmd+Option+T), and Tab/Shift+Tab cell navigation.

### Files Added
- `SynthApp/TableNavigator.swift` - Pure enum with static methods for table cell navigation and detection. Includes `isInsideTable()`, `nextCellPosition()`, `previousCellPosition()`, `newRowTemplate()`, `tableColumnCount()`, `isSeparatorRow()`, and `insertionTemplate`. No AppKit dependencies for testability.
- `SynthAppTests/TableSupportTests.swift` - Comprehensive tests covering table detection, column counting, row templates, separator detection, cell navigation (forward/backward/cross-row), insertion template validation, and regex pattern matching.

### Files Modified
- `SynthApp/MarkdownFormat.swift` - Added `tableRowPattern` static regex for detecting table rows. Modified `render()` to detect consecutive table lines and process them as blocks with monospace font, bold headers, and dimmed pipes/separators via new `renderTableBlock()` method. Added helper methods `dimPipeCharacters()` and `boldCellContent()`.
- `SynthApp/MarkdownEditor.swift` - Modified `performKeyEquivalent()` to handle Cmd+Option+T for table insertion. Added `insertTable()` method to FormattingTextView. Updated `insertTab()` and `insertBacktab()` to handle table cell navigation using TableNavigator before falling through to existing bullet-indent behavior. Added `tableBlockRanges` tracking, `findTableBlockRanges()`, `tableBlockContaining()`, and `formatTableBlocks()` in the Coordinator for incremental table formatting as block units.
- `SynthApp/AutocompleteCoordinator.swift` - Added notification observer for `.insertTableNow` that calls `textView.insertTable()`.
- `SynthApp/ContentView.swift` - Added `.insertTableNow` notification name.
- `SynthApp/SynthApp.swift` - Added "Insert Table" command with Cmd+Option+T shortcut that posts `.insertTableNow` notification.
- `Synth.xcodeproj/project.pbxproj` - Registered `TableNavigator.swift` (app sources) and `TableSupportTests.swift` (test sources) in all 4 required sections with 7B-prefixed IDs.

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
