# Wiki Links & @Today -- Product Specification

**Feature**: Internal note linking (`[[wiki links]]`) and date references (`@Today`)
**Target**: Synth macOS text editor
**Status**: Draft
**Last updated**: 2026-02-06

---

## 1. Overview

Add the ability to link between notes using `[[wiki link]]` syntax and reference dates with `@Today` shortcuts. These features turn Synth from a standalone editor into a connected knowledge tool where notes reference each other and daily notes serve as a journal/scratch space.

### Goals

- Let users create connections between notes without leaving the editor
- Provide fast, keyboard-driven autocomplete when typing `[[`
- Support daily notes via `@Today`, `@Yesterday`, `@Tomorrow`
- Keep the feature minimal and consistent with Synth's existing UI patterns

### Non-goals (for now)

- Full graph visualization
- Transclusion / embedded note previews
- Bi-directional sync with external tools

---

## 2. Core UX Flows

### 2.1 Inserting a Wiki Link (`[[`)

**Trigger**: User types `[[` anywhere in the editor.

1. The editor detects the `[[` character sequence via `insertText(_:replacementRange:)` in `FormattingTextView`.
2. An autocomplete popup appears anchored below the cursor position.
3. The popup shows all note files in the current workspace, sorted by recency (reusing `DocumentStore.recentFiles` ordering, then alphabetical).
4. As the user continues typing after `[[`, the list filters in real-time using the existing `fuzzyScore` algorithm from `FileLauncher.swift`.
5. The user selects a note via:
   - **Arrow keys** (Up/Down) to move highlight
   - **Enter** or **Tab** to confirm selection
   - **Escape** to dismiss without inserting
   - **Click** on an item
6. On confirmation, the typed text (including `[[` and any filter query) is replaced with `[[Note Name]]`, where "Note Name" is the file name without extension.
7. The link is rendered inline with link styling (see Section 3).
8. If the user closes the brackets manually by typing `]]` without selecting from the popup, the text between the brackets is treated as a link target (matched by filename without extension, case-insensitive).

**Edge cases**:
- If the user types `[[` then immediately `]]`, no link is created (empty link ignored).
- If the user types `[[` and presses Backspace past the second `[`, the popup dismisses.
- Nested brackets are not supported; inner `[` characters are treated as literal text.

### 2.2 Inserting a Date Reference (`@`)

**Trigger**: User types `@` followed by a recognized keyword.

1. The editor detects `@` and shows an autocomplete popup with date options.
2. Available options:
   - **@Today** -- resolves to today's date (e.g., `2026-02-06`)
   - **@Yesterday** -- resolves to yesterday's date
   - **@Tomorrow** -- resolves to tomorrow's date
   - **@Date...** -- future: opens a date picker (Phase 2+)
3. The user types to filter (e.g., `@to` shows "Today" and "Tomorrow").
4. On selection, the `@Keyword` text is replaced with a date pill that:
   - Displays the friendly name (e.g., "Today, Feb 6") in the editor
   - Stores the underlying value as a wiki link to the daily note: `[[daily/2026-02-06]]`
5. Clicking the date pill navigates to (or creates) the corresponding daily note.

**Dismissal**: The popup dismisses if:
- The user presses Escape
- The user types a space without matching any keyword
- The cursor moves away from the trigger point

### 2.3 Clicking a Wiki Link

**Trigger**: User clicks on a rendered `[[wiki link]]` in the editor.

1. Single click on a wiki link navigates to the target note.
2. If the target note exists in the workspace:
   - The note opens in a new tab (or switches to it if already open), using the existing `DocumentStore.open()` flow.
3. If the target note does NOT exist:
   - A confirmation dialog appears: "Create 'Note Name'?" with options **Create** and **Cancel**.
   - On **Create**: A new `.md` file is created in the workspace root with the note name, containing `# Note Name` as the first line. The file opens immediately.
   - On **Cancel**: Nothing happens.
4. The link resolution strategy:
   - First, exact match on filename (without extension), case-insensitive.
   - If no exact match, search subdirectories.
   - If multiple matches exist, prefer the file closest to the linking note's directory.

### 2.4 Viewing Backlinks (Phase 2)

**Location**: Collapsible section at the bottom of the editor, below the document content.

1. When a note is open, Synth scans all workspace `.md` and `.txt` files for `[[Note Name]]` references pointing to the current note.
2. A "Backlinks" section appears at the bottom of the editor with:
   - A header: "N backlinks" (collapsed by default)
   - When expanded: a list of linking notes, each showing the note name and a one-line context snippet around the link.
3. Clicking a backlink entry navigates to that note (same as clicking a wiki link).
4. The backlink index is computed lazily on file open and cached until the workspace changes.

---

## 3. Visual Design Specifications

### 3.1 Wiki Link Rendering

Wiki links render inline within the editor text, not as raw `[[brackets]]`.

