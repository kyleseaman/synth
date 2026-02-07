# Backlinks, #Tags & Related Notes -- Product Specification

**Feature**: Backlinks display, `#tag` syntax, tag browsing, related notes, broken link detection
**Target**: Synth macOS text editor
**Status**: Draft
**Last updated**: 2026-02-06
**Continues from**: Phase 1 (wiki links, @Today, daily notes -- all shipped)

---

## 1. Overview

Phase 1 delivered `[[wiki link]]` autocomplete, click-to-navigate, `@Today`/`@Yesterday`/`@Tomorrow` daily note references, and the `NoteIndex` for link resolution. This specification extends the linking system with backlinks, inline `#tags`, tag browsing, related notes discovery, and broken link detection -- turning Synth into a full personal knowledge management tool.

### Goals

- Surface reverse connections (backlinks) so users discover relationships between notes
- Add `#tag` syntax for lightweight categorization without file/folder structure
- Provide tag browsing and multi-tag filtering for note discovery
- Algorithmically surface related notes based on shared tags and mutual backlinks
- Detect and visually indicate broken wiki links (references to non-existent notes)
- Maintain Synth's keyboard-driven, distraction-free philosophy

### Non-Goals

- Full graph visualization (deferred to Phase 3)
- Transclusion / block embeds
- Cross-workspace tags or links
- Tag hierarchy / nested tags (e.g., `#project/web`)
- AI-suggested tags or links (deferred to Phase 3)

---

## 2. #Tag Syntax Rules

### 2.1 Format

Tags use the `#` prefix followed by a tag name:

```
#project  #idea  #meeting-notes  #Q4-review  #draft
```

| Rule | Detail |
|------|--------|
| Prefix | `#` character |
| First character after `#` | Must be a letter (a-z, A-Z). `#123` is NOT a tag. |
| Allowed characters | Alphanumeric (a-z, A-Z, 0-9) and hyphens (`-`) |
| Termination | Whitespace, punctuation (except `-`), or end of line |
| Case sensitivity | Case-insensitive for matching and grouping. `#Project` and `#project` resolve to the same tag. |
| Case preservation | The original casing as typed by the user is preserved in the document text. |
| Minimum length | 2 characters after `#` (so `#a` is not a valid tag; `#ab` is) |
| Maximum length | 50 characters after `#` |
| Storage | Inline in document text (plain markdown). No external metadata. |

### 2.2 Regex Pattern

```
(?<![#\w])#([a-zA-Z][a-zA-Z0-9-]{1,49})(?=[^a-zA-Z0-9-]|$)
```

This ensures:
- Not preceded by another `#` or word character (prevents matching `##heading`)
- Starts with a letter after `#`
- Ends at a non-tag character or end of line

### 2.3 Examples

| Input | Is Tag? | Tag Name |
|-------|---------|----------|
| `#project` | Yes | `project` |
| `#meeting-notes` | Yes | `meeting-notes` |
| `#Q4-review` | Yes | `q4-review` (matched case-insensitive) |
| `#123` | No | Starts with digit |
| `#a` | No | Too short (1 char) |
| `##heading` | No | Markdown heading syntax |
| `#project-` | Yes | `project` (trailing hyphen is terminator) |
| `code #draft here` | Yes | `draft` |
| `email@Today` | No | `@` is not `#` -- this is a daily note ref |

### 2.4 Plain Text Round-Trip

Tags are stored as literal `#tag-name` in the `.md` file. The `MarkdownFormat.render()` function applies visual styling at render time. `toPlainText()` preserves the raw `#` syntax. Tags survive round-tripping through any editor.

---

## 3. Tag Autocomplete

### 3.1 Trigger

Typing `#` followed by a letter in the editor triggers the tag autocomplete popup. This reuses the existing `WikiLinkState` state machine pattern on `FormattingTextView`, adding a new state:

```swift
case tagActive(start: Int)  // user typed # followed by a letter
```

The `#` alone does not trigger the popup (to avoid false positives on markdown headings). The popup opens when the character after `#` is a letter (a-z, A-Z).

### 3.2 Popup Behavior

