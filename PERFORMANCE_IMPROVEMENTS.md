# Synth App Performance Improvement Recommendations

This document outlines performance improvement opportunities discovered through code review. The recommendations are organized by impact level and implementation complexity.

---

## High Impact Improvements

### 1. File Tree Scanning - Synchronous I/O on Main Thread
**Location:** `FileTreeNode.swift:18-42`

**Issue:** The `scan()` method performs synchronous file system I/O on the main thread, which can cause UI freezes with large workspaces.

```swift
static func scan(_ url: URL) -> [FileTreeNode] {
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: keys
    ) else { return [] }
    // ... synchronous recursive scan
}
```

**Recommendation:**
- Move file tree scanning to a background thread using `Task.detached(priority: .userInitiated)`
- Use a streaming approach that emits partial results
- Cache resource values instead of fetching them multiple times per file

**Implementation Sketch:**
```swift
static func scanAsync(_ url: URL) async -> [FileTreeNode] {
    await Task.detached(priority: .userInitiated) {
        scan(url)
    }.value
}
```

---

### 2. Index Rebuilding - Reading All Files Synchronously
**Location:** `NoteIndex.swift:381-408`, `BacklinkIndex.swift:24-43`, `TagIndex.swift:31-47`, `PeopleIndex.swift:52-74`

**Issue:** All four indexes (NoteIndex, BacklinkIndex, TagIndex, PeopleIndex) read file contents synchronously during rebuild:

```swift
for file in files {
    guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
    // process content...
}
```

**Recommendation:**
- Parallelize file reading using `withTaskGroup`
- Use `FileHandle` with buffered reading for large files
- Implement lazy content loading - only read full content when needed for search
- Consider a unified file scanner that all indexes share (single pass)

**Implementation Sketch:**
```swift
func rebuildAsync(fileTree: [FileTreeNode]) async {
    await withTaskGroup(of: (URL, String?).self) { group in
        for file in files {
            group.addTask {
                (file.url, try? String(contentsOf: file.url, encoding: .utf8))
            }
        }
        for await (url, content) in group {
            if let content { processFile(url, content) }
        }
    }
}
```

---

### 3. Redundant Index Rebuilds - Quadruple Rebuild on Workspace Events
**Location:** `DocumentStore.swift:523-529`

**Issue:** When applying scan results, four separate rebuilds occur:

```swift
private func applyScanResult(_ scanResult: WorkspaceScanResult, workspace: URL) {
    fileTree = scanResult.tree
    noteIndex.rebuild(from: scanResult.tree, workspace: workspace)  // Reads all files
    mediaFiles = scanResult.media
    backlinkIndex.rebuild(fileTree: scanResult.tree)                // Reads all files AGAIN
    tagIndex.rebuild(fileTree: scanResult.tree)                     // Reads all files AGAIN
    peopleIndex.rebuild(fileTree: scanResult.tree)                  // Reads all files AGAIN
}
```

**Recommendation:**
- Implement a **unified indexer** that reads each file once and populates all indexes in a single pass
- Create a `FileContent` cache during rebuild that indexes can share

**Implementation Sketch:**
```swift
struct UnifiedScanResult {
    let tree: [FileTreeNode]
    let media: [URL]
    let fileContents: [URL: String]  // Shared cache
}

func applyScanResult(_ result: UnifiedScanResult, workspace: URL) {
    noteIndex.rebuild(from: result.tree, contents: result.fileContents, workspace: workspace)
    backlinkIndex.rebuild(fileTree: result.tree, contents: result.fileContents)
    tagIndex.rebuild(fileTree: result.tree, contents: result.fileContents)
    peopleIndex.rebuild(fileTree: result.tree, contents: result.fileContents)
}
```

---

### 4. Markdown Formatting - Full Re-render on Every Keystroke
**Location:** `MarkdownEditor.swift:1878-1980`

**Issue:** The `textStorage:didProcessEditing` delegate re-applies formatting to the entire paragraph on every character change, which involves multiple regex matches:

```swift
func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask...) {
    guard editedMask.contains(.editedCharacters) else { return }
    let paragraphRange = (textStorage.string as NSString).paragraphRange(for: editedRange)
    highlightParagraph(textStorage, range: paragraphRange)  // 6 regex patterns applied
}
```

**Recommendation:**
- Implement dirty tracking - only re-format if content actually changed
- Use a coalesced update with debouncing for rapid typing
- Consider incremental parsing that only updates changed ranges
- Pre-compile attribute dictionaries instead of creating them per call

