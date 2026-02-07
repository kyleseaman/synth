# Daily Notes View - UX Specification

## 1. Overview

The Daily Notes view is a dedicated chronological journal interface within Synth. It replaces the standard editor detail area when activated, presenting a continuous scroll of daily notes with an integrated calendar sidebar. The design targets macOS 26 Liquid Glass aesthetic while remaining consistent with Synth's existing visual language.

---

## 2. Layout Specification

### 2.1 Three-Column Structure

The Daily Notes view reuses the existing `NavigationSplitView` layout:

```
+---------------------+----------------------------------+------------+
|   Left Sidebar      |    Center: Note Stream           |  Calendar  |
|   (250-500px)       |    (flexible, min 500px)         |  Sidebar   |
|                     |                                  |  (260px)   |
|   [existing file    |    [chronological daily notes    |            |
|    tree with        |     scrolling vertically]        |  [month    |
|    "Daily notes"    |                                  |   grid]    |
|    entry at top]    |                                  |            |
+---------------------+----------------------------------+------------+
```

- **Left sidebar**: Existing file tree sidebar. A new "Daily notes" entry is added at the very top, above the file tree list, as a pinned navigation item.
- **Center pane**: Continuous vertical scroll of daily notes, each separated by date headers. Flexible width, minimum 500px. Content is horizontally centered with a maximum content width of 720px and horizontal padding of 48px on each side (matching typical prose-optimized reading widths).
- **Right sidebar (Calendar)**: Fixed width of 260px (matching the existing backlinks sidebar width for consistency). Contains the calendar widget and optional quick actions. Separated from center by a `Divider()`.

### 2.2 Left Sidebar - "Daily notes" Entry

Position: First item in the sidebar list, above the file tree, separated by a subtle divider.

```
+---------------------+
|  [pencil.line]      |
|  Daily notes        |  <-- Accent color background when active
|---------------------|
|  [folder] Projects  |
|  [folder] Notes     |
|  ...                |
+---------------------+
```

- **Icon**: `pencil.line` SF Symbol (represents writing/journaling)
- **Label**: "Daily notes" (sentence case)
- **Active state**: Background fill with `Color.accentColor.opacity(0.15)`, text and icon in `Color.accentColor`, font weight `.semibold`
- **Inactive state**: `.secondary` foreground, `.regular` weight
- **Hover state**: `Color.accentColor.opacity(0.08)` background, matching existing `FileRow` hover behavior
- **Corner radius**: 6pt (matching existing `FileRow` rounding)
- **Padding**: `.vertical(8)`, `.horizontal(10)` -- slightly more generous than file rows to visually distinguish it as a pinned item

### 2.3 Responsive Behavior

- When the left sidebar is collapsed (via Cmd+\), the center pane expands to fill the available space. The calendar sidebar remains visible.
- The calendar sidebar can be toggled independently via a small button in its header area, similar to the backlinks toggle button pattern. When hidden, the center pane expands.
- Minimum window width remains 800px. At narrow widths, the calendar sidebar auto-hides first.

---

## 3. Typography & Visual Hierarchy

### 3.1 Date Headers

Each daily note section begins with a prominent date header:

```
|  Sat, February 7th, 2026
|
   - Bullet point content here
   - More content
```

- **Format**: `"EEE, MMMM d'th', yyyy"` (e.g., "Sat, February 7th, 2026") using ordinal suffixes (st, nd, rd, th)
- **Font**: System font, size 24pt, weight `.bold`
- **Color**: `.primary` (adapts to light/dark mode)
- **Left accent bar**: 3pt wide, `Color.accentColor` (system accent), full height of the date text line, positioned 0px from the left edge of the content area with 12px gap before the date text
- **Spacing**: 32px top margin between note sections, 12px bottom margin below date header before content begins
- **Today indicator**: Today's date header includes a small "Today" pill badge to the right of the date text -- `.caption` size, `.medium` weight, `Color.accentColor.opacity(0.15)` background with `Color.accentColor` text, 4pt vertical / 8pt horizontal padding, capsule shape