| Property | Value |
|----------|-------|
| Appearance | Reuses `WikiLinkPopover` (NSPopover at cursor position) |
| Width | 280pt (same as wiki link popup) |
| Max visible items | 8 |
| Fuzzy matching | Uses existing `String.fuzzyScore(_:)` from `FileLauncher.swift` |
| Data source | `TagIndex` (new class, see Section 9) |
| Icon | `number` SF Symbol (instead of `doc.text`) |
| Secondary text | Note count for each tag (e.g., "5 notes") |

### 3.3 Keyboard Navigation

| Key | Action |
|-----|--------|
| Arrow Up/Down | Move selection highlight |
| Enter | Insert selected tag, close popup |
| Escape | Dismiss popup, leave raw `#` + typed text as-is |
| Space | Dismiss popup (tag is whatever was typed so far) |
| Backspace past `#` | Dismiss popup |

### 3.4 Create Tag Option

When the typed query does not match any existing tag, a "Create #query" option appears at the bottom of the popup (same pattern as wiki link "Create" option). Selecting it simply closes the popup and leaves the typed `#query` in place -- no file creation needed since tags are inline text.

### 3.5 Dismissal

The popup dismisses when:
- User presses Escape
- User presses Space (tag boundary)
- User types punctuation (tag boundary)
- Cursor moves away from the tag position
- User backspaces past the `#` character

---

## 4. Tag Rendering

### 4.1 Visual Style

Tags render inline in the editor text with distinct styling:

| Property | Value |
|----------|-------|
| Text color | `NSColor.systemTeal` (distinct from wiki link accent blue) |
| Font weight | `.medium` |
| Background | `NSColor.systemTeal.withAlphaComponent(0.1)` (subtle pill) |
| Corner radius | 3pt (on the background) |
| Horizontal padding | 2pt |
| Cursor | Pointing hand on hover |
| `#` prefix | Visible (rendered as part of the tag, e.g., `#project`) |

### 4.2 Rendering Implementation

Add a new regex pass in `MarkdownFormat.applyInlineFormatting`, running after wiki links and @Today but before bold/italic/code:

```
Pass order:
1. Wiki links [[...]]
2. @Today/@Yesterday/@Tomorrow
3. #tags (new)
4. Bold **text**
5. Italic *text*
6. Inline code `text`
```

Tags use a custom `NSAttributedString.Key` (e.g., `.synthTag`) storing the normalized (lowercased) tag name, plus a `synth://tag/<name>` URL in the `.link` attribute for click handling.

### 4.3 Click Behavior

Clicking a rendered tag opens the Tag Browser (Section 7) filtered to that tag. This uses the existing link click handler in the Coordinator, routing `synth://tag/<name>` URLs.

---

## 5. Backlinks Display

### 5.1 Location & Layout

Backlinks appear as a collapsible section at the bottom of the editor view, below the document content. Visually separated by a horizontal divider.

| Property | Value |
|----------|-------|
| Position | Below document content in `EditorViewSimple` |
| Separator | Thin `Divider()` above the section |
| Header | "Backlinks (N)" with disclosure triangle, `.tertiary` color |
| Default state | Collapsed. State persisted via `@AppStorage("backlinksExpanded")`. |
| Max visible | 10 entries before scrolling |
| Empty state | Hidden entirely when 0 backlinks (no empty-state text) |

### 5.2 Backlink Entry

Each backlink entry shows:

| Element | Description |
|---------|-------------|
| Note title | Filename without extension, `.medium` weight, primary color |
| Context snippet | The line containing the `[[Current Note]]` reference, `.caption` style, `.secondary` color. The `[[...]]` portion highlighted with accent color. |
| Click | Opens the linking note in a tab (calls `DocumentStore.open(url:)`) |
| Hover | Subtle background highlight (`Color.accentColor.opacity(0.08)`) |

### 5.3 Data Source: BacklinkIndex

A new `BacklinkIndex` class (see Section 9) provides:

- `links(to noteTitle: String) -> Set<URL>`: All files containing `[[noteTitle]]`
- `snippet(from source: URL, to noteTitle: String) -> String?`: Context line

### 5.4 Update Triggers

| Trigger | Action |
|---------|--------|
| File saved | Incremental update: re-scan saved file's outgoing links (<100ms) |
| Workspace file tree changes | Full rebuild on background thread (<2s for 10,000 notes) |
| File renamed | Full rebuild (rename triggers `loadFileTree()` which triggers rebuild) |
| File deleted | Full rebuild (delete triggers `loadFileTree()` which triggers rebuild) |