**Implementation Sketch:**
```swift
private var pendingFormatRanges: Set<NSRange> = []
private var formatDebouncer: DispatchWorkItem?

func scheduleFormat(range: NSRange) {
    pendingFormatRanges.insert(range)
    formatDebouncer?.cancel()
    formatDebouncer = DispatchWorkItem { [weak self] in
        self?.applyPendingFormats()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: formatDebouncer!)
}
```

---

### 5. Line Position Calculation - O(n) Recalculation
**Location:** `MarkdownEditor.swift:1768-1831`

**Issue:** Line positions are recalculated by iterating through all lines, even when the newline count hasn't changed:

```swift
func updateLinePositions() {
    var newlineCount = 0
    for char in string where char == "\n" { newlineCount += 1 }  // O(n)
    
    if newlineCount == lastNewlineCount && !parent.linePositions.isEmpty {
        return  // Early exit, but still did O(n) work
    }
    // ... full recalculation
}
```

**Recommendation:**
- Track inserted/deleted ranges and update incrementally
- Maintain a running newline count instead of counting each time
- Use `NSLayoutManager` notifications for line fragment changes

---

## Medium Impact Improvements

### 6. Daily Note Backlinks - Synchronous File I/O in View
**Location:** `DailyNotesView.swift:577-587`

**Issue:** Content previews for backlinks read files from disk on the main thread:

```swift
private static func contentPreview(for url: URL) -> String {
    guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return "" }
    // ... synchronous file read
}
```

**Recommendation:**
- Pre-compute and cache content previews during index rebuild
- Load previews asynchronously with `Task.detached`

---

### 7. Image Loading - No Memory Pressure Handling
**Location:** `DocumentStore.swift:167-253`

**Issue:** `WorkspaceImageLoader` uses `NSCache` but doesn't implement memory pressure handling or size limits:

```swift
private let imageCache = NSCache<NSString, NSImage>()
// No countLimit or totalCostLimit set
```

**Recommendation:**
- Set cache limits based on available memory
- Implement `NSCacheDelegate` to handle eviction
- Consider using a LRU cache with configurable size

---

### 8. Orphan Media Cleanup - Full Workspace Enumeration
**Location:** `DocumentStore.swift:541-571`

**Issue:** Cleaning orphaned media enumerates the entire workspace for EACH media file:

```swift
for mediaURL in mediaFiles {
    // Creates a NEW enumerator for each media file
    let enumerator = FileManager.default.enumerator(at: workspace, ...)
    while let fileURL = enumerator?.nextObject() as? URL {
        // Check if content contains filename
    }
}
```

**Recommendation:**
- Build a single set of all referenced media filenames first
- Then check each media file against the set (O(1) lookup vs O(n) enumeration)

**Implementation Sketch:**
```swift
static func cleanOrphanedMedia(mediaFiles: [URL], workspace: URL) -> Set<URL> {
    // Single pass: collect all referenced filenames
    var referencedFilenames: Set<String> = []
    let enumerator = FileManager.default.enumerator(at: workspace, ...)
    while let fileURL = enumerator?.nextObject() as? URL {
        if fileURL.pathExtension == "md",
           let content = try? String(contentsOf: fileURL) {
            // Extract image references and add filenames to set
            referencedFilenames.formUnion(extractImageFilenames(from: content))
        }
    }
    
    // Check each media file against the set
    return Set(mediaFiles.filter { !referencedFilenames.contains($0.lastPathComponent) })
}
```

---

### 9. Note Search - Linear Scan for Filters
**Location:** `NoteIndex.swift:310-341`

**Issue:** Filter matching iterates through all notes even when filters could narrow results first:

```swift
let ranked: [(NoteSearchResult, Int)] = allNotes
    .compactMap { indexed -> (NoteSearchResult, Int)? in
        guard matchesFilters(indexed, query: parsedQuery) else { return nil }
        // ...
    }
```

**Recommendation:**
- Build inverted indexes for tags, paths, and people
- Use set intersection to narrow candidates before scoring
- For `path:` filters, use the file tree structure to prune early

---

### 10. Fuzzy Search - No Early Exit
**Location:** `FileLauncher.swift:33-52`

**Issue:** Fuzzy scoring doesn't exit early when a match is clearly impossible:

```swift
func fuzzyScore(_ query: String) -> Int? {
    // Always iterates through entire string even if match is impossible
    for (index, char) in lower.enumerated() where char == remainder.first {
        // ...
    }
    return nil  // Only returns nil after full scan
}
```

**Recommendation:**
- Add early termination when remaining query can't possibly match remaining string
- Use character frequency pre-check

---

## Lower Impact Improvements

### 11. NotificationCenter Overhead
**Location:** `AutocompleteCoordinator.swift`, `MarkdownEditor.swift`

**Issue:** Multiple NotificationCenter observers are created for autocomplete coordination, adding overhead for each keypress.