### 3.2 Note Content

- **Font**: System font, size 16pt (matching existing `MarkdownFormat` body font)
- **Bullet points**: Standard markdown bullet rendering via existing `MarkdownFormat`
- **Line height**: 1.5x (24pt)
- **Content left inset**: 15px from the left accent bar position (aligning content with the date text)

### 3.3 Empty Day Placeholder

For days without content (virtual notes):

- Date header renders normally
- Below the header: A single line of placeholder text "Start writing..." in `.tertiary` foreground, `.italic` style
- On click/focus, placeholder disappears and a cursor appears, ready for input
- File is created on first keystroke (lazy creation)

### 3.4 Visual Separation Between Days

- Between each day's section: a subtle horizontal rule -- 1px line in `Color.primary.opacity(0.06)`, spanning the full content width, centered vertically in the 32px gap between sections

---

## 4. Color & Styling (Liquid Glass / macOS 26)

### 4.1 Color Palette

| Element | Dark Mode | Light Mode |
|---|---|---|
| Background | `Color(nsColor: .textBackgroundColor)` | Same (adapts automatically) |
| Date header text | `.primary` | `.primary` |
| Left accent bar | `Color.accentColor` | `Color.accentColor` |
| Note content | `.primary` | `.primary` |
| Placeholder text | `.tertiary` | `.tertiary` |
| Day separator | `.primary.opacity(0.06)` | `.primary.opacity(0.08)` |
| Calendar sidebar bg | `Color(nsColor: .textBackgroundColor).opacity(0.5)` | Same |
| Today badge | `Color.accentColor.opacity(0.15)` bg, `Color.accentColor` text | Same |

### 4.2 Liquid Glass Effects

- **Calendar sidebar**: Apply `.background(.ultraThinMaterial)` to the calendar container for a frosted glass appearance, consistent with the existing toolbar material usage
- **Floating "scroll to today" button**: When the user scrolls away from today, a floating pill button appears at the bottom-center of the note stream: "Today" with a `chevron.up` or `chevron.down` icon (depending on scroll direction relative to today). Uses `.glassEffect(.regular.interactive())` matching the existing chat toggle button pattern
- **Calendar sidebar toggle button**: `.plain` button style, matching the backlinks toggle pattern

### 4.3 Dark Mode First

The design is dark-mode-first, matching the reference UI. All colors use semantic system colors (`NSColor.textBackgroundColor`, `NSColor.textColor`, `Color.accentColor`) that automatically adapt to light mode. No hardcoded color values.

---

## 5. Interaction Design

### 5.1 Navigation & Entry Points

| Action | Behavior |
|---|---|
| **Cmd+D** | Activates Daily Notes view (if not already active) AND smooth-scrolls to today's note. If already in Daily Notes view, just scrolls to today. |
| **Sidebar "Daily notes" click** | Activates Daily Notes view, scrolls to today |
| **Calendar date click** | Smooth-scrolls the note stream to the clicked date's note section |
| **Tab bar** | "Daily notes" appears as a persistent tab (like the existing "Links" tab), with `calendar` SF Symbol. Clicking it activates the view. |

### 5.2 Scrolling

- **Direction**: Newest dates at the top, older dates below. This matches the natural reading direction for a journal -- today is always near the top.
- **Momentum**: Standard macOS scroll physics via `ScrollView`
- **Scroll anchoring**: When the view loads or Cmd+D is pressed, the scroll position anchors to today's date header, positioned at the top of the visible area with 20px top inset
- **Programmatic scroll**: Uses `ScrollViewReader` with `.scrollTo(id:, anchor: .top)` and `withAnimation(.easeInOut(duration: 0.4))`
- **Lazy loading**: Notes are rendered in a `LazyVStack` to support arbitrarily long history without performance degradation. Only notes within the visible region (+/- a buffer of 5 notes) are fully rendered.
- **Date range**: Show the past 90 days + 7 future days by default. Extend further into the past as the user scrolls down (infinite scroll with lazy date generation).