| Property | Value |
|---|---|
| Text color | `NSColor.controlAccentColor` (system accent / blue) |
| Font weight | `.medium` (one step above body text) |
| Underline | None by default; single underline on hover |
| Cursor | Pointing hand cursor on hover |
| Display text | Note name only, brackets hidden (e.g., `Meeting Notes` not `[[Meeting Notes]]`) |
| Raw mode | When cursor is inside the link, show raw `[[Meeting Notes]]` for editing |

**Broken link styling** (Phase 2):
- Text color: `NSColor.systemRed` at 80% opacity
- Underline: Dashed, `NSUnderlineStyle.patternDash`
- Tooltip on hover: "Note not found -- click to create"

### 3.2 Autocomplete Popup

The popup reuses design patterns from the existing `FileLauncher` (ultraThinMaterial background, rounded corners, shadow).

| Property | Value |
|---|---|
| Width | 300pt |
| Max visible items | 8 |
| Max height | ~320pt (8 items * ~40pt each) |
| Position | Anchored below cursor, left-aligned to `[[` position |
| Background | `.ultraThinMaterial` (matches FileLauncher) |
| Corner radius | 10pt |
| Shadow | 6pt radius |
| Item height | ~40pt |
| Selected item | `Color.accentColor.opacity(0.2)` background (matches FileLauncher) |

**Each autocomplete item shows**:
- File icon (`doc.text` SF Symbol), secondary color
- Note name (filename without extension)
- Parent folder name in caption style, tertiary color (for disambiguation)
- If no results match: "Create 'query' as new note" option at the bottom

**For `@` date autocomplete**:
- Same popup style but narrower (200pt)
- Each item shows: calendar icon + keyword + resolved date in secondary text
- Example: `calendar | Today | Feb 6, 2026`

### 3.3 @Date Pill

Date references render as inline pills/badges.

| Property | Value |
|---|---|
| Background | `Color.accentColor.opacity(0.12)` |
| Text color | `NSColor.controlAccentColor` |
| Font | System font, same size as body, `.medium` weight |
| Corner radius | 4pt |
| Horizontal padding | 4pt |
| Vertical padding | 1pt |
| Display text | e.g., "Today, Feb 6" or "2026-02-06" |
| Cursor | Pointing hand on hover |

### 3.4 Backlinks Section (Phase 2)

| Property | Value |
|---|---|
| Position | Below document content, separated by a thin divider |
| Header | "N backlinks" with disclosure triangle, tertiary color |
| Default state | Collapsed |
| Item layout | Note name (medium weight) + one-line context snippet (secondary color) |
| Max visible | 10 items before scrolling |

---

## 4. Interaction Details

### 4.1 Autocomplete Keyboard Navigation

| Key | Action |
|---|---|
| `[[` | Open autocomplete popup |
| Any character | Filter results by fuzzy match |
| Up Arrow | Move selection up |
| Down Arrow | Move selection down |
| Enter | Insert selected note as link, close popup |
| Tab | Insert first/selected match |
| Escape | Dismiss popup, leave raw `[[` text |
| Backspace (past `[[`) | Dismiss popup |
| `]]` (typed manually) | Close as literal link (no autocomplete selection needed) |

### 4.2 `@` Autocomplete

| Key | Action |
|---|---|
| `@` | Open date autocomplete popup |
| Characters | Filter date options |
| Enter / Tab | Insert selected date reference |
| Escape | Dismiss, leave raw `@` text |
| Space (no match) | Dismiss, treat `@` as literal text |

### 4.3 Link Click Behavior

- **Single click**: Navigate to linked note (open or switch tab)
- **Cmd+Click**: Open linked note in a new tab without switching to it (future enhancement)
- Links are only clickable when the cursor is NOT inside the link text. When the cursor is inside the link, it enters edit mode showing raw brackets.

### 4.4 Link Resolution

Links are resolved by matching the display name to filenames in the workspace:

1. Strip extension from all workspace files
2. Case-insensitive match against link text
3. If the link contains a `/` (e.g., `[[daily/2026-02-06]]`), treat it as a relative path from workspace root
4. Ambiguous matches: prefer files in the same directory as the source note, then workspace root, then alphabetically first

---

## 5. Daily Notes

### 5.1 Storage

| Property | Value |
|---|---|
| Location | `daily/` folder inside workspace root |
| File naming | `YYYY-MM-DD.md` (e.g., `2026-02-06.md`) |
| Auto-creation | Folder and file created on first access |

### 5.2 Template

When a daily note is created automatically, it is initialized with:

```markdown
# February 6, 2026

```

The heading uses the long-form date. The body is left empty for the user.

### 5.3 Date Shortcuts

| Shortcut | Resolves To | Link Target |
|---|---|---|
| `@Today` | Current date | `[[daily/YYYY-MM-DD]]` |
| `@Yesterday` | Previous date | `[[daily/YYYY-MM-DD]]` |
| `@Tomorrow` | Next date | `[[daily/YYYY-MM-DD]]` |