**Recommendation:**
- Consider direct delegate pattern for tightly-coupled components
- Batch notification delivery for rapid events

---

### 12. Repeated URL Canonicalization
**Location:** `DocumentStore.swift:911-929`

**Issue:** `canonicalFileURL` and `standardizedFileURL` are called repeatedly for the same URLs:

```swift
private static func canonicalFileURL(_ fileURL: URL) -> URL {
    fileURL.standardizedFileURL.resolvingSymlinksInPath()  // I/O operation
}
```

**Recommendation:**
- Cache canonicalized URLs during operations
- Use identity-based caching for frequently accessed paths

---

### 13. Date Formatter Creation
**Location:** Multiple files

**Issue:** Several date formatters are created as static properties, which is good, but some are created per-call:

```swift
// Good: Static formatter (DailyNoteBacklinks)
private static let titleFormatter: DateFormatter = { ... }()

// Could be improved: Per-view formatter
```

**Recommendation:**
- Audit all date formatter usage
- Centralize formatters in a `DateFormatters` enum

---

### 14. Regex Pattern Compilation
**Location:** `MarkdownFormat`, `NoteIndex`, `TagIndex`, `PeopleIndex`

**Issue:** Regex patterns are compiled once (good), but some operations could use pre-compiled match iterators:

```swift
static let boldPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
```

**Recommendation:**
- Use `Regex` type (Swift 5.7+) for better performance
- Consider combining multiple patterns into a single pass where possible

---

### 15. SwiftUI View Identity
**Location:** `ContentView.swift:260-262`

**Issue:** File tree uses a version number as identity which causes full re-render:

```swift
FileTreeView(nodes: store.fileTree, store: store)
    .id(store.fileTreeVersion)  // Forces full re-render on any change
```

**Recommendation:**
- Use stable identifiers based on file paths
- Implement `Equatable` for `FileTreeNode` properly

---

## Architecture Recommendations

### A. Unified File Content Cache
Create a central service that caches file contents with invalidation:

```swift
actor FileContentCache {
    private var cache: [URL: (content: String, modificationDate: Date)] = [:]
    
    func content(for url: URL) async throws -> String {
        // Check modification date, return cached or reload
    }
    
    func invalidate(_ url: URL) {
        cache.removeValue(forKey: url)
    }
}
```

### B. Background Indexing Service
Move all indexing to a dedicated actor:

```swift
actor IndexingService {
    func rebuildAll(from fileTree: [FileTreeNode]) async -> IndexResult {
        // Single-pass indexing with shared file reading
    }
    
    func updateFile(_ url: URL, content: String) async {
        // Incremental update all indexes
    }
}
```

### C. Incremental Text Storage
Implement a custom `NSTextStorage` subclass that tracks modifications:

```swift
class IncrementalTextStorage: NSTextStorage {
    private var dirtyRanges: [NSRange] = []
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        // Track dirty range instead of immediate re-render
    }
    
    func applyPendingFormats() {
        // Batch format dirty ranges
    }
}
```

---

## Priority Implementation Order

1. **Unified Index Rebuilding** (High impact, medium complexity)
   - Single-pass file reading for all indexes
   - Estimated 4x reduction in I/O during workspace load

2. **Async File Tree Scanning** (High impact, low complexity)
   - Move to background thread
   - Prevents UI freezes on large workspaces

3. **Markdown Format Debouncing** (High impact, medium complexity)
   - Coalesce rapid formatting updates
   - Improves typing responsiveness

4. **Orphan Media Cleanup Optimization** (Medium impact, low complexity)
   - Single-pass reference collection
   - Reduces workspace enumeration from O(n²) to O(n)

5. **Image Cache Limits** (Medium impact, low complexity)
   - Prevent memory exhaustion
   - Add memory pressure handling

---

## Profiling Recommendations

Before implementing, profile with Instruments to validate assumptions:

1. **Time Profiler**: Identify actual hot paths during:
   - Workspace loading
   - Typing in editor
   - File tree navigation

2. **Allocations**: Check for:
   - Excessive string allocations during indexing
   - Image memory growth

3. **System Trace**: Verify:
   - File I/O patterns
   - Main thread blocking

4. **SwiftUI Instruments**: Analyze:
   - View body re-evaluations
   - State change cascades

---

## Summary

The most significant performance gains will come from:

1. **Eliminating redundant file reads** during index rebuilds (4 passes → 1 pass)
2. **Moving file I/O off the main thread** for workspace scanning
3. **Debouncing text formatting** during rapid typing
4. **Optimizing the orphan media cleanup** algorithm

These changes could improve workspace loading time by 50-75% and eliminate typing lag in the editor.
