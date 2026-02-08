# Daily Notes View -- Product Requirements Document

**Feature:** Daily Notes Chronological View with Calendar Sidebar
**Date:** 2026-02-07
**Status:** Draft

---

## 1. Overview

The Daily Notes view replaces the current "open today's daily note as a tab" workflow with a dedicated, continuous chronological journal view. Users see all their daily notes in a vertically-scrollable timeline with inline editing, alongside a calendar widget for date navigation. This transforms daily notes from isolated files into a connected journal experience.

## 2. Goals

- Provide a single view for browsing and editing all daily notes across time
- Let users quickly navigate to any date via the calendar widget
- Auto-create notes for today (and upcoming days) so the view is never empty
- Maintain full backward compatibility with existing `daily/YYYY-MM-DD.md` files
- Feel native to macOS -- follow Apple's design language and interaction patterns

## 3. Non-Goals

- Replacing the file-based storage format (notes remain as `daily/YYYY-MM-DD.md`)
- Adding reminders, notifications, or time-based triggers
- Multi-workspace daily note aggregation
- Syncing or cloud-based daily notes

---

## 4. User Stories

| ID | Story | Priority |
|----|-------|----------|
| US-1 | As a user, I want to press Cmd+D and immediately see today's daily note in a scrollable timeline so I can quickly journal | P0 |
| US-2 | As a user, I want to scroll up/down through past and future daily notes without switching tabs | P0 |
| US-3 | As a user, I want to click a date on the calendar to jump to that day's note | P0 |
| US-4 | As a user, I want today's note to be auto-created so I never see a blank screen | P0 |
| US-5 | As a user, I want to edit notes inline in the timeline without opening a separate editor tab | P0 |
| US-6 | As a user, I want each date entry to have a prominent header so I can visually scan the timeline | P1 |
| US-7 | As a user, I want the current month calendar to highlight today and show which dates have notes | P1 |
| US-8 | As a user, I want "Daily notes" to appear in the left sidebar so I can access the view from the navigation | P1 |
| US-9 | As a user, I want notes for the next 7 days to appear as empty placeholders so I can plan ahead | P2 |
| US-10 | As a user, I want to navigate months in the calendar with prev/next arrows | P1 |

---

## 5. Feature Specification

### 5.1 Daily Notes View (Main Content Area)

**Layout:** A full-height scrollable view replacing the editor area when active. No tab bar or line numbers are shown -- this is a dedicated view mode, similar to how `LinksView` replaces the editor.

**Content structure per date entry:**
1. **Date header**: Full date in format "Day, Month Nth, Year" (e.g., "Sat, February 7th, 2026")
   - Bold, large text (~20pt)
   - Left accent bar: 3px wide, accent color (system purple/blue), full height of the header
   - Top padding separating entries: 24pt
2. **Note content area**: The markdown content of the `daily/YYYY-MM-DD.md` file, rendered and editable inline
   - Uses the existing `MarkdownEditor` rendering (wiki links, tags, @mentions all work)
   - Minimum height of ~120pt so empty notes don't collapse to nothing
   - Content is editable in place -- typing creates/modifies the underlying file

**Scroll order:** Newest date at the top, oldest at the bottom. The view scrolls continuously.

**Date range loaded:**
- Future: Today + 7 days ahead (pre-created as virtual notes)
- Past: All existing `daily/YYYY-MM-DD.md` files, plus fill in any gaps between the earliest file and today as empty virtual entries
- If no daily notes exist yet, show today + 7 future days

**Virtual notes (lazy file creation):**
- A "virtual" daily note is an entry that appears in the timeline but has no file on disk yet
- The file is created only when the user begins typing in that entry
- File is created at `{workspace}/daily/YYYY-MM-DD.md` with `# Month Day, Year\n\n` heading, matching existing `DailyNoteResolver.ensureExists()` behavior
- Virtual notes show the date header and an empty/placeholder content area

**Auto-save:** Content auto-saves on:
- Switching to a different date entry (blur)
- Switching away from the Daily Notes view
- App losing focus (existing `applicationWillResignActive` behavior)
- Cmd+S (saves the currently focused entry)

### 5.2 Calendar Sidebar (Right Side)