Date resolution happens at insertion time. The stored link always uses the concrete date, so `@Today` inserted on Feb 6 always points to `daily/2026-02-06.md` even when viewed later.

---

## 6. Data Model Considerations

### 6.1 Storage Format

Wiki links are stored in the markdown source as `[[Note Name]]`. No database or index file is needed for Phase 1. The raw text is the source of truth.

For date references, the stored format is `[[daily/YYYY-MM-DD]]` with a display hint. In the markdown file on disk, this appears as:

```
See my notes from [[daily/2026-02-06]].
```

### 6.2 Rendering Pipeline

The existing `MarkdownFormat.render()` in `MarkdownEditor.swift` already processes inline patterns (bold, italic, code). Wiki link rendering fits naturally as an additional pass in `applyInlineFormatting()`:

1. Regex pattern: `\[\[(.+?)\]\]`
2. Replace matched range with styled `NSAttributedString` using link attributes
3. Store the link target in a custom `NSAttributedString.Key` (e.g., `.wikiLink`) for click handling

### 6.3 Click Handling

The `FormattingTextView` (subclass of `NSTextView`) can override `mouseDown(with:)` to detect clicks on characters with the `.wikiLink` attribute and route to `DocumentStore.open()`.

---

## 7. Phasing

### Phase 1 -- MVP

Minimal viable wiki linking. Ship this first.

- [x] `[[` trigger opens autocomplete popup
- [x] Fuzzy search filters workspace notes
- [x] Enter/Tab/Click inserts `[[Note Name]]`
- [x] Wiki links render with accent color and medium weight
- [x] Clicking a wiki link opens the target note
- [x] Click on a missing link offers to create the note
- [x] `@Today`, `@Yesterday`, `@Tomorrow` date shortcuts
- [x] Daily notes created in `daily/` folder with date template
- [x] Date references render as inline pills
- [x] Raw bracket editing when cursor is inside link

### Phase 2 -- Connections

Build out the linking ecosystem.

- [ ] Backlinks section at bottom of notes
- [ ] Broken link detection and red/dashed styling
- [ ] Backlink count in file sidebar
- [ ] `@Date...` option with date picker
- [ ] Cmd+Click to open in background tab

### Phase 3 -- Intelligence

Advanced features that build on the link graph.

- [ ] Automatic link refactoring when a note is renamed
- [ ] Graph view showing note connections
- [ ] "Unlinked mentions" detection (text that matches a note name but isn't wrapped in `[[]]`)
- [ ] AI-suggested links ("This note might relate to...")

---

## 8. Integration Points with Existing Code

| Component | Change Required |
|---|---|
| `FormattingTextView` (`MarkdownEditor.swift`) | Override `insertText` to detect `[[` and `@` triggers; override `mouseDown` for link clicks |
| `MarkdownFormat` (`MarkdownEditor.swift`) | Add wiki link regex pass in `applyInlineFormatting()` |
| `DocumentStore` (`DocumentStore.swift`) | Add `resolveWikiLink(_:from:)` method for link-to-file resolution; add `createDailyNote(for:)` method |
| `ContentView.swift` | Host the autocomplete popup as an overlay (similar to `FileLauncher` pattern) |
| `FileLauncher.swift` | Reuse `fuzzyScore` algorithm (already an extension on `String`) |
| `FileTreeNode.swift` | No changes needed; `flattenFiles` already provides the file list |
| `Document.swift` | No changes to load/save; wiki links are plain text in markdown |
| `Theme.swift` | Optionally add `linkColor` and `datePillBackground` constants |

### New Files Needed

| File | Purpose |
|---|---|
| `WikiLinkAutocomplete.swift` | SwiftUI view for the `[[` autocomplete popup |
| `WikiLinkResolver.swift` | Logic for resolving link text to file URLs |
| `DailyNoteManager.swift` | Daily note creation and date shortcut resolution |

---

## 9. Accessibility

- Autocomplete popup must be navigable via keyboard only (arrow keys, Enter, Escape)
- Wiki links should expose an `NSAccessibility` link role
- Screen readers should announce "Link to Note Name" when the cursor enters a wiki link
- Date pills should read the full date (e.g., "Link to daily note February 6, 2026")

---

## 10. Open Questions

1. **Should wiki links be case-sensitive?** Recommendation: No. `[[meeting notes]]` and `[[Meeting Notes]]` should resolve to the same file.
2. **What happens to links when a note is renamed?** Phase 1: Links break silently. Phase 2: Prompt to update references. Phase 3: Automatic refactoring.
3. **Should the autocomplete show files from all subdirectories or only the current folder?** Recommendation: All workspace files, with the parent folder shown for disambiguation.
4. **Maximum workspace size for responsive autocomplete?** The existing `FileLauncher` approach (flatten + fuzzy score) works for workspaces up to ~10,000 files. Beyond that, consider an indexed approach in Phase 3.
