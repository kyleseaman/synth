# Wiki Links & Daily Notes -- Requirements

## 1. Overview

Add Reflect/Obsidian-style note-to-note linking to Synth, enabling users to create a personal knowledge graph within their workspace. This includes `[[wiki link]]` syntax for linking notes, `@Today` references for daily notes, and a backlinks system for discovering connections.

### Goals

- Let users connect notes with minimal friction (typing `[[` triggers autocomplete)
- Support daily notes via `@Today`, `@Yesterday`, `@Tomorrow` shortcuts
- Surface reverse connections (backlinks) so users discover relationships
- Render wiki links as styled, clickable inline elements in the editor
- Maintain Synth's keyboard-driven, distraction-free philosophy

### Non-Goals (Out of Scope)

- Full graph visualization (node-and-edge graph view)
- Transclusion / block embeds (`![[Note]]` syntax)
- Tags or metadata taxonomy beyond links
- Cross-workspace linking

---

## 2. Existing Architecture Context

Key components that this feature touches:

| Component | File | Role |
|---|---|---|
| Editor | `MarkdownEditor.swift` | NSViewRepresentable wrapping `FormattingTextView` (NSTextView subclass). Handles key events, inline formatting, bullet continuation. |
| Markdown rendering | `MarkdownEditor.swift` (`MarkdownFormat`) | Converts raw markdown to `NSAttributedString`. Currently handles headings, bold, italic, inline code. |
| Document model | `Document.swift` | Load/save logic. Content stored as `NSAttributedString`. Plain text round-tripped for `.md` files. |
| State management | `DocumentStore.swift` | MVVM store. Manages workspace, file tree, open tabs. Has `open(url:)` for navigating to files. |
| File tree | `FileTreeNode.swift` | Recursive workspace scanner. Provides flat list of all files for search. |
| File launcher | `FileLauncher.swift` | Cmd+P fuzzy search popup. Reusable pattern for autocomplete UI (keyboard nav, fuzzy scoring). |
| Link system | `LinkStore.swift`, `LinksView.swift`, `LinkCaptureView.swift` | External URL bookmarking (separate from wiki links). Cmd+Shift+L shortcut. |
| App entry | `SynthApp.swift` | Scene setup, keyboard shortcuts, environment objects. |
| Notifications | `ContentView.swift` | Cross-component communication via `NotificationCenter`. |

### Important Patterns

- **Fuzzy search**: `String.fuzzyScore(_:)` in `FileLauncher.swift` is reusable for wiki link autocomplete.
- **Popup overlay**: `FileLauncher` and `LinkCaptureView` both use the overlay pattern in `ContentView` with `showFileLauncher`/`showLinkCapture` state and `.onReceive` for notifications.
- **Keyboard handling**: `KeyboardHandler` NSViewRepresentable for arrow/escape key interception in popups.
- **Text storage**: The editor stores `NSAttributedString` but round-trips through plain text (`textView.string`) for `.md` files. Wiki link syntax must survive this round-trip.

---

## 3. Feature Requirements

### 3.1 [[Wiki Link]] Autocomplete

#### 3.1.1 Trigger

- Typing `[[` in the editor triggers an autocomplete popup.
- The popup appears anchored to the cursor position (inline, not centered like FileLauncher).
- Only triggers when `[[` is typed as new input, not when navigating into existing `[[` text.

#### 3.1.2 Autocomplete Popup

- Displays a scrollable list of note titles from the workspace file tree.
- Notes are identified by filename without extension (e.g., `Meeting Notes.md` displays as `Meeting Notes`).
- Shows the containing folder as secondary text (like FileLauncher does).
- Supported file types in autocomplete: `.md`, `.txt` (not `.docx` -- wiki linking is markdown-native).
- Maximum 8 visible rows; scrollable if more results.

#### 3.1.3 Fuzzy Search Filtering

- As the user types after `[[`, the query filters the list using fuzzy matching.
- Reuse the existing `String.fuzzyScore(_:)` algorithm from `FileLauncher.swift`.
- Recently opened files get a score boost (same as FileLauncher).
- Empty query shows all notes sorted by recency, then alphabetically.

#### 3.1.4 Keyboard Navigation

- **Up/Down arrows**: Navigate the selection highlight.
- **Enter/Tab**: Accept the selected note, inserting `[[Note Title]]` and closing the popup.
- **Escape**: Dismiss the popup without inserting anything; leave `[[` as typed.
- **Continue typing**: Refines the filter. If no matches remain, popup shows "No matching notes" with an option to create a new note with the typed name.