### 5.5 Integration with EditorViewSimple

```swift
// In EditorViewSimple body, after MarkdownEditor:
BacklinksSection(
    noteTitle: currentNoteTitle,
    backlinkIndex: store.backlinkIndex,
    noteIndex: store.noteIndex,
    onNavigate: { url in store.open(url) }
)
```

Where `currentNoteTitle` is derived from the current file's name without extension.

---

## 6. Broken Link Detection

### 6.1 Detection

During the wiki link rendering pass in `MarkdownFormat.applyInlineFormatting`, each `[[Note Title]]` is checked against `NoteIndex.findExact()`:

- If `findExact(noteTitle)` returns a result: the note exists, render normally.
- If `findExact(noteTitle)` returns nil: the note does not exist, render as broken link.

### 6.2 Broken Link Visual Style

| Property | Value |
|----------|-------|
| Text color | `NSColor.systemRed` at 80% opacity |
| Underline | `NSUnderlineStyle.patternDash` combined with `.single` |
| Font weight | `.medium` (same as normal wiki links) |
| Cursor | Pointing hand on hover |
| Tooltip | "Note not found -- click to create" (via `.toolTip` attribute) |

### 6.3 Click Behavior

Clicking a broken link triggers the existing `promptCreateNote(title:)` flow in the Coordinator:

1. Show `NSAlert`: "Create 'Note Title'?" with Create/Cancel buttons.
2. On Create: new `.md` file in workspace root with `# Note Title` heading. File opens in a tab.
3. On Create: `loadFileTree()` is called, which triggers `NoteIndex` and `BacklinkIndex` rebuild.
4. The previously broken link re-renders as a normal wiki link on the next render cycle.

### 6.4 NoteIndex Injection

`MarkdownFormat` needs access to `NoteIndex` to check link targets. Add optional properties:

```swift
struct MarkdownFormat: DocumentFormat {
    var noteIndex: NoteIndex?
    // ...
}
```

Pass `noteIndex` from the Coordinator when constructing `MarkdownFormat` for rendering. When `noteIndex` is nil (e.g., during tests), all links render as valid (no broken link detection).

---

## 7. Tag Browser

### 7.1 Access

The Tag Browser is accessible via:

| Method | Detail |
|--------|--------|
| Keyboard shortcut | `Cmd+Shift+T` (registered in `SynthApp.swift`) |
| Clicking a rendered `#tag` in the editor | Opens browser filtered to that tag |
| Notification | `.showTagBrowser` posted via `NotificationCenter` |

### 7.2 UI: Overlay Popup

