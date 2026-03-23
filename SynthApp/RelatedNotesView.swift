import SwiftUI

// MARK: - Related Notes Section

struct RelatedNote: Identifiable, Equatable {
    let url: URL
    let title: String
    let score: Int
    let reason: String
    var id: URL { url }
}

struct RelatedNotesSection: View {
    let noteTitle: String
    let noteURL: URL?
    var backlinkIndex: BacklinkIndex
    var tagIndex: TagIndex
    let onNavigate: (URL) -> Void
    @AppStorage("relatedNotesExpanded") private var isExpanded = false
    @State private var cachedNotes: [RelatedNote] = []

    // MARK: - Body

    var body: some View {
        if !cachedNotes.isEmpty {
            VStack(spacing: 0) {
                Divider()

                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cachedNotes) { note in
                            RelatedNoteRow(
                                title: note.title,
                                reason: note.reason
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onNavigate(note.url) }
                            .accessibilityLabel("Related note \(note.title)")
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 4) {
                        Text("Related Notes (\(cachedNotes.count))")
                            .font(Theme.uiSwiftUIFont(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .animation(.easeOut(duration: 0.15), value: isExpanded)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }

        Color.clear.frame(height: 0)
            .task(id: noteTitle) { recompute() }
            .onChange(of: backlinkIndex.incomingLinks.count) { _, _ in recompute() }
            .onChange(of: tagIndex.tagToFiles.count) { _, _ in recompute() }
    }

    // MARK: - Computation (runs outside view body)

    private func recompute() {
        guard !noteTitle.isEmpty else {
            cachedNotes = []
            return
        }
        let currentTitle = noteTitle.lowercased()
        var candidates: [URL: Int] = [:]
        var reasons: [URL: [String]] = [:]

        // 1. Shared tags (weight: 2 per shared tag)
        let currentNoteTags: Set<String> = noteURL.map { tagIndex.tags(for: $0) } ?? []
        for tag in currentNoteTags {
            for fileURL in tagIndex.notes(for: tag) where fileURL != noteURL {
                candidates[fileURL, default: 0] += 2
                reasons[fileURL, default: []].append("#\(tag)")
            }
        }

        // 2. Mutual backlinks (weight: 3)
        let currentOutgoing: Set<String> = noteURL.map {
            backlinkIndex.outgoing(from: $0)
        } ?? []
        let currentIncoming = backlinkIndex.links(to: noteTitle)
        for fileURL in currentIncoming where fileURL != noteURL {
            let theirTitle = fileURL.deletingPathExtension().lastPathComponent.lowercased()
            if currentOutgoing.contains(theirTitle) {
                candidates[fileURL, default: 0] += 3
                reasons[fileURL, default: []].append("mutual link")
            }
        }

        // 3. Common link targets + 4. Shared incoming (single pass over all note URLs)
        let allURLs = collectAllNoteURLs()
        for otherURL in allURLs {
            let otherTitle = otherURL.deletingPathExtension().lastPathComponent.lowercased()
            guard otherTitle != currentTitle else { continue }

            // Shared outgoing targets
            let otherOutgoing = backlinkIndex.outgoing(from: otherURL)
            let sharedTargets = currentOutgoing.intersection(otherOutgoing)
            if !sharedTargets.isEmpty {
                candidates[otherURL, default: 0] += sharedTargets.count
                for target in sharedTargets.prefix(2) {
                    reasons[otherURL, default: []].append("links to [[\(target)]]")
                }
            }

            // Shared incoming sources
            let otherIncoming = backlinkIndex.links(to: otherTitle)
            let sharedSources = currentIncoming.intersection(otherIncoming)
            if !sharedSources.isEmpty {
                candidates[otherURL, default: 0] += sharedSources.count
            }
        }

        cachedNotes = candidates
            .filter { $0.value >= 2 }
            .map { (url, score) in
                RelatedNote(
                    url: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    score: score,
                    reason: Self.formatReason(reasons[url] ?? [])
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(8)
            .map { $0 }
    }

    private func collectAllNoteURLs() -> Set<URL> {
        var urls: Set<URL> = []
        for urlSet in tagIndex.tagToFiles.values {
            urls.formUnion(urlSet)
        }
        for urlSet in backlinkIndex.incomingLinks.values {
            urls.formUnion(urlSet)
        }
        return urls
    }

    private static func formatReason(_ reasons: [String]) -> String {
        let unique = Array(Set(reasons))
        if unique.isEmpty { return "related content" }

        var parts: [String] = []
        let tags = unique.filter { $0.hasPrefix("#") }
        let links = unique.filter { $0.hasPrefix("links to") }
        let mutual = unique.filter { $0 == "mutual link" }

        if !tags.isEmpty {
            let tagList = tags.prefix(3).joined(separator: ", ")
            parts.append("shares \(tagList)")
        }
        if !mutual.isEmpty {
            parts.append("mutual link")
        }
        if !links.isEmpty {
            let linkList = links.prefix(2).joined(separator: ", ")
            parts.append(linkList)
        }

        return parts.joined(separator: " * ")
    }
}

// MARK: - Related Note Row

struct RelatedNoteRow: View {
    let title: String
    let reason: String
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "doc.text")
                    .font(Theme.uiSwiftUIFont(size: 12))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(Theme.uiSwiftUIFont(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            if !reason.isEmpty {
                Text(reason)
                    .font(Theme.uiSwiftUIFont(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        )
        .onHover { isHovering = $0 }
    }
}
