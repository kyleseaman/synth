import SwiftUI
import AppKit

struct LinksView: View {
    @Environment(LinkStore.self) var linkStore
    @Environment(DocumentStore.self) var store
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if linkStore.links.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(linkStore.links, id: \.identifier) { link in
                            LinkRow(
                                link: link,
                                onOpen: { open(link: link) },
                                onCopy: { copy(link: link) },
                                onDelete: { linkStore.removeLink(identifier: link.identifier) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.textBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Links")
                .font(.system(size: 16, weight: .semibold))

            Text("\(linkStore.links.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                store.showLinkCaptureModal()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Add Link")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No links yet")
                .foregroundStyle(.secondary)
            Text("Press ⌘⇧L to add one")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(link: SavedLink) {
        guard let url = URL(string: link.urlString) else { return }
        openURL(url)
    }

    private func copy(link: SavedLink) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link.urlString, forType: .string)
    }
}

struct LinkRow: View {
    let link: SavedLink
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                Text(link.urlString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .opacity(isHovering ? 1 : 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            isHovering ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open", action: onOpen)
            Button("Copy", action: onCopy)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var displayTitle: String {
        guard let url = URL(string: link.urlString), let host = url.host else {
            return link.urlString
        }
        return host
    }
}
