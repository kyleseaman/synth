import AppKit

final class GlobalHotkeyMonitor {
    private let requiredKey: String
    private let requiredModifiers: NSEvent.ModifierFlags
    private let trigger: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(key: String, modifiers: NSEvent.ModifierFlags, trigger: @escaping () -> Void) {
        self.requiredKey = key.lowercased()
        self.requiredModifiers = modifiers
        self.trigger = trigger
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matches(event) {
                self.trigger()
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard !NSApp.isActive else { return }
            if self.matches(event) {
                self.trigger()
            }
        }
    }

    private func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func matches(_ event: NSEvent) -> Bool {
        let keyText = event.charactersIgnoringModifiers?.lowercased()
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return keyText == requiredKey && modifiers == requiredModifiers
    }
}
