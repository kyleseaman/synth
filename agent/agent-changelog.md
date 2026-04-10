# Agent Changelog

## BRAD: Hashtag Filter Mode for Search with Graph-Related Notes

**Feature:** Added a hashtag filter mode (codenamed BRAD) to the dedicated search that finds related notes via the knowledge graph. A new keyboard shortcut (Cmd+Shift+H) opens the search tab pre-focused on the tag filter field. When tags are entered, a "Related via Graph" section surfaces notes connected through shared tags, mutual backlinks, and common link targets.

### Files Modified
- `SynthApp/DocumentStore.swift` - Added `searchTagFocusRequested` property (Bool) and `selectSearchTabWithTagFocus()` method that sets `detailMode = .search` and signals the tag field to receive focus.
- `SynthApp/SynthApp.swift` - Added Cmd+Shift+H keyboard shortcut ("Hashtag Search") that calls `store.selectSearchTabWithTagFocus()`.
- `SynthApp/DedicatedSearchView.swift` - Added `HashtagGraphSearch` enum with static `relatedNotes(forTags:tagIndex:backlinkIndex:limit:)` method implementing the graph traversal algorithm (shared tags weight 2, mutual backlinks weight 3, common link targets weight 1, shared incoming sources weight 1). Added `@FocusState` for the tag field, `graphRelatedItems` computed property, "Related via Graph" section in results list, tag focus handling on appear/change, and a `facetField` overload accepting a focus binding.
- `SynthAppTests/UtilityLogicTests.swift` - Added 6 tests for `HashtagGraphSearch`: shared tags, mutual backlinks, common link targets, empty results for unknown tags, limit parameter, and formatReason output.
- `SynthAppTests/DocumentStoreTests.swift` - Added 2 tests for `selectSearchTabWithTagFocus()`: verifying it sets detailMode and the flag, and verifying it requires a workspace.

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
