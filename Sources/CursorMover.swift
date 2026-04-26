import Cocoa

class CursorMover {

    /// Determines the next screen to jump to based on current cursor position.
    /// Returns nil if there are fewer than 2 screens.
    func nextScreen(from screens: [NSScreen]) -> NSScreen? {
        guard screens.count > 1 else { return nil }

        let mouseLocation = NSEvent.mouseLocation

        guard let currentIndex = screenIndex(containing: mouseLocation, in: screens) else {
            NSLog("[D-Switch] Cursor not on any known screen, targeting first display")
            return screens.first
        }

        let nextIndex = (currentIndex + 1) % screens.count
        return screens[nextIndex]
    }

    /// Warps the cursor to the given CG point and posts a mouse-moved event.
    func warpCursor(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, 
                            mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    /// Returns the center of a screen in CG coordinates (top-left origin).
    func screenCenter(_ screen: NSScreen) -> CGPoint {
        nsToCG(NSPoint(x: screen.frame.midX, y: screen.frame.midY))
    }

    /// Converts a point from NS coordinates (bottom-left origin) to CG coordinates (top-left origin).
    func nsToCG(_ nsPoint: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: nsPoint.x, y: primaryHeight - nsPoint.y)
    }

    // MARK: - Private

    private func screenIndex(containing point: NSPoint, in screens: [NSScreen]) -> Int? {
        if let idx = screens.firstIndex(where: { $0.frame.contains(point) }) {
            return idx
        }
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, screen) in screens.enumerated() {
            let d = distance(from: point, to: screen.frame)
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }
        return bestDistance < 5 ? bestIndex : nil
    }

    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = Swift.max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = Swift.max(rect.minY - point.y, 0, point.y - rect.maxY)
        return sqrt(dx * dx + dy * dy)
    }
}
