import Cocoa
import ApplicationServices

struct FocusResult {
    let cursorTarget: CGPoint  // Best landing point in CG coordinates
    let appName: String?
}

/// Detects the topmost window on the target display, activates it, and determines
/// the best cursor landing point using a four-tier fallback:
///
/// 1. Text caret / insertion point position (via AX)
/// 2. Focused UI element center (via AX)
/// 3. Window center
/// 4. (caller provides screen center if no window found)
class WindowFocusManager {

    func focusTopWindow(on targetScreen: NSScreen) -> FocusResult? {
        guard let window = topWindow(on: targetScreen) else {
            NSLog("[D-Switch] Focus: no focusable window on target display")
            return nil
        }

        let screenRect = screenCGRect(targetScreen)

        // Query the AX focus point BEFORE activation — the app's AX tree retains
        // its last focused element even while backgrounded, and this avoids timing issues.
        let axPoint = focusedPoint(for: window.pid, clampedTo: screenRect)

        // Activate the app
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            let activated = app.activate(options: [])
            if !activated {
                NSLog("[D-Switch] Focus: failed to activate \(app.localizedName ?? "unknown") (PID \(window.pid))")
            }
        } else {
            NSLog("[D-Switch] Focus: could not resolve app for PID \(window.pid)")
        }

        let target = axPoint ?? window.center
        return FocusResult(cursorTarget: target, appName: window.ownerName)
    }

    // MARK: - AX Focus Detection

    /// Attempts to find the precise focus point within an app, trying in order:
    /// 1. Text caret / insertion point bounds
    /// 2. Focused UI element center
    /// Returns nil if AX is unavailable or the element is off-screen.
    private func focusedPoint(for pid: pid_t, clampedTo screenRect: CGRect) -> CGPoint? {
        let axApp = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let ref = focusedRef else {
            return nil
        }
        let element = ref as! AXUIElement

        // Tier 1: text caret position
        if let caretPoint = caretPosition(of: element, clampedTo: screenRect) {
            return caretPoint
        }

        // Tier 2: focused element center
        if let elementCenter = elementCenter(of: element, clampedTo: screenRect) {
            return elementCenter
        }

        return nil
    }

    /// Gets the screen position of the text insertion point (caret) for text elements.
    private func caretPosition(of element: AXUIElement, clampedTo screenRect: CGRect) -> CGPoint? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        ) == .success, let range = rangeRef else {
            return nil
        }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsRef
        ) == .success, let bounds = boundsRef else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // A zero-width rect is a collapsed caret — use its left edge
        let point = CGPoint(
            x: rect.minX + rect.width / 2,
            y: rect.minY + rect.height / 2
        )

        guard rect.height > 0 && screenRect.contains(point) else { return nil }
        return point
    }

    /// Gets the center point of a focused UI element.
    private func elementCenter(of element: AXUIElement, clampedTo screenRect: CGRect) -> CGPoint? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &posRef
        ) == .success,
              AXUIElementCopyAttributeValue(
            element, kAXSizeAttribute as CFString, &sizeRef
        ) == .success,
              let posVal = posRef, let sizeVal = sizeRef else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
            return nil
        }

        // Skip trivially small elements (decorative, invisible)
        guard size.width > 5 && size.height > 5 else { return nil }

        let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)

        guard screenRect.contains(center) else { return nil }
        return center
    }

    // MARK: - Window Detection

    private struct WindowInfo {
        let pid: pid_t
        let center: CGPoint
        let ownerName: String?
    }

    private func topWindow(on screen: NSScreen) -> WindowInfo? {
        let screenRect = screenCGRect(screen)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return nil
        }

        let selfPID = ProcessInfo.processInfo.processIdentifier

        for entry in windowList {
            guard let layer = entry[kCGWindowLayer] as? Int, layer == 0 else { continue }
            guard let pid = entry[kCGWindowOwnerPID] as? pid_t, pid != selfPID else { continue }

            guard let boundsDict = entry[kCGWindowBounds] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width > 50 && rect.height > 50 else { continue }

            guard screenRect.intersects(rect) else { continue }

            let intersection = screenRect.intersection(rect)
            let overlapArea = intersection.width * intersection.height
            let windowArea = rect.width * rect.height
            guard windowArea > 0 && (overlapArea / windowArea) > 0.1 else { continue }

            let centerX = max(screenRect.minX + 1, min(screenRect.maxX - 1, rect.midX))
            let centerY = max(screenRect.minY + 1, min(screenRect.maxY - 1, rect.midY))

            return WindowInfo(
                pid: pid,
                center: CGPoint(x: centerX, y: centerY),
                ownerName: entry[kCGWindowOwnerName] as? String
            )
        }

        return nil
    }

    private func screenCGRect(_ screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsFrame = screen.frame
        return CGRect(
            x: nsFrame.origin.x,
            y: primaryHeight - nsFrame.origin.y - nsFrame.height,
            width: nsFrame.width,
            height: nsFrame.height
        )
    }
}
