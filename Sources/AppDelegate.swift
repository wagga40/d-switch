import Cocoa

enum CursorLandingMode: String {
    case smartFocus
    case displayCenter

    static let `default`: CursorLandingMode = .smartFocus
    static let storageKey = "cursorLandingMode"
    static let legacyAutoFocusKey = "autoFocusTopWindow"

    static func load() -> CursorLandingMode {
        let defaults = UserDefaults.standard
        // One-time migration from the old boolean key.
        if let raw = defaults.string(forKey: storageKey),
           let mode = CursorLandingMode(rawValue: raw) {
            return mode
        }
        if defaults.object(forKey: legacyAutoFocusKey) != nil {
            let migrated: CursorLandingMode = defaults.bool(forKey: legacyAutoFocusKey) ? .smartFocus : .displayCenter
            defaults.set(migrated.rawValue, forKey: storageKey)
            defaults.removeObject(forKey: legacyAutoFocusKey)
            return migrated
        }
        return .default
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }

    var displayName: String {
        switch self {
        case .smartFocus:    return "Topmost Window (Smart)"
        case .displayCenter: return "Display Center"
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let gestureManager = GestureManager()
    private let displayManager = DisplayManager()
    private let cursorMover = CursorMover()
    private let windowFocusManager = WindowFocusManager()
    private let overlayManager = OverlayFeedbackManager()
    private var recorderWindow: ShortcutRecorderWindow?

    private var currentShortcut: Shortcut = .default
    private var landingMode: CursorLandingMode = .default
    private var ringPreset: RingPreset = .default
    private var fourFingerTapEnabled = true

    private var shortcutMenuItem: NSMenuItem!
    private var landingModeItems: [CursorLandingMode: NSMenuItem] = [:]
    private var ringPresetItems: [RingPreset: NSMenuItem] = [:]
    private var launchAtLoginItem: NSMenuItem!
    private var accessibilityStatusItem: NSMenuItem!
    private var fourFingerTapItem: NSMenuItem!

    private static let fourFingerTapEnabledKey = "fourFingerTapEnabled"
    private static let didShowSingleDisplayHintKey = "didShowSingleDisplayHint"

    private static func loadFourFingerTapEnabled() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: fourFingerTapEnabledKey) != nil else { return true }
        return defaults.bool(forKey: fourFingerTapEnabledKey)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        currentShortcut = Shortcut.load()
        landingMode = CursorLandingMode.load()
        ringPreset = RingPreset.current()
        fourFingerTapEnabled = Self.loadFourFingerTapEnabled()

        setupMenuBar()
        registerHotkey()
        startGestureDetection()
        checkAccessibility()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.toolTip = "D-Switch: move cursor to the next display"
            button.setAccessibilityLabel("D-Switch: move cursor to the next display")
            let symbolNames = ["rectangle.2.swap", "display.2", "arrow.left.arrow.right"]
            var found = false
            for name in symbolNames {
                if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Move cursor to next display") {
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
        menu.delegate = self

        let titleItem = NSMenuItem(title: "D-Switch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        shortcutMenuItem = NSMenuItem(title: shortcutLabel(), action: nil, keyEquivalent: "")
        shortcutMenuItem.isEnabled = false
        menu.addItem(shortcutMenuItem)

        menu.addItem(NSMenuItem.separator())

        let moveItem = NSMenuItem(title: "Move Cursor Now", action: #selector(moveCursorAction), keyEquivalent: "")
        moveItem.target = self
        menu.addItem(moveItem)

        let changeShortcutItem = NSMenuItem(title: "Change Shortcut\u{2026}", action: #selector(changeShortcut), keyEquivalent: "")
        changeShortcutItem.target = self
        menu.addItem(changeShortcutItem)

        let resetShortcutItem = NSMenuItem(title: "Reset Shortcut", action: #selector(resetShortcut), keyEquivalent: "")
        resetShortcutItem.target = self
        menu.addItem(resetShortcutItem)

        fourFingerTapItem = NSMenuItem(title: "Four-Finger Tap", action: #selector(toggleFourFingerTap), keyEquivalent: "")
        fourFingerTapItem.target = self
        fourFingerTapItem.state = fourFingerTapEnabled ? .on : .off
        menu.addItem(fourFingerTapItem)

        menu.addItem(NSMenuItem.separator())

        // Cursor Lands At submenu
        let landingItem = NSMenuItem(title: "Cursor Lands At", action: nil, keyEquivalent: "")
        let landingSubmenu = NSMenu()
        for mode in [CursorLandingMode.smartFocus, .displayCenter] {
            let item = NSMenuItem(title: mode.displayName, action: #selector(selectLandingMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (mode == landingMode) ? .on : .off
            landingSubmenu.addItem(item)
            landingModeItems[mode] = item
        }
        landingItem.submenu = landingSubmenu
        menu.addItem(landingItem)

        // Ring Animation submenu
        let ringItem = NSMenuItem(title: "Ring Animation", action: nil, keyEquivalent: "")
        let ringSubmenu = NSMenu()
        for preset in RingPreset.allCases {
            let item = NSMenuItem(title: preset.displayName, action: #selector(selectRingPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (preset == ringPreset) ? .on : .off
            ringSubmenu.addItem(item)
            ringPresetItems[preset] = item
        }
        ringItem.submenu = ringSubmenu
        menu.addItem(ringItem)

        menu.addItem(NSMenuItem.separator())

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = LoginItemManager.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        accessibilityStatusItem = NSMenuItem(title: accessibilityStatusTitle(), action: nil, keyEquivalent: "")
        accessibilityStatusItem.isEnabled = false
        menu.addItem(accessibilityStatusItem)

        let accessibilityItem = NSMenuItem(title: "Open Accessibility Settings\u{2026}", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func shortcutLabel() -> String {
        if fourFingerTapEnabled {
            return "Shortcut: \(currentShortcut.displayString)  \u{00B7}  4-finger tap"
        }
        return "Shortcut: \(currentShortcut.displayString)"
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = LoginItemManager.isEnabled ? .on : .off
        accessibilityStatusItem.title = accessibilityStatusTitle()
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        let registered = hotkeyManager.register(shortcut: currentShortcut) { [weak self] in
            self?.moveCursor()
        }
        if !registered {
            showHotkeyRegistrationAlert(for: currentShortcut)
        }
    }

    @objc private func changeShortcut() {
        let recorder = ShortcutRecorderWindow()
        recorderWindow = recorder
        recorder.present { [weak self] shortcut in
            guard let self = self else { return }
            self.recorderWindow = nil
            guard let shortcut = shortcut else { return }
            guard self.hotkeyManager.update(to: shortcut) else {
                _ = self.hotkeyManager.update(to: self.currentShortcut)
                self.showHotkeyRegistrationAlert(for: shortcut)
                return
            }
            self.currentShortcut = shortcut
            shortcut.save()
            self.shortcutMenuItem.title = self.shortcutLabel()
        }
    }

    @objc private func resetShortcut() {
        guard hotkeyManager.update(to: .default) else {
            _ = hotkeyManager.update(to: currentShortcut)
            showHotkeyRegistrationAlert(for: .default)
            return
        }
        currentShortcut = .default
        currentShortcut.save()
        shortcutMenuItem.title = shortcutLabel()
    }

    private func showHotkeyRegistrationAlert(for shortcut: Shortcut) {
        let alert = NSAlert()
        alert.messageText = "Couldn't register \(shortcut.displayString)"
        let fallback = fourFingerTapEnabled ? "the menu bar and four-finger tap" : "the menu bar"
        alert.informativeText = "That shortcut may already be used by macOS or another app. D-Switch still works from \(fallback)."
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Gesture

    private func startGestureDetection() {
        guard fourFingerTapEnabled else { return }
        gestureManager.start { [weak self] in
            self?.moveCursor()
        }
    }

    @objc private func toggleFourFingerTap() {
        fourFingerTapEnabled.toggle()
        UserDefaults.standard.set(fourFingerTapEnabled, forKey: Self.fourFingerTapEnabledKey)
        fourFingerTapItem.state = fourFingerTapEnabled ? .on : .off
        shortcutMenuItem.title = shortcutLabel()

        if fourFingerTapEnabled {
            startGestureDetection()
        } else {
            gestureManager.stop()
        }
    }

    // MARK: - Cursor Movement

    @objc private func moveCursorAction() {
        moveCursor()
    }

    private func moveCursor() {
        let screens = displayManager.orderedScreens()
        guard screens.count > 1 else {
            showSingleDisplayHintIfNeeded()
            return
        }
        guard let target = cursorMover.nextScreen(from: screens) else { return }

        let landingPoint: CGPoint
        switch landingMode {
        case .smartFocus:
            if let result = windowFocusManager.focusTopWindow(on: target) {
                landingPoint = result.cursorTarget
            } else {
                landingPoint = cursorMover.screenCenter(target)
            }
        case .displayCenter:
            landingPoint = cursorMover.screenCenter(target)
        }

        cursorMover.warpCursor(to: landingPoint)
        overlayManager.showHint(at: landingPoint, on: target)
    }

    private func showSingleDisplayHintIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.didShowSingleDisplayHintKey) else { return }
        defaults.set(true, forKey: Self.didShowSingleDisplayHintKey)

        let alert = NSAlert()
        alert.messageText = "Only one display is connected"
        alert.informativeText = "D-Switch moves the cursor between displays. Connect another display and try again."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func selectLandingMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = CursorLandingMode(rawValue: raw) else { return }
        landingMode = mode
        mode.save()
        for (m, item) in landingModeItems {
            item.state = (m == mode) ? .on : .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let target = !LoginItemManager.isEnabled
        if LoginItemManager.setEnabled(target) {
            launchAtLoginItem.state = LoginItemManager.isEnabled ? .on : .off
        } else {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Launch at Login"
            alert.informativeText = "macOS rejected the change. You can manage login items in System Settings \u{2192} General \u{2192} Login Items."
            alert.alertStyle = .warning
            alert.runModal()
            launchAtLoginItem.state = LoginItemManager.isEnabled ? .on : .off
        }
    }

    @objc private func selectRingPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = RingPreset(rawValue: raw) else { return }
        ringPreset = preset
        preset.save()
        for (p, item) in ringPresetItems {
            item.state = (p == preset) ? .on : .off
        }
    }

    // MARK: - Permissions

    private static let didPromptAccessibilityKey = "didPromptAccessibility"

    private func accessibilityStatusTitle() -> String {
        isAccessibilityTrusted() ? "Accessibility: Enabled" : "Accessibility: Needed for smart landing"
    }

    private func isAccessibilityTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func checkAccessibility() {
        let trusted = isAccessibilityTrusted()
        let defaults = UserDefaults.standard
        if trusted {
            NSLog("[D-Switch] Accessibility: trusted")
            defaults.set(true, forKey: Self.didPromptAccessibilityKey)
            return
        }
        // Auto-open System Settings only on the first launch where permission is missing.
        // After that, rely on the menu item so a stale trust entry doesn't reopen Settings every launch.
        if defaults.bool(forKey: Self.didPromptAccessibilityKey) {
            NSLog("[D-Switch] Accessibility: not trusted — use the menu to open Settings.")
            return
        }
        NSLog("[D-Switch] Accessibility: not trusted — opening System Settings. Grant access to enable precise focus-point detection.")
        defaults.set(true, forKey: Self.didPromptAccessibilityKey)
        openAccessibilityPane()
    }

    @objc private func openAccessibilitySettings() {
        openAccessibilityPane()
    }

    private func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
