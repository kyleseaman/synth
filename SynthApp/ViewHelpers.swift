import SwiftUI

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Notification.Name {
    // MARK: - Wiki Link Notifications
    static let wikiLinkTrigger = Notification.Name("wikiLinkTrigger")
    static let wikiLinkDismiss = Notification.Name("wikiLinkDismiss")
    static let wikiLinkQueryUpdate = Notification.Name("wikiLinkQueryUpdate")
    static let wikiLinkSelect = Notification.Name("wikiLinkSelect")
    static let wikiLinkNavigate = Notification.Name("wikiLinkNavigate")
    static let showDailyDate = Notification.Name("showDailyDate")
    static let insertTemplate = Notification.Name("insertTemplate")
    static let formatParagraphNow = Notification.Name("formatParagraphNow")
    static let reloadEditor = Notification.Name("reloadEditor")
}

struct EditorSelectionContext {
    let selectedText: String
    let selectedLineRange: String
}

enum ShortcutHintRules {
    static let revealDelaySeconds: TimeInterval = 1.0

    static func shouldRevealHint(hoverStartDate: Date, currentDate: Date) -> Bool {
        currentDate.timeIntervalSince(hoverStartDate) >= revealDelaySeconds
    }
}

private struct DelayedShortcutHintModifier: ViewModifier {
    let shortcutText: String
    @State private var isPointerHovering = false
    @State private var hoverStartDate: Date?
    @State private var shouldShowHint = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if shouldShowHint {
                    Text(shortcutText)
                        .font(Theme.terminalSwiftUIFont(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                        .offset(y: 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering in
                isPointerHovering = hovering
                if hovering {
                    let hoverDate = Date()
                    hoverStartDate = hoverDate
                    shouldShowHint = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(ShortcutHintRules.revealDelaySeconds))
                        guard isPointerHovering,
                              hoverStartDate == hoverDate,
                              ShortcutHintRules.shouldRevealHint(
                                  hoverStartDate: hoverDate,
                                  currentDate: Date()
                              ) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            shouldShowHint = true
                        }
                    }
                } else {
                    hoverStartDate = nil
                    withAnimation(.easeOut(duration: 0.08)) {
                        shouldShowHint = false
                    }
                }
            }
    }
}

extension View {
    @ViewBuilder
    func keyboardShortcutHint(_ shortcutText: String?) -> some View {
        if let shortcutText {
            modifier(DelayedShortcutHintModifier(shortcutText: shortcutText))
        } else {
            self
        }
    }
}

struct SidebarModeButton: View {
    let label: String
    let icon: String
    let mode: DetailViewMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.55))
        .padding(.vertical, 4)
    }
}
