# Backlinks, #Tags, and Related Notes -- UX/Visual Design Specification

**Feature**: Backlinks panel, inline #tags with autocomplete, tag browser, broken link styling, related notes
**Target**: Synth macOS text editor
**Status**: Design Spec
**Last updated**: 2026-02-06

---

## 1. Backlinks Section

### 1.1 Placement and Layout

The backlinks section is a collapsible panel rendered below the editor content, inside the same scroll container as the document. It lives within `EditorViewSimple`, placed after the `MarkdownEditor` and before the `DocumentChatTray` (if visible).

**Component hierarchy**:
```
EditorViewSimple
  HStack(spacing: 0)
    LineNumberGutter
    VStack(spacing: 0)
      MarkdownEditor        // existing
      BacklinksSection       // new -- below editor content
      RelatedNotesSection    // new -- below backlinks
```

The backlinks section scrolls with the document. It is not a fixed/floating element. This matches the mental model of "metadata about this note" living at the end of the note, similar to footnotes.

### 1.2 Visual Design

**Container**:
| Property | Value |
|---|---|
| Top separator | 1px `Color.primary.opacity(0.08)` divider, full-width |
| Top margin | 16pt above the divider (space from last line of content) |
| Horizontal padding | 20pt (matches `textContainerInset.width` on the NSTextView) |
| Vertical padding | 12pt top, 16pt bottom |
| Background | Transparent (inherits editor background `NSColor.textBackgroundColor`) |

**Header row** (always visible):
| Property | Value |
|---|---|
| Layout | HStack: disclosure triangle + label + count badge + spacer |
| Disclosure triangle | SF Symbol `chevron.right`, rotates 90 degrees when expanded. Size 10pt, `.secondary` color |
| Label | "Backlinks" in `NSFont.systemFont(ofSize: 12, weight: .medium)`, `.secondary` color |
| Count badge | "(N)" appended to label, same font/color. Example: "Backlinks (3)" |
| Tap target | Entire header row is tappable (`.contentShape(Rectangle())`) |
| Animation | Disclosure rotation: `.easeOut(duration: 0.15)`. Content reveal: `.easeOut(duration: 0.2)` |

**Expanded content** (list of backlink entries):
| Property | Value |
|---|---|
| Layout | VStack(alignment: .leading, spacing: 8) |
| Top padding | 8pt below header |
| Max visible entries | 10 before the list clips (internal ScrollView only if > 10) |
| Max height (scrollable) | 400pt |

### 1.3 Backlink Entry Design

Each entry represents a note that references the current note via `[[wiki link]]`.

```
+---------------------------------------------------------------+
| doc.text  Meeting Notes                        projects/       |
|           "...discussed the approach in [[Design Spec]] and    |
|            agreed to proceed..."                               |
+---------------------------------------------------------------+
```

| Property | Value |
|---|---|
| Layout | VStack(alignment: .leading, spacing: 2) inside a row container |
| Row container | Rounded rectangle with 6pt corner radius, `Color.primary.opacity(0.03)` background on hover |
| Horizontal padding | 8pt |
| Vertical padding | 6pt |
| **Title line** | HStack: icon + note title + spacer + relative path |
| Icon | SF Symbol `doc.text`, 12pt, `.secondary` color |
| Note title | System font 13pt, `.medium` weight, `.primary` color. Clickable (navigates to note) |
| Relative path | System font 11pt (`.caption`), `.tertiary` color. Shows parent folder name |
| **Context snippet** | Below title line. System font 12pt, `.secondary` color. Single line, truncated with ellipsis |
| Snippet highlight | The `[[link text]]` within the snippet is rendered in `NSColor.controlAccentColor` at 12pt `.medium` weight |
| Cursor | Pointing hand on hover over entire entry |
| Click action | `store.open(url)` -- opens the linking note in a tab |

### 1.4 States

**Empty state** (no backlinks):
- Show a subtle message below the divider: "No backlinks yet" in system font 12pt, `.tertiary` color, centered
- Padding: 12pt vertical
- Do NOT show the disclosure group at all -- just the message with the divider above

**Collapsed state** (has backlinks, user collapsed):
- Show only the header row: "Backlinks (3)" with rightward chevron
- Persist collapsed/expanded preference via `@AppStorage("backlinksExpanded")`

**Expanded state** (has backlinks, user expanded):
- Show header with downward chevron + scrollable list of entries
- Default state for first use: collapsed (per existing product spec)