**Position:** Right sidebar, ~260px wide (matching the existing backlinks sidebar width). Shown whenever the Daily Notes view is active. Can be toggled independently.

**Calendar widget components:**
1. **Month/Year header**: "February 2026" with left/right arrow buttons for month navigation
2. **Day-of-week row**: Mo Tu We Th Fr Sa Su
3. **Date grid**: Standard 6-row x 7-column grid
   - **Today**: Highlighted with a filled accent-color circle
   - **Dates with notes**: Shown with a small dot indicator below the number
   - **Dates in adjacent months**: Grayed out text
   - **Selected date**: Outlined circle (when user clicks a date to navigate)
4. **Click behavior**: Clicking a date scrolls the main timeline to that date's entry (or creates a virtual entry and scrolls to it if outside the current range)

**Month navigation:**
- Left arrow: Previous month
- Right arrow: Next month
- Clicking the month/year text returns to the current month and scrolls to today

### 5.3 Left Sidebar Entry

**Position:** Top of the existing file tree sidebar, above the workspace file list.

**Entry:**
- Label: "Daily notes"
- Icon: `calendar` (SF Symbol) or `note.text` -- should be distinct from file tree icons
- Highlighted (selected state) when the Daily Notes view is active
- Click activates the Daily Notes view

**Separator:** A subtle divider between the "Daily notes" entry and the file tree below it.

### 5.4 Navigation & Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+D | Open/activate Daily Notes view, scroll to today |
| Up/Down arrow | Normal scrolling within the timeline |
| Cmd+S | Save the currently focused daily note entry |

**Cmd+D behavior change:** Currently `Cmd+D` calls `store.openDailyNote()` which opens today's note as a tab. The new behavior activates the Daily Notes view and scrolls to today. If the Daily Notes view is already active, Cmd+D scrolls to today.

### 5.5 Integration with Existing Features

- **Wiki links** (`[[Note]]`): Work normally within daily note content. Clicking navigates to the linked note (opens as a tab in the standard editor).
- **@mentions** (`@PersonName`): Work normally, show in People Browser.
- **#tags**: Work normally, show in Tag Browser.
- **@Today/@Yesterday/@Tomorrow**: Rendered as links. Clicking scrolls within the Daily Notes timeline instead of opening a tab.
- **Backlinks**: Notes that link TO a daily note (via wiki link or @Today) should appear in that note's backlinks. The backlinks sidebar is not shown in the Daily Notes view -- backlinks are a per-file feature.
- **Cmd+P (File Launcher)**: Daily notes should still appear in search results. Opening a daily note from Cmd+P opens it in the Daily Notes view and scrolls to it (rather than opening as a tab).
- **Chat/AI (Cmd+K/J)**: Not available in the Daily Notes view for v1. Could be added per-entry in a future iteration.

---

## 6. State Management

### 6.1 New State in DocumentStore

| Property | Type | Purpose |
|----------|------|---------|
| `isDailyNotesActive` | `Bool` | Whether the Daily Notes view is displayed in the detail area |
| `dailyNoteEntries` | `[DailyNoteEntry]` | Ordered list of date entries (date, content, isDirty, isVirtual) |
| `focusedDailyDate` | `Date?` | The date entry currently being edited |

### 6.2 DailyNoteEntry Model

```
struct DailyNoteEntry: Identifiable {
    let date: Date
    var content: String        // markdown text
    var isDirty: Bool
    var isVirtual: Bool        // true = no file on disk yet
    var id: String             // YYYY-MM-DD string
}
```

### 6.3 View Activation

When `isDailyNotesActive == true`:
- The detail column shows `DailyNotesView` instead of the editor or empty state
- The tab bar is hidden (or shows a single "Daily Notes" pseudo-tab)
- `isLinksTabSelected` is set to false
- The "Daily notes" sidebar entry shows as selected

Opening a regular file (clicking in sidebar, Cmd+P, wiki link navigation) deactivates the Daily Notes view and returns to the normal tab-based editor.

---

## 7. File System Conventions

