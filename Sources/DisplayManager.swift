import Cocoa

class DisplayManager {

    /// Returns all screens sorted in a deterministic spatial order:
    /// left-to-right, then top-to-bottom (in CG coordinates).
    /// Falls back to CGDirectDisplayID as a stable tiebreaker.
    func orderedScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return screens }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        return screens.sorted { a, b in
            let aOrigin = cgOrigin(for: a, primaryHeight: primaryHeight)
            let bOrigin = cgOrigin(for: b, primaryHeight: primaryHeight)

            // Left-to-right
            if aOrigin.x != bOrigin.x {
                return aOrigin.x < bOrigin.x
            }
            // Top-to-bottom
            if aOrigin.y != bOrigin.y {
                return aOrigin.y < bOrigin.y
            }
            // Stable tiebreaker: display ID
            return displayID(for: a) < displayID(for: b)
        }
    }

    /// Converts an NSScreen's origin to CG coordinates (top-left origin system).
    private func cgOrigin(for screen: NSScreen, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(
            x: screen.frame.origin.x,
            y: primaryHeight - screen.frame.origin.y - screen.frame.height
        )
    }

    /// Extracts the CGDirectDisplayID from an NSScreen.
    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