The Tag Browser follows the `FileLauncher` pattern: a centered overlay in `ContentView` with `showTagBrowser` state. It does NOT use NSPopover (it's a browsing UI, not a cursor-anchored autocomplete).

| Property | Value |
|----------|-------|
| Width | 500pt |
| Max height | 400pt |
| Background | `.ultraThinMaterial` (matches `FileLauncher`) |
| Corner radius | 12pt |
| Shadow | 8pt radius |

### 7.3 Layout

```
+-------------------------------------------+
| Search tags...                        [x] |
|-------------------------------------------|
| All Tags (sorted by note count)           |
|                                           |
| #meeting-notes          12 notes    [x]   |
| #project                 8 notes    [x]   |
| #idea                    5 notes    [x]   |
| #draft                   3 notes          |
| ...                                       |
|-------------------------------------------|
| Filtered Notes (when tags selected):      |
|                                           |
| Meeting with Alex       meeting-notes/    |
| Project Kickoff         projects/         |
| ...                                       |
+-------------------------------------------+
```

### 7.4 Interaction

| Action | Behavior |
|--------|----------|
| Click a tag | Toggle tag filter (add/remove from active filter set) |
| Multiple tags selected | Show notes matching ALL selected tags (intersection) |
| Click `[x]` on active tag | Remove from filter |
| Click a note in filtered list | Open note in editor (calls `DocumentStore.open(url:)`) |
| Search field | Fuzzy filter the tag list itself |
| Escape | Close the tag browser |
| Keyboard | Arrow keys navigate tags, Enter toggles selection |

### 7.5 Multi-Tag Intersection

When multiple tags are selected, the filtered notes list shows only notes that contain ALL selected tags. The note count next to each tag updates to reflect the intersection count.

Example: If `#project` has 8 notes and `#meeting-notes` has 12 notes, selecting both might show 3 notes that have both tags.

---

## 8. Related Notes

### 8.1 Algorithm

Related notes are surfaced below the Backlinks section using a scoring algorithm:

```
relatedness_score = (shared_tags * 2) + (mutual_backlinks * 3)
```

Where:
- **shared_tags**: Number of `#tags` that appear in both the current note and the candidate note.
- **mutual_backlinks**: Number of notes that both the current note and the candidate link to via `[[wiki links]]`, plus cases where one links to the other.

### 8.2 Display

| Property | Value |
|----------|-------|
| Position | Below Backlinks section in `EditorViewSimple` |
| Header | "Related (N)" with disclosure triangle, `.tertiary` color |
| Default state | Collapsed. Persisted via `@AppStorage("relatedExpanded")`. |
| Max entries | 5-8 (configurable, default 5) |
| Minimum score | 2 (notes with score < 2 are not shown) |

### 8.3 Related Note Entry

| Element | Description |
|---------|-------------|
| Note title | Filename without extension, `.medium` weight |
| Reason | Brief explanation: "2 shared tags, 1 mutual link" in `.caption` style, `.secondary` color |
| Click | Opens the note in a tab |

### 8.4 Computation

Related notes are computed lazily when the user expands the "Related" section (not on every file open, since it requires cross-referencing multiple indices). Cached per-note and invalidated when `BacklinkIndex` or `TagIndex` change.

### 8.5 Empty State

If no notes have a relatedness score >= 2, the Related section is hidden entirely (same pattern as Backlinks).

---

## 9. Data Model: New Indices

### 9.1 TagIndex

```swift
class TagIndex: ObservableObject {
    /// Map from normalized tag name -> set of file URLs containing that tag
    @Published private(set) var tagToFiles: [String: Set<URL>] = [:]

    /// Map from file URL -> set of normalized tag names in that file
    private var fileToTags: [URL: Set<String>] = [:]

    /// All known tags sorted by frequency (most used first)
    var allTags: [(name: String, count: Int)]

    /// Full rebuild from workspace file tree
    func rebuild(fileTree: [FileTreeNode])

    /// Incremental update for a single file
    func updateFile(_ url: URL, content: String)

    /// Search tags using fuzzy matching
    func search(_ query: String) -> [(name: String, count: Int)]

    /// Get tags for a specific file
    func tags(for url: URL) -> Set<String>

    /// Get files matching ALL given tags (intersection)
    func files(matchingAll tags: Set<String>) -> Set<URL>
}
```

**Scanning**: Parse each `.md` file using the tag regex from Section 2.2. Extract normalized (lowercased) tag names.

**Rebuild triggers**: Same as `BacklinkIndex` -- full rebuild on workspace changes, incremental on file save.

**Performance**: Tag scanning is simpler than backlink scanning (no context snippets needed). Target: <1 second full rebuild for 10,000 notes.

### 9.2 BacklinkIndex

As designed in the architecture doc (`docs/wiki-links-architecture.md`, Section 7), with these structures:

```swift
class BacklinkIndex: ObservableObject {
    /// note title (lowercased) -> set of file URLs that reference it
    @Published private(set) var incomingLinks: [String: Set<URL>] = [:]

    /// source URL -> set of note titles it links to
    private var outgoingLinks: [URL: Set<String>] = [:]

    /// source URL -> (note title -> context line)
    @Published private(set) var contextSnippets: [URL: [String: String]] = [:]

    func rebuild(fileTree: [FileTreeNode])
    func updateFile(_ url: URL, content: String)
    func links(to noteTitle: String) -> Set<URL>
    func snippet(from source: URL, to noteTitle: String) -> String?
}
```

### 9.3 Integration with DocumentStore

```swift
class DocumentStore: ObservableObject {
    let noteIndex = NoteIndex()       // existing
    let backlinkIndex = BacklinkIndex()  // new
    let tagIndex = TagIndex()            // new

    func loadFileTree() {
        // ... existing file tree scan ...
        // After setting self.fileTree:
        noteIndex.rebuild(from: tree, workspace: workspace)
        let treeSnapshot = tree
        Task.detached(priority: .utility) { [weak self] in
            self?.backlinkIndex.rebuild(fileTree: treeSnapshot)
            self?.tagIndex.rebuild(fileTree: treeSnapshot)
        }
    }

    func save() {
        // ... existing save logic ...
        // After writing file -- incremental updates:
        let content = openFiles[currentIndex].content.string
        let url = openFiles[currentIndex].url
        backlinkIndex.updateFile(url, content: content)
        tagIndex.updateFile(url, content: content)
    }
}
```

---

## 10. User Stories with Acceptance Criteria

### US-B1: View Backlinks for Current Note

**As a** writer using Synth,
**I want to** see which notes link to the note I'm currently editing,
**So that** I can discover connections and navigate my knowledge graph.

**Acceptance Criteria:**
1. A "Backlinks (N)" section appears below the editor content when N > 0.
2. Each backlink entry shows the linking note's title and a context snippet containing the `[[link]]`.
3. Clicking a backlink entry opens the linking note in a tab.
4. The section is collapsible with a disclosure triangle; collapsed/expanded state persists across sessions.
5. Backlinks update within 100ms when a file is saved that adds or removes a `[[link]]` to the current note.
6. The section is hidden entirely when there are 0 backlinks (no empty state shown).
7. For a workspace of 10,000 notes, the backlink index full rebuild completes in under 2 seconds.

### US-B2: Detect and Display Broken Links

**As a** writer,
**I want to** see which wiki links point to non-existent notes,
**So that** I can create missing notes or fix typos in link targets.

**Acceptance Criteria:**
1. `[[Non Existent Note]]` renders with `systemRed` text color at 80% opacity and a dashed underline.
2. Hovering a broken link shows a tooltip: "Note not found -- click to create".
3. Clicking a broken link shows a confirmation dialog: "Create 'Non Existent Note'?" with Create/Cancel.
4. Selecting Create produces a new `.md` file in the workspace root with `# Non Existent Note` heading.
5. After creation, the link immediately re-renders with normal accent color styling (no longer broken).
6. Broken link detection updates when `NoteIndex` rebuilds (on file tree changes or file saves).

### US-B3: Create and Use #Tags

**As a** writer,
**I want to** add `#tags` to my notes for lightweight categorization,
**So that** I can organize and find notes by topic without needing a folder structure.

**Acceptance Criteria:**
1. Typing `#` followed by a letter in the editor triggers a tag autocomplete popup.
2. The popup shows existing tags from the workspace, sorted by usage frequency, filtered by fuzzy match.
3. Each popup entry shows the tag name and the number of notes containing it.
4. Pressing Enter inserts the selected tag; pressing Escape dismisses without inserting.
5. Tags render inline with teal color and a subtle teal background pill.
6. Tags are stored as literal `#tag-name` in the markdown source (plain text round-trip safe).
7. `#123`, `#a`, and `##heading` are NOT recognized as tags.
8. Tags are matched case-insensitively: `#Project` and `#project` are the same tag.

### US-B4: Browse Tags

**As a** writer,
**I want to** browse all tags in my workspace and see which notes contain them,
**So that** I can explore my notes by topic.

**Acceptance Criteria:**
1. Pressing `Cmd+Shift+T` opens a Tag Browser overlay.
2. The browser lists all tags with their note counts, sorted by frequency (most used first).
3. Clicking a tag filters the note list to show only notes containing that tag.
4. Selecting multiple tags shows notes matching ALL selected tags (intersection).
5. A search field at the top fuzzy-filters the tag list.
6. Clicking a note in the filtered list opens it in the editor.
7. Pressing Escape closes the Tag Browser.
8. Clicking a rendered `#tag` in the editor opens the Tag Browser filtered to that tag.

### US-B5: View Related Notes

**As a** writer,
**I want to** see notes that are related to the one I'm editing,
**So that** I can discover relevant content I may have forgotten about.

**Acceptance Criteria:**
1. A "Related (N)" section appears below the Backlinks section.
2. Related notes are scored: `(shared tags x 2) + (mutual backlinks x 3)`.
3. Only notes with score >= 2 are shown. If none qualify, the section is hidden.
4. Each entry shows the note title and a brief reason (e.g., "2 shared tags, 1 mutual link").
5. Clicking a related note opens it in a tab.
6. Up to 5 related notes are shown by default.
7. The section is collapsible; collapsed/expanded state persists.
8. Related notes update when the user expands the section (lazy computation).

### US-B6: Rename Note with Reference Updates

**As a** writer,
**I want to** rename a note and have all `[[wiki links]]` pointing to it update automatically,
**So that** my links don't break when I reorganize.

**Acceptance Criteria:**
1. Renaming a note via the sidebar context menu scans for `[[Old Name]]` references across all workspace `.md` files.
2. If references exist, a dialog shows: "Update N reference(s) from [[Old Name]] to [[New Name]]?" with Update All / Skip.
3. Selecting Update All replaces all occurrences of `[[Old Name]]` with `[[New Name]]` across the workspace.
4. Alias forms `[[Old Name|display]]` are updated to `[[New Name|display]]`.
5. Open files with updated references are reloaded in their tabs.
6. BacklinkIndex and NoteIndex rebuild after the rename completes.

---

## 11. Edge Cases

### 11.1 Renamed Notes

- **Via sidebar context menu**: Triggers reference update prompt (US-B6).
- **Via Finder (external)**: Detected on next `loadFileTree()` (file watcher). Old links render as broken until manually updated. No automatic prompt.
- **Rename to existing name**: Prevented by FileManager (file already exists error). User sees no change.

### 11.2 Deleted Notes

- All `[[Deleted Note]]` references render as broken links on next render cycle.
- No automatic cleanup of references. User must manually remove or update them.
- Backlinks and tags for the deleted note are removed from indices on next `loadFileTree()`.

### 11.3 Circular Backlinks

- Note A links to Note B, and Note B links to Note A.
- Both notes show the other in their Backlinks section. This is correct and expected.
- Related Notes algorithm handles this naturally (mutual backlinks score +3 each).

### 11.4 Self-References

- A note linking to itself (`[[This Note]]` inside `This Note.md`) is valid.
- The self-link renders with muted styling (lighter accent color, per existing Phase 1 design).
- The note does NOT appear in its own Backlinks section (filtered out).
- The note does NOT appear in its own Related Notes section (filtered out).

### 11.5 Empty Tags

- `#` followed by a space or punctuation is not a tag (ignored by regex).
- `#` at end of line is not a tag.
- A note that previously had tags but was edited to remove them: `TagIndex.updateFile()` clears the old tags.

### 11.6 Very Long Tag Lists

- Notes with >50 tags: all render correctly but may cause visual clutter. No limit enforced.
- Workspace with >500 distinct tags: Tag Browser uses scrolling. Fuzzy search helps with discovery.
- TagIndex performance: scanning 10,000 files with avg 5 tags each should complete <1 second.

### 11.7 Tags in Code Blocks

- Tags inside inline code (`` `#not-a-tag` ``) or fenced code blocks should NOT be recognized.
- Implementation: the tag regex pass runs after inline code pass, so code-formatted text has already been replaced. However, since code pass runs AFTER tags in the current ordering, we must handle this differently.
- Solution: The tag regex pass should skip ranges that are inside backtick-delimited spans. Check if the match position falls within a code span by scanning for balanced backticks.
- Alternative (simpler): Move inline code pass before tags. Ordering becomes: wiki links, @dates, inline code, #tags, bold, italic. This requires the inline code pass to protect its ranges from subsequent passes.

### 11.8 Tags in Headings

- `# Heading with #tag` -- the `#` at the start is a heading marker. The `#tag` later in the line IS a valid tag.
- `## #tag-heading` -- the `##` is heading syntax. `#tag-heading` after the space IS a valid tag.
- The heading prefix stripping in `MarkdownFormat.render()` already removes `# `/`## `/`### ` before `applyInlineFormatting` runs, so tags in heading content are detected correctly.

### 11.9 Backlinks for Daily Notes

- Daily notes (`daily/2026-02-06.md`) can receive backlinks like any other note.
- Links stored as `[[daily/2026-02-06]]` are indexed with the full path as the link target.
- BacklinkIndex must handle path-based link targets: `links(to: "daily/2026-02-06")`.

### 11.10 Concurrent Index Updates

- Full rebuilds run on `Task.detached(priority: .utility)` (background thread).
- Incremental updates run on the main thread (they are fast, <100ms).
- If an incremental update arrives while a full rebuild is in progress, the incremental update is applied to the in-memory state. The full rebuild will overwrite when it completes. This is acceptable because the full rebuild produces a complete, correct state.

---

## 12. Phasing

All phases build on the completed Phase 1 (wiki links, @Today, daily notes, NoteIndex, WikiLinkPopover).

### Phase 2A: BacklinkIndex + Backlinks UI

**Scope**:
- New file: `BacklinkIndex.swift` -- full and incremental rebuild, context snippets
- New file: `BacklinksSection.swift` -- SwiftUI view for collapsible backlinks display
- Modified: `DocumentStore.swift` -- add `backlinkIndex` property, wire rebuild into `loadFileTree()` and `save()`
- Modified: `ContentView.swift` (`EditorViewSimple`) -- add `BacklinksSection` below `MarkdownEditor`

**Dependencies**: None (uses existing `NoteIndex` and file tree infrastructure).

**Estimated complexity**: Medium.

### Phase 2B: Broken Link Detection

**Scope**:
- Modified: `MarkdownEditor.swift` (`MarkdownFormat`) -- add `noteIndex` property, check each `[[link]]` against `noteIndex.findExact()` during rendering
- Modified: `MarkdownEditor.swift` (Coordinator) -- pass `noteIndex` when constructing `MarkdownFormat`; update `promptCreateNote` to handle the create-and-refresh flow
- Modified: `MarkdownEditor.swift` (`MarkdownEditor` struct) -- pass `noteIndex` through from `store`

**Dependencies**: Phase 2A (BacklinkIndex for post-creation rebuild). Can technically be done in parallel with 2A.

**Estimated complexity**: Low-Medium.

### Phase 2C: #Tag Rendering + Autocomplete + TagIndex

**Scope**:
- New file: `TagIndex.swift` -- tag scanning, search, per-file tag lookup
- Modified: `MarkdownEditor.swift` (`WikiLinkState`) -- add `.tagActive(start:)` state
- Modified: `MarkdownEditor.swift` (`FormattingTextView`) -- detect `#` + letter trigger in `insertText`, update state machine
- Modified: `MarkdownEditor.swift` (`MarkdownFormat`) -- add tag regex pass in `applyInlineFormatting`
- Modified: `MarkdownEditor.swift` (Coordinator) -- handle `synth://tag/<name>` URLs in click handler, wire tag autocomplete to `WikiLinkPopover`
- Modified: `WikiLinkPopover.swift` -- support `mode: "tag"` with tag-specific icon and secondary text
- Modified: `DocumentStore.swift` -- add `tagIndex` property, wire rebuild into `loadFileTree()` and `save()`
- Modified: `ContentView.swift` -- add `.synthTag` notification name if needed

**Dependencies**: None (independent of Phases 2A/2B).

**Estimated complexity**: Medium-High (state machine changes, new index, rendering pass).

### Phase 2D: Tag Browser

**Scope**:
- New file: `TagBrowser.swift` -- SwiftUI overlay view with tag list, multi-select filtering, note list
- Modified: `ContentView.swift` -- add `showTagBrowser` state, overlay, `.onReceive` for `.showTagBrowser` notification
- Modified: `SynthApp.swift` -- register `Cmd+Shift+T` keyboard shortcut
- Modified: `MarkdownEditor.swift` (Coordinator) -- post `.showTagBrowser` notification on `synth://tag/<name>` click

**Dependencies**: Phase 2C (`TagIndex` must exist).

**Estimated complexity**: Medium (new UI component, but follows existing `FileLauncher` pattern).

### Phase 2E: Related Notes

**Scope**:
- New file: `RelatedNotesSection.swift` -- SwiftUI view, scoring algorithm, lazy computation
- Modified: `ContentView.swift` (`EditorViewSimple`) -- add `RelatedNotesSection` below `BacklinksSection`

**Dependencies**: Phases 2A (BacklinkIndex) and 2C (TagIndex). Both indices must be available.

**Estimated complexity**: Medium (algorithm is straightforward; UI follows BacklinksSection pattern).

### Phase 3 (Future)

- **Rename refactoring**: Prompt user to update `[[Old Name]]` references across workspace on rename.
- **Graph view**: Visual node-and-edge graph of note connections (wiki links + tags).
- **Unlinked mentions**: Detect text matching note titles that is not wrapped in `[[]]`; offer to link.
- **AI-suggested links**: Use AI to suggest related notes or tags.

---

## 13. New Files Summary

| File | Purpose | Phase |
|------|---------|-------|
| `SynthApp/BacklinkIndex.swift` | Backlink scanning, incoming/outgoing link tracking, context snippets | 2A |
| `SynthApp/BacklinksSection.swift` | Collapsible backlinks UI below editor | 2A |
| `SynthApp/TagIndex.swift` | Tag scanning, search, per-file tag lookup, multi-tag filtering | 2C |
| `SynthApp/TagBrowser.swift` | Tag browsing overlay with multi-tag intersection filtering | 2D |
| `SynthApp/RelatedNotesSection.swift` | Related notes scoring, display below backlinks | 2E |

## 14. Modified Files Summary

| File | Changes | Phase(s) |
|------|---------|----------|
| `DocumentStore.swift` | Add `backlinkIndex`, `tagIndex` properties; wire rebuild/incremental into `loadFileTree()`/`save()` | 2A, 2C |
| `MarkdownEditor.swift` (MarkdownFormat) | Add `noteIndex` property for broken link detection; add tag regex pass | 2B, 2C |
| `MarkdownEditor.swift` (WikiLinkState) | Add `.tagActive(start:)` case | 2C |
| `MarkdownEditor.swift` (FormattingTextView) | Detect `#` + letter trigger; handle tag popup dismiss on space/punctuation | 2C |
| `MarkdownEditor.swift` (Coordinator) | Pass `noteIndex` to MarkdownFormat; handle `synth://tag/` URLs; tag autocomplete wiring | 2B, 2C |
| `WikiLinkPopover.swift` | Support `mode: "tag"` with tag icon and note count | 2C |
| `ContentView.swift` | Add `BacklinksSection` and `RelatedNotesSection` to `EditorViewSimple`; add `showTagBrowser` overlay | 2A, 2D, 2E |
| `SynthApp.swift` | Register `Cmd+Shift+T` shortcut | 2D |

---

## 15. Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| BacklinkIndex full rebuild | <2 seconds | 10,000 notes, background thread |
| BacklinkIndex incremental (single file) | <100ms | Main thread |
| TagIndex full rebuild | <1 second | 10,000 notes, background thread |
| TagIndex incremental (single file) | <50ms | Main thread |
| Tag autocomplete popup appearance | <50ms | After typing `#` + letter |
| Tag fuzzy search | <16ms | One frame for 10,000 notes |
| Related notes computation | <200ms | Lazy, on expand |
| Broken link check per wiki link | <1ms | Hash lookup in NoteIndex |

---

## 16. Accessibility

- Backlinks section exposes `NSAccessibility` list role; each entry is a link.
- Tag Browser is keyboard-navigable: arrow keys move between tags, Enter toggles selection, Escape closes.
- Tags in the editor expose accessibility label: "Tag: project" (readable by screen readers).
- Related Notes section follows same accessibility patterns as Backlinks.
- All new UI components support VoiceOver navigation.

---

## 17. Open Questions

1. **Should tags support nesting?** (e.g., `#project/web`). Recommendation: Defer. Flat tags with hyphens (`#project-web`) cover most use cases.

2. **Should the Tag Browser show in the sidebar instead of an overlay?** Recommendation: Start with overlay (matches FileLauncher pattern). Consider sidebar tab in Phase 3 if users want persistent tag navigation.

3. **Should Related Notes use AI for similarity scoring?** Recommendation: Defer to Phase 3. The tag+backlink algorithm is deterministic and fast. AI scoring adds latency and API dependency.

4. **Should backlinks include `.txt` files?** Recommendation: Yes. The existing `NoteIndex` already indexes `.txt` files. `BacklinkIndex` should scan both `.md` and `.txt` for `[[...]]` patterns.

5. **Maximum number of related notes to show?** Recommendation: Default 5, max 8. Configurable in a future Settings panel.