#### 3.1.5 Mouse Interaction

- Clicking a row selects and inserts it.
- Clicking outside the popup dismisses it.

#### 3.1.6 Create-on-Complete

- If the user types `[[New Note Title]]` (closing brackets manually) and no note with that title exists, the link renders with "broken link" styling.
- Clicking a broken link prompts: "Create 'New Note Title'?" with Create/Cancel buttons.
- Created notes are `.md` files in the workspace root (or same folder as the linking note -- see Section 6.5).
- After creation, the new note opens in a tab.

### 3.2 Single Bracket `[` Behavior

- **Decision: Do NOT support single-bracket linking.** Single `[` is standard markdown link syntax (`[text](url)`) and must not be intercepted.
- The autocomplete popup triggers only on the second `[` character typed immediately after a first `[`.
- If the user types `[` then any non-`[` character, no wiki link behavior activates.

### 3.3 @Today and Date References

#### 3.3.1 @Today Shortcut

- Typing `@Today` (case-insensitive: `@today`, `@TODAY`) in the editor creates a link to today's daily note.
- Rendered inline as a styled link (same accent color as wiki links but with a calendar icon or distinct prefix).
- Clicking navigates to the daily note file.

#### 3.3.2 @Yesterday and @Tomorrow

- `@Yesterday` links to the previous day's daily note.
- `@Tomorrow` links to the next day's daily note.
- Both follow the same rendering and navigation behavior as `@Today`.

#### 3.3.3 @ Trigger Popup

- Typing `@` in the editor triggers a small popup with date shortcut options:
  - Today (YYYY-MM-DD)
  - Yesterday (YYYY-MM-DD)
  - Tomorrow (YYYY-MM-DD)
  - A mini calendar date picker for arbitrary dates
- Arrow keys navigate, Enter selects, Escape dismisses.
- Selecting a date inserts `@YYYY-MM-DD` which links to that day's note.

#### 3.3.4 Daily Notes Folder

- Daily notes live in a `daily/` folder at the workspace root.
- File naming: `YYYY-MM-DD.md` (e.g., `2026-02-06.md`).
- If the daily note does not exist when navigated to, it is auto-created with a template:
  ```markdown
  # February 6, 2026

  ```
- The `daily/` folder is created on first use if it does not exist.

### 3.4 Backlinks

#### 3.4.1 Backlink Index