### 5.3 Editing

- Each note section is an inline editable area. The content area uses a simplified version of the existing `MarkdownEditor` (without line numbers).
- **Click to edit**: Clicking anywhere in a note's content area activates editing for that note. Only one note is editable at a time.
- **Auto-save**: Changes save automatically after 1 second of inactivity (debounced), matching existing document save behavior.
- **File creation**: For virtual (future/empty) notes, the `daily/yyyy-MM-dd.md` file is created via `DailyNoteResolver.ensureExists()` on first keystroke.
- **Keyboard navigation**: Tab moves focus to the next day's note. Shift+Tab moves to the previous day.

### 5.4 "Scroll to Today" Floating Button

- **Appears**: When today's date header is scrolled out of the visible viewport
- **Position**: Bottom-center of the note stream pane, 16px from the bottom edge
- **Label**: "Today" with directional chevron icon
- **Action**: Smooth-scroll to today's note with `.easeInOut(duration: 0.4)` animation
- **Disappears**: Fades out when today becomes visible, using `.opacity` transition with `.easeOut(duration: 0.2)`
- **Style**: `.glassEffect(.regular.interactive())` pill shape

---

## 6. Calendar Widget Design

### 6.1 Layout

```
+---------------------------+
|  < February 2026 >        |  Month header with navigation
+---------------------------+
|  Mo  Tu  We  Th  Fr Sa Su |  Day-of-week headers
|                           |
|                        1  |
|   2   3   4   5   6  7  8 |
|   9  10  11  12  13 14 15 |
|  16  17  18  19  20 21 22 |
|  23  24  25  26  27 28  . |
+---------------------------+
```

### 6.2 Month Header

- **Month/Year text**: System font, size 14pt, weight `.semibold`, `.primary` color
- **Navigation chevrons**: `chevron.left` and `chevron.right` SF Symbols, size 12pt, `.secondary` color, with hover state brightening to `.primary`
- **Layout**: HStack with month/year centered, chevrons at leading/trailing edges
- **Padding**: 12px horizontal, 8px vertical

### 6.3 Day-of-Week Headers

- **Font**: System font, size 11pt, weight `.medium`
- **Color**: `.tertiary`
- **Abbreviations**: Mo, Tu, We, Th, Fr, Sa, Su (two-letter, ISO week starting Monday)

### 6.4 Day Cells

Each day is a tappable cell in a 7-column CSS grid:

- **Size**: Equal-width columns, each cell is a square with size determined by `(calendarWidth - 2 * horizontalPadding) / 7`
- **Font**: System font, size 13pt
- **States**:

| State | Style |
|---|---|
| **Today** | Filled circle background in `Color.accentColor`, white text, weight `.bold` |
| **Has notes (with content)** | `.primary` text, weight `.medium`, small 4px accent dot below the number |
| **Has notes (empty)** | `.primary` text, weight `.regular`, no dot |
| **No note exists** | `.secondary` text, weight `.regular` |
| **Overflow days (prev/next month)** | `.quaternary` text (very dimmed), weight `.regular` |
| **Hover** | Subtle circle background in `Color.primary.opacity(0.06)` |
| **Selected (clicked)** | Ring outline in `Color.accentColor`, 1.5px stroke |

### 6.5 Note Indicator Dot

- **Size**: 4px diameter circle
- **Color**: `Color.accentColor.opacity(0.6)`
- **Position**: Centered below the day number, 2px gap
- **Purpose**: Indicates that this date has a daily note file with actual content (not just the template heading)

### 6.6 Calendar Interactions

- **Day click**: Scrolls the note stream to the clicked date. If the date is outside the currently loaded range, extends the range to include it.
- **Month navigation**: Clicking `<` / `>` chevrons transitions to prev/next month with a subtle horizontal slide animation (`.move(edge: .leading)` or `.move(edge: .trailing)`) with `.easeOut(duration: 0.2)`
- **Today shortcut**: Double-clicking the month/year text returns to the current month

