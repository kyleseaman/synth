import SwiftUI

// MARK: - Backlinks Section

struct BacklinksSection: View {
    let noteTitle: String
    @ObservedObject var backlinkIndex: BacklinkIndex
    let onNavigate: (URL) -> Void
    @AppStorage("backlinksExpanded") private var isExpanded = true

    var backlinks: [(url: URL, title: String, snippet: String, relativePath: String)] {
        let currentTitle = noteTitle.lowercased()
        let urls = backlinkIndex.links(to: noteTitle)
        return urls.compactMap { url in
            let title = url.deletingPathExtension().lastPathComponent
            // Exclude self-references
            guard title.lowercased() != currentTitle else { return nil }
            let snippet = backlinkIndex.snippet(from: url, to: noteTitle) ?? ""
            let parent = url.deletingLastPathComponent().lastPathComponent
            return (url: url, title: title, snippet: snippet, relativePath: parent)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        let links = backlinks
        if links.isEmpty {
            VStack(spacing: 0) {
                Text("No backlinks yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 12)
        } else {
            VStack(spacing: 0) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(links.prefix(10), id: \.url) { link in
                            BacklinkRow(
                                title: link.title,
                                snippet: link.snippet,
                                relativePath: link.relativePath,
                                url: link.url,
                                onNavigate: onNavigate
                            )
                            .accessibilityLabel("Link from \(link.title)")
                            .accessibilityHint("Opens \(link.title)")
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 4) {
                        Text("Backlinks (\(links.count))")
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
}

// MARK: - Backlink Row

struct BacklinkRow: View {
    let title: String
    let snippet: String
    let relativePath: String
    let url: URL
    let onNavigate: (URL) -> Void
    @State private var isHovering = false
    @State private var showFullNote = false
    @State private var fullContent: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    if !showFullNote && fullContent == nil {
                        fullContent = try? String(
                            contentsOf: url, encoding: .utf8
                        )
                    }
                    withAnimation(.easeOut(duration: 0.15)) {
                        showFullNote.toggle()
                    }
                } label: {
                    Image(
                        systemName: showFullNote
                            ? "rectangle.compress.vertical"
                            : "rectangle.expand.vertical"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(showFullNote ? "Collapse" : "Show full note")
            }
            .contentShape(Rectangle())
            .onTapGesture { onNavigate(url) }

            if !showFullNote && !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }

            if showFullNote, let content = fullContent {
                Text(content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.03))
                    )
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