- Maintain an in-memory index mapping each note to the set of notes that link to it.
- The index is built by scanning all `.md` files in the workspace for `[[...]]` patterns.
- Index rebuilds:
  - Full rebuild on workspace open/change.
  - Incremental update when a file is saved (re-scan that file's outgoing links).

#### 3.4.2 Backlink Display

- Displayed as a collapsible section at the bottom of the editor, below the document content.
- Header: "Backlinks (N)" where N is the count, with a disclosure triangle.
- Each backlink entry shows:
  - The linking note's title (filename without extension).
  - A snippet of surrounding context (the line containing the `[[link]]`).
- Clicking a backlink entry navigates to that note (opens in tab, scrolls to link location if feasible).
- The backlinks section is visually separated from the document (light divider, muted background).
- Default state: collapsed. User preference persisted.

#### 3.4.3 Performance

- For workspaces with up to 10,000 notes, the index must rebuild in under 2 seconds.
- Incremental updates (single file save) must complete in under 100ms.
- Use background thread for full index builds; update UI on main thread.

### 3.5 Visual Rendering

#### 3.5.1 Wiki Link Appearance

- **Existing note**: Rendered with `NSColor.controlAccentColor` foreground, no underline. The `[[` and `]]` delimiters are hidden (display only the note title).
- **Broken link (note does not exist)**: Rendered with `NSColor.systemRed` foreground and a dashed underline.
- **Hover**: Cursor changes to pointing hand (`NSCursor.pointingHand`). A subtle underline appears on hover for existing links.
- **Font**: Same as surrounding text (inherits from line context -- heading, body, etc.).

#### 3.5.2 @ Date Reference Appearance

- Rendered with `NSColor.controlAccentColor` foreground, same as wiki links.
- The `@` prefix is visible (e.g., displays as `@Today` or `@2026-02-06`).
- Hover shows the resolved date as a tooltip (e.g., hovering `@Today` shows "February 6, 2026").

#### 3.5.3 Plain Text Round-Trip

- In the underlying `.md` file, wiki links are stored as `[[Note Title]]` literal text.
- Date references are stored as `@Today`, `@Yesterday`, `@Tomorrow`, or `@YYYY-MM-DD` literal text.
- The `MarkdownFormat.render()` function applies styling on load; `toPlainText()` preserves the raw syntax.
- This ensures files are portable and readable in other editors.

### 3.6 Link Navigation

#### 3.6.1 Click to Navigate

- Clicking a wiki link calls `DocumentStore.open(url:)` for the linked note's URL.
- If the note is already open in a tab, switch to that tab.
- If not open, load and open in a new tab.

#### 3.6.2 Cmd+Click

- Cmd+Click on a wiki link opens the note in a new tab without switching to it (background open).
- This mirrors standard macOS link behavior.

#### 3.6.3 Resolution

- Link resolution: match `[[Note Title]]` to a file named `Note Title.md` (or `Note Title.txt`) in the workspace.
- Search is case-insensitive on macOS (APFS is case-insensitive by default).
- If multiple files match (e.g., `note.md` and `Note.md`), prefer the exact-case match, then the most recently modified.
- Search includes all subdirectories of the workspace (not just root).

---

## 4. @Today / Date Reference Details

### 4.1 Date Resolution

| Token | Resolves To |
|---|---|
| `@Today` | Current date at render time |
| `@Yesterday` | Current date minus 1 day |
| `@Tomorrow` | Current date plus 1 day |
| `@YYYY-MM-DD` | The literal date specified |

- Named tokens (`@Today`, etc.) re-resolve each time the document is opened/rendered. A note written on Monday with `@Today` will show Monday's date on Monday and Tuesday's date on Tuesday.
- Explicit date tokens (`@2026-02-06`) always point to that fixed date.

### 4.2 Persistence

- In the `.md` file, `@Today` is stored literally as `@Today` (not resolved to a date).
- `@YYYY-MM-DD` is stored as-is.
- Resolution happens at render time only.

---

## 5. Backlink Index Design

### 5.1 Data Structure

```
WikiLinkIndex:
  outgoingLinks: [URL: Set<String>]    // file -> set of note titles it links to
  incomingLinks: [String: Set<URL>]    // note title -> set of files linking to it
  contextSnippets: [URL: [String: String]]  // file -> (note title -> context line)
```

### 5.2 Scanning

- Parse each `.md` file for `\[\[(.+?)\]\]` regex matches.
- Extract the inner text as the linked note title.
- Store the line containing the link as context snippet.

### 5.3 Rebuild Triggers

- **Full rebuild**: Workspace opened, workspace changed, app launch with persisted workspace.
- **Incremental**: File saved (remove old outgoing links for that file, re-scan, update incoming).
- **File renamed**: Update all entries referencing the old filename (see Section 6.1).
- **File deleted**: Remove from index, mark incoming links as broken.

---

## 6. Edge Cases

### 6.1 Renamed Notes

- When a note is renamed via the file tree context menu (`DocumentStore.promptRename`):
  - Scan all `.md` files for `[[Old Name]]` references.
  - Prompt the user: "Update N references from [[Old Name]] to [[New Name]]?" with Update All / Skip options.
  - If accepted, perform find-and-replace across the workspace.
  - Update the backlink index.
- Renaming via Finder (external) is detected on the next file tree refresh. Broken links appear with red styling until manually updated.

### 6.2 Deleted Notes

- Deleting a note (`DocumentStore.delete`) triggers a backlink index update.
- All `[[Deleted Note]]` references across the workspace switch to broken-link styling on next render.
- No automatic cleanup of references (user must manually update or remove them).

### 6.3 Case Sensitivity

- Link matching is **case-insensitive** (consistent with macOS APFS default behavior).
- `[[meeting notes]]` matches `Meeting Notes.md`.
- Display the link using the case as typed by the user; resolve to the actual filename.

### 6.4 Special Characters in Titles

- Note titles may contain any characters valid in macOS filenames.
- The following characters are stripped/escaped when creating new notes from links: `:`, `/`, `\` (filesystem-illegal).
- Pipe `|` inside wiki links is reserved for display aliases: `[[Actual Title|Display Text]]` renders as "Display Text" but links to "Actual Title".

### 6.5 Nested Folders / Subdirectories

- Wiki links resolve by searching the entire workspace recursively, not just the root.
- If a note title is ambiguous (exists in multiple folders), resolution priority:
  1. Same folder as the linking note.
  2. Workspace root.
  3. Alphabetically first by path.
- Users can disambiguate with path syntax: `[[subfolder/Note Title]]`.
- The autocomplete popup shows the containing folder to help users pick the right note.

### 6.6 Self-Links

- A note linking to itself (`[[This Note]]` inside `This Note.md`) is valid but renders with muted styling (lighter accent color). Clicking it is a no-op (already viewing that note).

### 6.7 Links in Non-Markdown Files

- `.txt` files: Wiki link syntax is recognized and clickable but rendered with monospace font (no rich styling).
- `.docx` files: Wiki links are **not supported** (OOXML format cannot store wiki syntax portably).

### 6.8 Empty or Whitespace-Only Links

- `[[]]` or `[[   ]]` are ignored (not treated as links, rendered as literal text).

### 6.9 Nested Brackets

- `[[ [[inner]] ]]` -- the parser matches the first valid close: `[[ [[inner]]`. The outer `]]` is treated as literal text. This is consistent with Obsidian behavior.

---

## 7. User Stories with Acceptance Criteria

### US-1: Create a Wiki Link via Autocomplete

**As a** writer using Synth,
**I want to** type `[[` and see a list of my notes,
**So that** I can quickly link related ideas together.

**Acceptance Criteria:**
1. Typing `[[` in the editor shows an autocomplete popup anchored near the cursor.
2. The popup lists all `.md` and `.txt` files in the workspace by title (filename without extension).
3. Typing additional characters filters the list using fuzzy matching.
4. Pressing Enter inserts `[[Selected Note Title]]` at the cursor position.
5. Pressing Escape dismisses the popup and leaves `[[` as-is.
6. The popup disappears after selection or dismissal.

### US-2: Navigate to a Linked Note

**As a** writer,
**I want to** click a wiki link to open the linked note,
**So that** I can quickly jump between related notes.

**Acceptance Criteria:**
1. Wiki links render with accent color and no visible `[[`/`]]` delimiters.
2. Hovering over a wiki link shows a pointing-hand cursor.
3. Clicking a wiki link opens the target note in a tab (or switches to it if already open).
4. Cmd+clicking opens the note in a background tab.
5. If the target note does not exist, clicking shows a "Create note?" prompt.

### US-3: See Broken Links

**As a** writer,
**I want to** see which links point to non-existent notes,
**So that** I can create missing notes or fix typos.

**Acceptance Criteria:**
1. Links to non-existent notes render in red with a dashed underline.
2. Clicking a broken link offers to create the note.
3. After creating the note, the link styling updates to the normal accent color.

### US-4: Use @Today to Create a Daily Note

**As a** writer,
**I want to** type `@Today` to link to today's daily note,
**So that** I can quickly reference my daily journal.

**Acceptance Criteria:**
1. `@Today` renders as a clickable link with accent color styling.
2. Clicking `@Today` opens (or creates) `daily/YYYY-MM-DD.md` for the current date.
3. The daily note is created with a heading template if it does not exist.
4. `@Yesterday` and `@Tomorrow` work analogously for adjacent dates.
5. Hovering shows the resolved date as a tooltip.

### US-5: Use the @ Date Picker

**As a** writer,
**I want to** type `@` and pick a date from a popup,
**So that** I can link to daily notes for any date.

**Acceptance Criteria:**
1. Typing `@` shows a popup with Today, Yesterday, Tomorrow, and a calendar.
2. Selecting a date inserts `@YYYY-MM-DD` at the cursor.
3. Arrow keys navigate, Enter selects, Escape dismisses.
4. The inserted date reference is a clickable link to that day's note.

### US-6: View Backlinks

**As a** writer,
**I want to** see which notes link to the current note,
**So that** I can discover connections and navigate my knowledge graph.

**Acceptance Criteria:**
1. A "Backlinks (N)" section appears below the editor content.
2. Each backlink shows the linking note title and a context snippet.
3. Clicking a backlink opens the linking note.
4. The section is collapsible and remembers its state.
5. Backlinks update when files are saved.

### US-7: Rename a Note and Update Links

**As a** writer,
**I want to** rename a note and have all wiki links pointing to it update automatically,
**So that** my links don't break when I reorganize.

**Acceptance Criteria:**
1. Renaming a note via the context menu scans for `[[Old Name]]` references.
2. A prompt shows the count of references and offers to update them.
3. Accepting updates all references to `[[New Name]]` across the workspace.
4. The backlink index updates accordingly.

### US-8: Create a New Note from a Link

**As a** writer,
**I want to** type `[[New Topic]]` for a note that doesn't exist yet,
**So that** I can capture ideas and create the note later.

**Acceptance Criteria:**
1. Closing `]]` for a non-existent note title renders as a broken link (red, dashed underline).
2. The autocomplete popup offers "Create 'New Topic'" when no matches are found.
3. Selecting the create option creates the `.md` file and opens it.
4. The link immediately updates to normal styling.

---

## 8. Implementation Priority

Recommended build order based on dependencies and user value:

| Phase | Feature | Depends On |
|---|---|---|
| **Phase 1** | Wiki link rendering in `MarkdownFormat` (parse `[[...]]`, apply styling) | -- |
| **Phase 1** | Click-to-navigate for wiki links | Rendering |
| **Phase 2** | `[[` autocomplete popup (trigger, fuzzy search, insert) | Rendering |
| **Phase 2** | Broken link detection and styling | Rendering |
| **Phase 3** | `@Today`/`@Yesterday`/`@Tomorrow` rendering and navigation | Rendering |
| **Phase 3** | Daily notes folder and auto-creation | @Today navigation |
| **Phase 4** | `@` date picker popup | @Today rendering |
| **Phase 5** | Backlink index and display | Rendering, full workspace scan |
| **Phase 6** | Rename refactoring (update links across workspace) | Backlink index |
| **Phase 6** | Create-on-click for broken links | Broken link detection |

---

## 9. Technical Constraints and Decisions

### 9.1 NSTextView and Attributed Strings

- Wiki links are rendered as `NSAttributedString` attributes with a custom key (e.g., `.wikiLink`) storing the target note title.
- Click handling uses `NSTextView.clicked(onLink:at:)` or hit-testing in the coordinator's mouse event handlers.
- The `FormattingTextView` subclass is the right place to add link click handling.

### 9.2 Plain Text Fidelity

- The `.md` file on disk always contains raw `[[Note Title]]` and `@Today` text.
- `MarkdownFormat.render()` adds visual styling; `toPlainText()` strips it.
- This means wiki links survive round-tripping through any text editor.

### 9.3 Autocomplete Popup Positioning

- Unlike `FileLauncher` (centered overlay), the wiki link popup must be positioned at the text cursor.
- Use `NSTextView.firstRect(forCharacterRange:actualRange:)` to get screen-space coordinates for the cursor, then convert to the window's coordinate space for the SwiftUI overlay.

### 9.4 Existing Link System Coexistence

- The existing `LinkStore`/`LinksView`/`LinkCaptureView` system is for external URL bookmarks.
- Wiki links are a separate system for internal note-to-note linking.
- The two systems do not overlap. `[[...]]` is always wiki links; `Cmd+Shift+L` is always external links.
- Future consideration: a unified "Links" panel showing both outgoing wiki links and external links.

### 9.5 Performance Budget

- Autocomplete popup should appear within 50ms of typing `[[`.
- Fuzzy search filtering should complete within 16ms (one frame) for up to 10,000 notes.
- Backlink index full rebuild: under 2 seconds for 10,000 notes.

---

## 10. Open Questions

1. **Alias syntax**: Should `[[Title|Alias]]` be supported from the start, or deferred?
   - Recommendation: Defer to Phase 2+. Keep initial implementation simple.

2. **Header linking**: Should `[[Note#Section]]` deep-link to a heading within a note?
   - Recommendation: Defer. Requires heading parsing and scroll-to behavior.

3. **Unlinked mentions**: Should Synth detect mentions of note titles that are NOT wrapped in `[[]]`?
   - Recommendation: Defer. This is a "nice to have" discovery feature.

4. **Workspace-level settings**: Should there be a setting to disable wiki links per workspace?
   - Recommendation: Not initially. If needed, add to SettingsView later.

5. **Markdown export**: When exporting/sharing, should `[[links]]` be converted to standard markdown links `[Title](path)`?
   - Recommendation: Worth considering for a future export feature.
