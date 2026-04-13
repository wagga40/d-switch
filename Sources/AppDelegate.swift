import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let gestureManager = GestureManager()
    private let displayManager = DisplayManager()
    private let cursorMover = CursorMover()
    private let windowFocusManager = WindowFocusManager()
    private let overlayManager = OverlayFeedbackManager()

    private static let autoFocusKey = "autoFocusTopWindow"
    private var autoFocusItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.autoFocusKey: true])
        setupMenuBar()
        registerHotkey()
        startGestureDetection()
        checkAccessibility()
    }

    private var isAutoFocusEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoFocusKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoFocusKey) }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let symbolNames = ["rectangle.2.swap", "display.2", "arrow.left.arrow.right"]
            var found = false
            for name in symbolNames {
                if let image = NSImage(systemSymbolName: name, accessibilityDescription: "D-Switch") {
                    image.isTemplate = true
                    button.image = image
                    found = true
                    break
                }
            }
            if !found {
                button.title = "D"
            }
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "D-Switch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let shortcutItem = NSMenuItem(title: "\u{2318}\u{21E7}M  or  4-finger tap", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem.separator())

        let moveItem = NSMenuItem(title: "Move Cursor Now", action: #selector(moveCursorAction), keyEquivalent: "")
        moveItem.target = self
        menu.addItem(moveItem)

        autoFocusItem = NSMenuItem(title: "Auto-Focus Window", action: #selector(toggleAutoFocus), keyEquivalent: "")
        autoFocusItem.target = self
        autoFocusItem.state = isAutoFocusEnabled ? .on : .off
        menu.addItem(autoFocusItem)

        menu.addItem(NSMenuItem.separator())

        // TODO: Launch at Login
        let launchItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
        launchItem.isEnabled = false
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        hotkeyManager.register { [weak self] in
            self?.moveCursor()
        }
    }

    // MARK: - Gesture

    private func startGestureDetection() {
        gestureManager.start { [weak self] in
            self?.moveCursor()
        }
    }

    // MARK: - Cursor Movement

    @objc private func moveCursorAction() {
        moveCursor()
    }

    private func moveCursor() {
        let screens = displayManager.orderedScreens()
        guard let target = cursorMover.nextScreen(from: screens) else { return }

        // Landing point: AX focus point → window center → screen center
        let landingPoint: CGPoint
        if isAutoFocusEnabled, let result = windowFocusManager.focusTopWindow(on: target) {
            landingPoint = result.cursorTarget
        } else {
            landingPoint = cursorMover.screenCenter(target)
        }

        cursorMover.warpCursor(to: landingPoint)
        overlayManager.showHint(at: landingPoint, on: target)
    }

    @objc private func toggleAutoFocus() {
        isAutoFocusEnabled.toggle()
        autoFocusItem.state = isAutoFocusEnabled ? .on : .off
    }

    // MARK: - Permissions

    private func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            NSLog("[D-Switch] Accessibility: trusted")
        } else {
            NSLog("[D-Switch] Accessibility: not trusted — opening System Settings. Grant access to enable precise focus-point detection.")
            // Open System Settings → Accessibility pane directly
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
