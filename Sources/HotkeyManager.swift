import Cocoa
import Carbon

class HotkeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var currentShortcut: Shortcut?
    fileprivate var onHotkey: (() -> Void)?

    func register(shortcut: Shortcut, callback: @escaping () -> Void) -> Bool {
        unregister()
        self.onHotkey = callback

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            NSLog("[D-Switch] Failed to install Carbon event handler (status: \(installStatus))")
            return false
        }

        return registerCarbonHotkey(shortcut)
    }

    /// Re-registers the Carbon hotkey with a new shortcut, keeping the existing callback.
    func update(to shortcut: Shortcut) -> Bool {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        return registerCarbonHotkey(shortcut)
    }

    private func registerCarbonHotkey(_ shortcut: Shortcut) -> Bool {
        // "DSWT" as FourCharCode: D=0x44 S=0x53 W=0x57 T=0x54
        let hotKeyID = EventHotKeyID(signature: 0x44535754, id: 1)

        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            NSLog("[D-Switch] Failed to register hotkey \(shortcut.displayString) (status: \(registerStatus)). The shortcut may conflict with another app. Use the menu bar item to move the cursor.")
            currentShortcut = nil
            return false
        } else {
            NSLog("[D-Switch] Registered global hotkey: \(shortcut.displayString)")
            currentShortcut = shortcut
            return true
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        currentShortcut = nil
        onHotkey = nil
    }

    deinit {
        unregister()
    }
}

// C-compatible callback — must not capture context
private func carbonHotkeyHandler(
    _: EventHandlerCallRef?,
    _: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else {
        return OSStatus(eventNotHandledErr)
    }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.onHotkey?()
    }
    return noErr
}