**Loading state**:
- Not explicitly shown. Backlink index rebuilds are fast enough (<2s for 10k notes per architecture doc) that a skeleton/spinner is unnecessary
- If the index is stale during rebuild, show the last known results

### 1.5 Keyboard Navigation

| Key | Action |
|---|---|
| Tab (from last line of editor) | Focus moves to backlinks section header |
| Return (on header) | Toggle expanded/collapsed |
| Up/Down (in expanded list) | Navigate between backlink entries |
| Return (on entry) | Open the linking note (`store.open(url)`) |
| Escape | Return focus to editor |

Accessibility: Each backlink entry should have `.accessibilityLabel("Link from \(title)")` and `.accessibilityHint("Opens \(title)")`.

---

## 2. #Tag Inline Rendering

### 2.1 Tag Syntax

Tags are words prefixed with `#` in note content. They are recognized by the pattern `#[a-zA-Z][a-zA-Z0-9_-]*` (must start with a letter after `#`, no spaces). Examples: `#project`, `#idea`, `#work-in-progress`, `#meeting_notes`.

Tags are NOT recognized inside:
- Code blocks (fenced ``` or indented)
- Inline code (`backticks`)
- Wiki links `[[...]]`
- URLs
- Headings (the `#` prefix in `# Heading` is not a tag)

### 2.2 Inline Rendering Style

Tags render inline with distinct styling that visually separates them from wiki links.

| Property | Value |
|---|---|
| Text color | `NSColor.systemTeal` (differs from wiki link `controlAccentColor` to avoid visual confusion) |
| Font | Same size as surrounding text, `.medium` weight |
| Background | `NSColor.systemTeal.withAlphaComponent(0.10)` pill background |
| Corner radius | 3pt on the background pill |
| Horizontal padding | 2pt (visual padding via attributed string paragraph style is not practical; use slight letter spacing or just the background color) |
| Cursor | Pointing hand on hover |
| Click action | Navigate to tag browser filtered to this tag (see Section 3) |
| Link URL scheme | `synth://tag/<tagname>` (e.g., `synth://tag/project`) |

**Rendering in MarkdownFormat**: Add a new regex pass in `applyInlineFormatting`, running after wiki links and date references but before bold/italic/code:

```
Regex: (?<=\s|^)#([a-zA-Z][a-zA-Z0-9_-]*)(?=\s|$|[.,;:!?)])
```

The lookbehind ensures `#` is preceded by whitespace or start-of-line (avoiding false matches on hex colors like `#ff0000` mid-word). The lookahead allows punctuation after the tag.

**Rendered attributed string attributes**:
```swift
[
    .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium),
    .foregroundColor: NSColor.systemTeal,
    .backgroundColor: NSColor.systemTeal.withAlphaComponent(0.10),
    .link: URL(string: "synth://tag/\(tagName)")!
]
```

### 2.3 #Tag Autocomplete Popup

**Trigger**: User types `#` preceded by whitespace or at line start.

**State machine addition**: Extend the existing `WikiLinkState` enum:
```swift
enum WikiLinkState {
    case idle
    case singleBracket
    case wikiLinkActive(start: Int)
    case atActive(start: Int)
    case hashtagActive(start: Int)    // new
}
```

**Detection in `insertText`**: When `str == "#"` and the character before the cursor is whitespace or the cursor is at position 0, transition to `.hashtagActive(start: cursorPosition)`.

**Popup behavior**:
- Reuses the `WikiLinkPopover` NSPopover pattern (cursor-anchored)
- Content size: `NSSize(width: 250, height: 200)`
- Shows all known tags in the workspace, filtered by fuzzy match as user types
- Each row: `#` prefix + tag name + note count badge

**Popup row layout**:
```
+-----------------------------------------------+
| number.sign  #project                    (12)  |
+-----------------------------------------------+
| number.sign  #idea                        (5)  |
+-----------------------------------------------+
| +            Create #newta...                  |
+-----------------------------------------------+
```

| Property | Value |
|---|---|
| Icon | SF Symbol `number.sign`, `.secondary` color, 12pt |
| Tag name | System font 13pt, `NSColor.systemTeal`, `.medium` weight. Prefixed with `#` |
| Note count | System font 11pt (`.caption`), `.tertiary` color. Right-aligned. Shows "(N)" |
| Selected row | `Color.accentColor.opacity(0.2)` background (matches WikiLinkPopover) |
| Create option | Shown when query has no exact match. SF Symbol `plus`, `.secondary`. "Create #query" |
| Query header | Same as WikiLinkPopover: `number.sign` icon + query text + spacer |

**Completion behavior**: On selection (Enter/Tab/Click):
- Replace from `#` through cursor with `#selectedTag`
- Add a space after the tag
- Dismiss popup, reset state to `.idle`
- If "Create" was selected, the tag is simply inserted as text (tags are implicit -- they exist by being typed, no separate creation needed)

**Dismissal**: Popup dismisses on:
- Space (tag name cannot contain spaces; insert what's typed as a literal tag)
- Escape
- Newline
- Backspace past the `#`

### 2.4 Tag Index

A new `TagIndex` class (similar to `NoteIndex`) scans all `.md` files for `#tag` patterns and maintains:
- A set of all unique tags in the workspace
- A mapping from tag name to set of file URLs containing that tag
- Rebuilt on workspace load; incrementally updated on file save

---

## 3. Tag Browser

### 3.1 Access Methods

The tag browser is accessible via:

1. **Keyboard shortcut**: `Cmd+T` opens the tag browser as a centered overlay (same pattern as `FileLauncher` with `Cmd+P`)
2. **Click on inline tag**: Clicking any `#tag` in the editor opens the tag browser pre-filtered to that tag
3. **Sidebar section**: A "Tags" section below the file tree in the navigation sidebar (future enhancement, not in initial implementation)

The initial implementation uses method 1 (overlay) and method 2 (click navigation). This avoids modifying the sidebar layout and reuses the proven overlay pattern from `FileLauncher`.

### 3.2 Tag Browser Overlay Design

The tag browser is a centered overlay popup, matching the `FileLauncher` visual pattern.

**Component hierarchy**:
```
ContentView overlay
  TagBrowser
    VStack(spacing: 0)
      SearchBar          // tag search input
      Divider
      HStack(spacing: 0)
        TagList          // left: scrollable tag list
        Divider
        NoteList         // right: notes matching selected tag(s)
```

**Container**:
| Property | Value |
|---|---|
| Width | 600pt |
| Max height | 400pt |
| Background | `.ultraThinMaterial` (matches FileLauncher) |
| Corner radius | 12pt (matches FileLauncher) |
| Shadow | `radius: 8` (matches FileLauncher) |

**Search bar** (top):
| Property | Value |
|---|---|
| Layout | HStack: `number.sign` icon + TextField + clear button |
| Icon | SF Symbol `number.sign`, `.secondary`, 14pt |
| TextField | "Filter tags..." placeholder, system font 16pt, plain style |
| Padding | 12pt |
| Focus | Auto-focused on appear (`@FocusState`) |

**Tag list** (left panel):
| Property | Value |
|---|---|
| Width | 200pt |
| Layout | ScrollView > VStack(spacing: 0) |
| Each tag row | HStack: tag name (`.medium`, `NSColor.systemTeal`) + spacer + count (`caption`, `.tertiary`) |
| Row padding | 8pt horizontal, 6pt vertical |
| Selected tag | `Color.accentColor.opacity(0.2)` background |
| Multi-select | Hold Cmd to select multiple tags for intersection filtering |
| Hover | `Color.primary.opacity(0.03)` background |

**Note list** (right panel):
| Property | Value |
|---|---|
| Layout | ScrollView > VStack(spacing: 0) |
| Shows | Notes that contain ALL selected tags (intersection/AND filter) |
| Each note row | HStack: `doc.text` icon + note title + spacer + relative path |
| Row padding | 8pt horizontal, 6pt vertical |
| Selected note | `Color.accentColor.opacity(0.2)` background |
| Click | Opens the note via `store.open(url)`, dismisses tag browser |
| Empty state | "No notes with selected tags" centered, `.tertiary` color |

**Active tag pills** (below search bar, above the two-panel area):
When one or more tags are selected, show them as removable pills:

| Property | Value |
|---|---|
| Layout | HStack(spacing: 4) with wrapping (FlowLayout or LazyHGrid) |
| Pill | Rounded capsule, `NSColor.systemTeal.withAlphaComponent(0.15)` background |
| Pill text | `#tagname` in system font 11pt, `.medium`, `NSColor.systemTeal` |
| Remove button | `xmark` icon, 8pt, `.secondary`. Click removes the tag from filter |
| Padding | 4pt horizontal, 2pt vertical per pill. Section has 8pt padding |

### 3.3 Keyboard Navigation

| Key | Action |
|---|---|
| Type characters | Filter tag list |
| Up/Down | Navigate tag list |
| Return | Select/deselect highlighted tag (toggles it in the filter) |
| Tab | Move focus from tag list to note list |
| Up/Down (in note list) | Navigate note list |
| Return (in note list) | Open selected note, dismiss browser |
| Escape | Dismiss tag browser |
| Cmd+Click on tag | Multi-select (add tag to filter without removing others) |

### 3.4 Notification

Add a new notification name for the tag browser:
```swift
static let showTagBrowser = Notification.Name("showTagBrowser")
```

Triggered by `Cmd+T` in `SynthApp.swift` keyboard shortcuts. The notification can carry a `userInfo` dictionary with an initial tag filter when opened from an inline tag click: `["initialTag": "project"]`.

---

## 4. Broken Link Styling

### 4.1 Detection

A wiki link `[[Note Title]]` is "broken" when `noteIndex.findExact(title)` returns `nil`. Detection happens during the `MarkdownFormat.applyInlineFormatting` rendering pass, which already processes wiki link patterns.

### 4.2 Visual Design

**Broken link inline rendering**:
| Property | Value |
|---|---|
| Text color | `NSColor.systemOrange` (orange is less alarming than red, communicates "warning" rather than "error") |
| Font weight | `.medium` (same as valid wiki links) |
| Underline | Dashed underline: `NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue` |
| Underline color | `NSColor.systemOrange.withAlphaComponent(0.6)` |
| Cursor | Pointing hand on hover |
| Brackets | Hidden (same as valid links -- show `Note Title` not `[[Note Title]]`) |
| Link URL | `synth://wiki/<encoded-title>` (same scheme as valid links) |

**Attributed string attributes for broken links**:
```swift
[
    .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium),
    .foregroundColor: NSColor.systemOrange,
    .underlineStyle: NSUnderlineStyle.patternDash.rawValue | NSUnderlineStyle.single.rawValue,
    .underlineColor: NSColor.systemOrange.withAlphaComponent(0.6),
    .link: linkURL,
    .cursor: NSCursor.pointingHand
]
```

### 4.3 Tooltip

On hover, broken links show a tooltip: "Note not found -- click to create"

Implementation: Set `.toolTip` attribute on the attributed string for broken links:
```swift
.toolTip: "Note not found -- click to create"
```

Note: NSAttributedString `.toolTip` is supported by NSTextView natively. The tooltip appears after the standard macOS hover delay (~0.5s).

### 4.4 Click Behavior

Clicking a broken link triggers note creation with a confirmation step:

1. An `NSAlert` appears:
   - **Title**: "Create '\(noteTitle)'?"
   - **Message**: "This note does not exist yet. Create it in the workspace?"
   - **Buttons**: "Create" (default) and "Cancel"
2. On "Create":
   - Create `<noteTitle>.md` in the workspace root
   - File content: `# <noteTitle>\n\n`
   - Call `store.loadFileTree()` to refresh
   - Call `store.open(newURL)` to open the new note
   - The MarkdownFormat re-renders: the link is no longer broken, so it switches to valid link styling (accent color, no underline)
3. On "Cancel": No action

This behavior already exists in the codebase at `MarkdownEditor.Coordinator.handleWikiLinkClick` -- the broken link styling is purely a visual addition to the rendering pass.

### 4.5 Transition Animation

When a broken link becomes valid (e.g., after creating the target note and the editor re-renders), there is no explicit animation. The re-render replaces the attributed string naturally. The color change from orange to accent blue provides sufficient visual feedback.

---

## 5. Related Notes Section

### 5.1 Placement

The related notes section appears below the backlinks section, inside the same scrolling area. It is a separate collapsible group.

**Component hierarchy** (within EditorViewSimple):
```
VStack(spacing: 0)
  MarkdownEditor
  BacklinksSection
  RelatedNotesSection    // new
```

### 5.2 Relationship Algorithm

A note is "related" to the current note if it shares connections through:

1. **Shared tags**: Both notes contain the same `#tag`. Weight: 1 point per shared tag.
2. **Mutual backlinks**: Note A links to Note B AND Note B links to Note A. Weight: 3 points (strong bidirectional relationship).
3. **Common link targets**: Both notes link to the same third note via `[[wiki link]]`. Weight: 1 point per shared target.
4. **Shared incoming links**: Both notes are linked to by the same third note. Weight: 1 point per shared source.

Related notes are scored by summing weights. Only notes with score >= 2 are shown (to avoid noise). The current note itself is excluded. Notes already shown in the backlinks section are still eligible for related notes (since the relationship reason may be different from the backlink).

Maximum items: 8.

### 5.3 Visual Design

**Header**:
| Property | Value |
|---|---|
| Layout | Same as backlinks header: disclosure triangle + label + count |
| Label | "Related Notes" in system font 12pt, `.medium` weight, `.secondary` color |
| Count | "(N)" appended, same styling |
| Default state | Collapsed |
| Persistence | `@AppStorage("relatedNotesExpanded")` |
| Top separator | 1px `Color.primary.opacity(0.08)` divider |
| Top margin | 8pt above divider (tighter than backlinks since they're grouped) |

**Entry design**:
```
+---------------------------------------------------------------+
| doc.text  Architecture Notes                                   |
|           shares #project, #design  *  also links to [[API]]  |
+---------------------------------------------------------------+
```

| Property | Value |
|---|---|
| Layout | VStack(alignment: .leading, spacing: 2) |
| Row container | Same as backlink entry: rounded rect, 6pt radius, hover highlight |
| Horizontal padding | 8pt |
| Vertical padding | 6pt |
| **Title line** | HStack: `doc.text` icon (12pt, `.secondary`) + note title (13pt, `.medium`, `.primary`) |
| **Reason line** | System font 11pt, `.tertiary` color. Describes why this note is related |
| Reason format | Comma-separated relationship reasons. Examples below |
| Cursor | Pointing hand on hover |
| Click action | `store.open(url)` |

**Reason line examples**:
- "shares #project, #design" (shared tags -- tags rendered in `NSColor.systemTeal`)
- "also links to [[API Design]]" (common link target -- link name in `NSColor.controlAccentColor`)
- "mutual link" (bidirectional backlink)
- "shares #project * also links to [[API Design]]" (multiple reasons, separated by ` * `)

The reason line uses rich text (if rendered in SwiftUI `Text` with concatenation):
- Tag names: `NSColor.systemTeal` / `Color(nsColor: .systemTeal)`
- Link names: `NSColor.controlAccentColor` / `Color.accentColor`
- Connectors ("shares", "also links to", "mutual link"): `.tertiary` color

### 5.4 Empty State

If no related notes meet the score threshold:
- Do NOT show the Related Notes section at all (no header, no empty message)
- This keeps the bottom of the editor clean when a note has no meaningful connections

### 5.5 Collapsible Behavior

- Both backlinks and related notes remember their expanded/collapsed state independently
- Toggling one does not affect the other
- Both use `DisclosureGroup` with `@AppStorage` bindings

---

## 6. Color Summary

Consolidated color reference for all new elements:

| Element | Color | NSColor Name |
|---|---|---|
| Valid wiki link text | System accent (blue) | `NSColor.controlAccentColor` |
| Broken wiki link text | Orange | `NSColor.systemOrange` |
| Broken wiki link underline | Orange at 60% | `NSColor.systemOrange.withAlphaComponent(0.6)` |
| #Tag text | Teal | `NSColor.systemTeal` |
| #Tag background pill | Teal at 10% | `NSColor.systemTeal.withAlphaComponent(0.10)` |
| Tag browser pill background | Teal at 15% | `NSColor.systemTeal.withAlphaComponent(0.15)` |
| Section headers | Secondary | `.secondary` (SwiftUI) |
| Context snippets | Secondary | `.secondary` (SwiftUI) |
| Relative paths / counts | Tertiary | `.tertiary` (SwiftUI) |
| Empty state text | Tertiary | `.tertiary` (SwiftUI) |
| Section dividers | Primary at 8% | `Color.primary.opacity(0.08)` |
| Row hover background | Primary at 3% | `Color.primary.opacity(0.03)` |
| Selected row background | Accent at 20% | `Color.accentColor.opacity(0.2)` |
| Popup/overlay background | Ultra-thin material | `.ultraThinMaterial` |

All colors are semantic and adapt to light/dark mode automatically.

---

## 7. Spacing and Padding Reference

| Location | Value |
|---|---|
| Backlinks section top margin (from last editor line) | 16pt |
| Backlinks section horizontal padding | 20pt (matches editor `textContainerInset.width`) |
| Backlinks header vertical padding | 12pt top, 0 bottom when collapsed; 12pt top, 8pt to content when expanded |
| Backlink entry inter-item spacing | 8pt |
| Backlink entry internal padding | 8pt horizontal, 6pt vertical |
| Related notes section top margin (from backlinks) | 8pt |
| Related notes follows same padding as backlinks | Same values |
| Bottom padding (below last section) | 16pt |
| Tag browser overlay width | 600pt |
| Tag browser overlay max height | 400pt |
| Tag browser search bar padding | 12pt |
| Tag browser row padding | 8pt horizontal, 6pt vertical |
| Tag browser tag list width | 200pt |
| Hashtag autocomplete popup width | 250pt |
| Hashtag autocomplete popup max height | 200pt |

---

## 8. Animation Specifications

| Animation | Spec |
|---|---|
| Backlinks/Related Notes disclosure toggle | `.easeOut(duration: 0.15)` for chevron rotation; `.easeOut(duration: 0.2)` for content reveal |
| Tag browser overlay appear/dismiss | `.easeOut(duration: 0.15)` with `.opacity.combined(with: .scale(scale: 0.95))` transition (matches FileLauncher) |
| Hashtag autocomplete popup | `NSPopover.animates = true` (default system animation, matches WikiLinkPopover) |
| Tag pill appear in browser | `.easeOut(duration: 0.15)` with `.opacity.combined(with: .scale)` |
| Tag pill removal | `.easeOut(duration: 0.1)` fade out |
| Row hover highlight | No animation (instant, matches existing FileRow hover behavior) |
| Broken link -> valid link | No animation (re-render handles it naturally) |

---

## 9. Interaction Flows

### 9.1 Typing a #Tag with Autocomplete

```
User types "#pro" in editor
  |
  v
FormattingTextView.insertText("#") -> checks whitespace before cursor
  -> state = .hashtagActive(start: cursorPos)
  -> Posts .wikiLinkTrigger with mode="hashtag"
  |
  v
Coordinator receives trigger
  -> Opens WikiLinkPopover at cursor (mode="hashtag")
  -> Queries TagIndex for all tags, shows initial list
  |
  v
User types "pro"
  -> Posts .wikiLinkQueryUpdate with query="pro"
  -> Coordinator filters tags: #project, #proposal, #productivity
  -> Updates popup
  |
  v
User presses Down, then Return
  -> Posts .wikiLinkNavigate(down), then .wikiLinkSelect
  -> Coordinator inserts "#project " (with trailing space)
  -> Popup dismissed, state = .idle
  |
  v
MarkdownFormat re-renders
  -> Detects #project pattern
  -> Renders "project" in teal with pill background
  -> Stores synth://tag/project as .link attribute
```

### 9.2 Clicking a Broken Link

```
User clicks orange-colored "Design Spec" link
  |
  v
Coordinator.textView(_:clickedOnLink:at:) receives synth://wiki/Design%20Spec
  -> Calls noteIndex.findExact("Design Spec") -> nil
  |
  v
Shows NSAlert: "Create 'Design Spec'?"
  |
  +-> "Create": Creates Design Spec.md, opens it, re-renders linking note
  |                (link now valid -> accent color)
  |
  +-> "Cancel": No action
```

### 9.3 Opening Tag Browser from Inline Tag

```
User clicks "#project" in editor text
  |
  v
Coordinator.textView(_:clickedOnLink:at:) receives synth://tag/project
  -> Posts .showTagBrowser with userInfo: ["initialTag": "project"]
  |
  v
ContentView receives notification
  -> Sets showTagBrowser = true, initialTagFilter = "project"
  |
  v
TagBrowser appears as centered overlay
  -> Tag list: "project" is pre-selected
  -> Note list: Shows all notes containing #project
  -> User can Cmd+Click another tag to narrow results
  |
  v
User clicks a note in the list
  -> store.open(noteURL)
  -> Tag browser dismisses
```

### 9.4 Browsing Backlinks

```
User opens "API Design.md"
  |
  v
EditorViewSimple renders with BacklinksSection
  -> backlinkIndex.links(to: "API Design") returns 3 URLs
  -> BacklinksSection shows "Backlinks (3)" header, collapsed
  |
  v
User clicks header to expand
  -> @AppStorage saves expanded=true
  -> List animates open showing 3 entries:
     1. "Architecture Notes" -- "...the [[API Design]] should follow REST..."
     2. "Sprint Planning" -- "...review [[API Design]] before demo..."
     3. "Meeting 2026-02-05" -- "...Kyle presented [[API Design]]..."
  |
  v
User clicks "Architecture Notes"
  -> store.open(architectureNotesURL)
  -> Tab switches to Architecture Notes
```

---

## 10. New Files Required

| File | Purpose |
|---|---|
| `SynthApp/BacklinksSection.swift` | `BacklinksSection` and `BacklinkRow` SwiftUI views |
| `SynthApp/BacklinkIndex.swift` | `BacklinkIndex` class: full/incremental rebuild, context snippets |
| `SynthApp/RelatedNotesSection.swift` | `RelatedNotesSection` and `RelatedNoteRow` SwiftUI views, scoring algorithm |
| `SynthApp/TagIndex.swift` | `TagIndex` class: workspace-wide tag scanning, tag-to-files mapping |
| `SynthApp/TagBrowser.swift` | `TagBrowser` SwiftUI overlay view (two-panel tag/note browser) |

## 11. Modified Files

| File | Changes |
|---|---|
| `SynthApp/MarkdownEditor.swift` (MarkdownFormat) | Add #tag regex pass in `applyInlineFormatting`. Add broken link styling (orange + dashed underline + tooltip) |
| `SynthApp/MarkdownEditor.swift` (FormattingTextView) | Add `.hashtagActive` case to `WikiLinkState`. Handle `#` trigger in `insertText`. Handle space-to-dismiss for hashtags |
| `SynthApp/MarkdownEditor.swift` (Coordinator) | Handle `synth://tag/` URL clicks. Wire hashtag mode in WikiLinkPopover. Query TagIndex for hashtag autocomplete |
| `SynthApp/WikiLinkPopover.swift` | Add `mode == "hashtag"` rendering variant (teal color, `number.sign` icon, count badge) |
| `SynthApp/ContentView.swift` | Add `.showTagBrowser` notification. Add `showTagBrowser` state and TagBrowser overlay. Add `Cmd+T` handling |
| `SynthApp/ContentView.swift` (EditorViewSimple) | Add `BacklinksSection` and `RelatedNotesSection` below MarkdownEditor |
| `SynthApp/DocumentStore.swift` | Add `backlinkIndex: BacklinkIndex` and `tagIndex: TagIndex` properties. Rebuild in `loadFileTree()`. Incremental update in `save()` |
| `SynthApp/NoteIndex.swift` | Add broken link check method: `func exists(_ title: String) -> Bool` |
| `SynthApp/SynthApp.swift` | Add `Cmd+T` keyboard shortcut posting `.showTagBrowser` |

---

## 12. Design Rationale

1. **Teal for tags, accent blue for wiki links**: Two distinct semantic colors prevent users from confusing tags with links. Teal is calmer than blue and communicates "categorization" rather than "navigation."

2. **Orange for broken links (not red)**: Red implies error or danger. Orange communicates "attention needed" without alarm, which is appropriate since broken links are a normal part of the note-writing workflow (you often create the link before the note).

3. **Tag browser as overlay (not sidebar section)**: Adding a permanent sidebar section would consume horizontal space and add visual clutter. The overlay appears on demand, like FileLauncher, and vanishes when dismissed. A sidebar section can be added later as an optional view.

4. **Backlinks scroll with content**: Placing backlinks in the document scroll area (not a fixed panel) means they don't compete for screen space with the chat tray. The user scrolls past them if not needed.

5. **Related notes threshold of 2**: Requiring at least 2 relationship points filters out noise. A single shared tag between two notes in a large workspace is weak evidence of relatedness. Two shared tags, or a tag plus a common link target, is meaningful.

6. **Maximum 8 related notes**: Keeps the section scannable. Beyond 8, the signal-to-noise ratio degrades. Users who want exhaustive connections can use the tag browser or eventually a graph view.

7. **NSPopover for hashtag autocomplete**: Reuses the exact infrastructure built for wiki link autocomplete. Same cursor-anchored positioning, same keyboard navigation, same notification flow. Only the data source and visual styling differ.

8. **Multi-tag intersection in browser**: AND filtering (show notes with ALL selected tags) is more useful than OR filtering for narrowing results. Users who want OR behavior can look at each tag individually.
