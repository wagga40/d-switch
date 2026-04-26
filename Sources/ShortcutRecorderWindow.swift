import Cocoa
import Carbon

/// Tiny floating panel that captures the next key-with-modifier the user presses
/// and reports it back via a completion handler. Esc cancels.
class ShortcutRecorderWindow: NSPanel {

    private var localMonitor: Any?
    private var completion: ((Shortcut?) -> Void)?
    private let messageLabel = NSTextField(labelWithString: "Press a shortcut\u{2026}")
    private let hintLabel = NSTextField(labelWithString: "Esc to cancel  \u{00B7}  needs at least one modifier")
    private static let panelSize = NSSize(width: 320, height: 130)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "D-Switch"
        isFloatingPanel = true
        level = .modalPanel
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        collectionBehavior = [.transient, .ignoresCycle]

        let content = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        contentView = content

        messageLabel.font = NSFont.systemFont(ofSize: 17, weight: .medium)
        messageLabel.alignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(messageLabel)

        hintLabel.font = NSFont.systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -8),
            hintLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 12),
        ])
    }

    /// Shows the recorder. `completion(nil)` means cancelled.
    func present(completion: @escaping (Shortcut?) -> Void) {
        self.completion = completion
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        installMonitor()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func installMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            // Esc with no modifiers cancels.
            if event.keyCode == UInt16(kVK_Escape)
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.finish(with: nil)
                return nil
            }
            if let shortcut = Shortcut.from(event: event) {
                self.finish(with: shortcut)
                return nil
            }
            // No modifier — flash a hint and swallow the event.
            self.flashHint()
            return nil
        }
    }

    private func flashHint() {
        let original = hintLabel.textColor
        hintLabel.textColor = .systemRed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.hintLabel.textColor = original
        }
    }

    private func finish(with shortcut: Shortcut?) {
        removeMonitor()
        let cb = completion
        completion = nil
        orderOut(nil)
        cb?(shortcut)
    }

    private func removeMonitor() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    deinit {
        removeMonitor()
    }
}