- **Directory:** `{workspace}/daily/`
- **Filename format:** `YYYY-MM-DD.md` (e.g., `2026-02-07.md`)
- **File heading:** `# Month Day, Year` (e.g., `# February 7, 2026`) -- matches existing `DailyNoteResolver`
- **New file creation:** Uses existing `DailyNoteResolver.ensureExists()` logic
- **No changes** to file format or directory structure from what exists today

---

## 8. Visual Design Guidelines

### 8.1 Dark Theme (Primary)

- Background: System text background color (`NSColor.textBackgroundColor`)
- Date header text: Primary text color, bold, ~20pt
- Accent bar: System accent color (purple default), 3px wide
- Content text: Standard markdown rendering (16pt body, existing font stack)
- Calendar: Matches sidebar styling, accent color for today indicator

### 8.2 Design Principles

- **Mac-native**: Use standard SwiftUI/AppKit controls and system colors
- **Minimal chrome**: The timeline should feel like a continuous document, not a grid of cards
- **Consistent with Synth**: Match existing padding, font sizes, and color usage from the editor and sidebar
- **macOS 26 Liquid Glass**: Use `.glassEffect()` for calendar and sidebar elements where appropriate (matching existing usage in ContentView)

---

## 9. Edge Cases

| Case | Behavior |
|------|----------|
| No workspace open | Daily Notes sidebar entry is disabled/hidden |
| No daily/ directory exists | Created automatically when first note is written |
| Very old notes (years of history) | Load lazily -- initially show last 30 days + 7 future, load more on scroll |
| Date with no note and user starts typing | Create file immediately via `DailyNoteResolver.ensureExists()` |
| User deletes a daily note file externally | Entry disappears on next file tree refresh; shows as virtual if within visible range |
| Multiple workspaces | Each workspace has its own `daily/` directory; Daily Notes view shows current workspace only |
| User clicks Cmd+D with no workspace | No-op (same as current behavior) |

---

## 10. Success Metrics

- Users can view and edit today's note within 1 second of pressing Cmd+D
- Calendar navigation scrolls to target date within 200ms
- No perceptible lag when scrolling through 30+ days of notes
- File creation (virtual-to-real) is imperceptible to the user

---

## 11. Implementation Phases

### Phase 1 (MVP)
- DailyNotesView with chronological scroll of existing daily notes
- Date headers with accent bar
- Inline editing (simple text editing, not full MarkdownEditor)
- Cmd+D activates view and scrolls to today
- Left sidebar "Daily notes" entry

### Phase 2
- Calendar sidebar with month navigation
- Today highlighting and date-has-note indicators
- Click-to-navigate from calendar to timeline
- Virtual note creation (lazy file creation on first edit)

### Phase 3
- Full MarkdownEditor integration per entry (wiki links, @mentions, #tags)
- @Today/@Yesterday links navigate within the timeline
- Cmd+P integration (daily notes open in timeline view)
- Lazy loading for large note histories

---

## 12. Open Questions

1. Should the Daily Notes view support the AI chat tray (Cmd+J) per entry, or defer to a future iteration?
2. Should there be a "Daily Notes" tab in the tab bar when the view is active, or should the tab bar be hidden entirely?
3. Should clicking a date in the calendar that has no note and is in the past create a file, or show an empty virtual entry?
4. What is the maximum number of future days to pre-populate (7? 14? configurable)?

---

## 13. Appendix: Architecture Notes for Engineers

### Files to Modify
- `ContentView.swift` -- Add Daily Notes view toggle in detail column, add sidebar entry
- `DocumentStore.swift` -- Add `isDailyNotesActive`, daily note entries state, activation/deactivation logic
- `DailyNoteResolver.swift` -- Extend with date range scanning, virtual note support
- `SynthApp.swift` -- Update Cmd+D handler to activate Daily Notes view

### New Files
- `DailyNotesView.swift` -- Main chronological timeline view
- `CalendarSidebarView.swift` -- Calendar widget for right sidebar
- `DailyNoteEntry.swift` -- Model for individual date entries

### Key Patterns to Follow
- Use `@EnvironmentObject var store: DocumentStore` for state (matches all existing views)
- Use `NotificationCenter` for cross-component events (matches existing pattern)
- Use `LazyVStack` for performance with many entries (matches LinksView pattern)
- File operations through `FileManager` (matches existing Document/DailyNoteResolver pattern)