---

## 7. State Management

### 7.1 New State in DocumentStore

```swift
@Published var isDailyNotesActive = false     // Whether Daily Notes view is shown
@Published var dailyNotesScrollTarget: Date?  // Target date to scroll to
```

### 7.2 View Activation

The Daily Notes view is activated by setting `isDailyNotesActive = true` on `DocumentStore`. This is analogous to how `isLinksTabSelected` works for the Links tab. In `ContentView`'s detail section, the conditional rendering becomes:

```
if store.isDailyNotesActive {
    DailyNotesView()
} else if store.isLinksTabSelected {
    LinksView()
} else if !store.openFiles.isEmpty {
    // existing editor
}
```

### 7.3 Tab Bar Integration

The "Daily notes" tab appears in the tab bar as a persistent entry (similar to "Links"), using `TabButton` with:
- title: "Daily notes"
- isSelected: bound to `store.isDailyNotesActive`
- isDirty: false
- onClose: nil (persistent, not closable)

Position: After all open file tabs, before the "Links" tab.

### 7.4 Notification

Add a new notification:

```swift
static let showDailyNotes = Notification.Name("showDailyNotes")
```

This is posted by `Cmd+D` and the sidebar entry. The handler sets `isDailyNotesActive = true` and sets `dailyNotesScrollTarget = Date()`.

---

## 8. Transitions & Animation

### 8.1 View Switching

- **Entering Daily Notes**: Crossfade transition, `.opacity` with `.easeOut(duration: 0.2)`, matching the existing animation timing used throughout the app
- **Exiting Daily Notes**: Same crossfade. Triggered by clicking a file in the sidebar or switching to another tab.

### 8.2 Scroll Animations

- **Cmd+D / Calendar click**: `withAnimation(.easeInOut(duration: 0.4))` scroll to target date
- **"Today" floating button**: Same scroll animation

### 8.3 Calendar Month Change

- **Transition**: `.asymmetric` transition -- navigating forward uses `.move(edge: .trailing)` (new month slides in from right), navigating backward uses `.move(edge: .leading)` (new month slides in from left). Duration: `.easeOut(duration: 0.2)`.

### 8.4 Floating Button

- **Appear**: `.transition(.opacity.combined(with: .move(edge: .bottom)))` with `.easeOut(duration: 0.2)`
- **Disappear**: Same transition reversed

---

## 9. Accessibility

- All interactive elements have `.accessibilityLabel` and `.accessibilityHint`
- Calendar days announce: "February 7th, today, has notes" or "February 8th, no notes"
- Date headers use `.accessibilityAddTraits(.isHeader)`
- The "scroll to today" button announces: "Scroll to today's note"
- Keyboard navigation: Arrow keys move between calendar days when calendar is focused
- VoiceOver: Note content areas are standard text editing regions

---

## 10. Edge Cases

- **No workspace open**: Daily Notes sidebar entry and tab are hidden. Cmd+D shows no effect.
- **First-time use**: The `daily/` folder doesn't exist yet. On first activation, create it via `DailyNoteResolver.ensureExists()`. Show today's empty note with the "Start writing..." placeholder.
- **Large history**: Lazy loading ensures performance. Only render notes within the visible scroll region.
- **Midnight rollover**: If the app is open at midnight, the "Today" indicator should update. Use a timer that fires at midnight to refresh the view.
- **Conflicting state**: Activating Daily Notes deactivates `isLinksTabSelected` and vice versa. Opening a file tab deactivates both.

---

## 11. File Structure (New Swift Files)

| File | Purpose |
|---|---|
| `DailyNotesView.swift` | Main Daily Notes view (center pane + calendar sidebar) |
| `DailyNoteSection.swift` | Individual day section (date header + editable content) |
| `CalendarWidget.swift` | Mini calendar month grid widget |
| `DailyNotesStore.swift` | State management for daily notes loading, virtual notes, and scroll tracking |

These follow the existing codebase convention of one primary view per file, with supporting types in the same file when small.
