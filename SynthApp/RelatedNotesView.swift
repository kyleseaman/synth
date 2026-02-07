import SwiftUI

// MARK: - Related Notes Section

struct RelatedNotesSection: View {
    let noteTitle: String
    let noteURL: URL?
    @ObservedObject var backlinkIndex: BacklinkIndex
    @ObservedObject var tagIndex: TagIndex
    let onNavigate: (URL) -> Void
    @AppStorage("relatedNotesExpanded") private var isExpanded = false

    // MARK: - Related Notes Computation

    var relatedNotes: [(url: URL, title: String, score: Int, reason: String)] {
        guard !noteTitle.isEmpty else { return [] }
        let currentTitle = noteTitle.lowercased()

        // Gather all candidate notes from both indexes
        var candidates: [URL: Int] = [:]
        var reasons: [URL: [String]] = [:]

        // 1. Shared tags (weight: 2 per shared tag)
        let currentNoteTags: Set<String> = noteURL.map { tagIndex.tags(for: $0) } ?? []
        if !currentNoteTags.isEmpty {
            for tag in currentNoteTags {
                let filesWithTag = tagIndex.notes(for: tag)
                for fileURL in filesWithTag {
                    guard fileURL != noteURL else { continue }
                    candidates[fileURL, default: 0] += 2
                    if reasons[fileURL] == nil { reasons[fileURL] = [] }
                    reasons[fileURL]?.append("#\(tag)")
                }
            }
        }

        // 2. Mutual backlinks (weight: 3)
        // Notes that link to current AND current links to them
        let currentOutgoing: Set<String> = noteURL.map {
            backlinkIndex.outgoing(from: $0)
        } ?? []
        let currentIncoming = backlinkIndex.links(to: noteTitle)
        let mutualLinks = currentIncoming.filter { url in
            let theirTitle = url.deletingPathExtension().lastPathComponent.lowercased()
            return currentOutgoing.contains(theirTitle)
        }
        for fileURL in mutualLinks {
            guard fileURL != noteURL else { continue }
            candidates[fileURL, default: 0] += 3
            if reasons[fileURL] == nil { reasons[fileURL] = [] }
            reasons[fileURL]?.append("mutual link")
        }

        // 3. Common link targets (weight: 1 per shared target)
        for otherURL in allNoteURLs() {
            let otherTitle = otherURL.deletingPathExtension().lastPathComponent.lowercased()
            guard otherTitle != currentTitle else { continue }
            let otherOutgoing = backlinkIndex.outgoing(from: otherURL)
            let sharedTargets = currentOutgoing.intersection(otherOutgoing)
            if !sharedTargets.isEmpty {
                candidates[otherURL, default: 0] += sharedTargets.count
                if reasons[otherURL] == nil { reasons[otherURL] = [] }
                for target in sharedTargets.prefix(2) {
                    reasons[otherURL]?.append("links to [[\(target)]]")
                }
            }
        }

        // 4. Shared incoming links (weight: 1 per shared source)
        let incomingURLs = currentIncoming
        for otherURL in allNoteURLs() {
            let otherTitle = otherURL.deletingPathExtension().lastPathComponent.lowercased()
            guard otherTitle != currentTitle else { continue }
            let otherIncoming = backlinkIndex.links(to: otherTitle)
            let sharedSources = incomingURLs.intersection(otherIncoming)
            if !sharedSources.isEmpty {
                candidates[otherURL, default: 0] += sharedSources.count
            }
        }

        // Filter by minimum score and sort
        return candidates
            .filter { $0.value >= 2 }
            .map { (url, score) in
                let title = url.deletingPathExtension().lastPathComponent
                let reasonList = reasons[url] ?? []
                let reason = formatReason(reasonList)
                return (url: url, title: title, score: score, reason: reason)
            }
            .sorted { $0.score > $1.score }
            .prefix(8)
            .map { $0 }
    }

    // MARK: - Body

    var body: some View {
        let notes = relatedNotes
        if !notes.isEmpty {
            VStack(spacing: 0) {
                Divider()

                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(notes, id: \.url) { note in
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
                        Text("Related Notes (\(notes.count))")
                            .font(.system(size: 12, weight: .medium))
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
    }

    // MARK: - Helpers

    private func allNoteURLs() -> Set<URL> {
        var urls: Set<URL> = []
        for urlSet in tagIndex.tagToFiles.values {
            urls.formUnion(urlSet)
        }
        for urlSet in backlinkIndex.incomingLinks.values {
            urls.formUnion(urlSet)
        }
        return urls
    }

    private func formatReason(_ reasons: [String]) -> String {
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
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            if !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 11))
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
