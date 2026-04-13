import Cocoa
import QuartzCore

class OverlayFeedbackManager {

    private var overlayWindow: NSPanel?

    private let ringDiameter: CGFloat = 48
    private let windowSize: CGFloat = 100  // Extra room for scale animation

    /// Shows a brief ring hint at the given CG coordinate on the specified screen.
    func showHint(at cgPoint: CGPoint, on screen: NSScreen) {
        dismissOverlay()

        let nsPoint = cgToNS(cgPoint)

        let rect = NSRect(
            x: nsPoint.x - windowSize / 2,
            y: nsPoint.y - windowSize / 2,
            width: windowSize,
            height: windowSize
        )

        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        let ringView = RingView(
            frame: NSRect(origin: .zero, size: CGSize(width: windowSize, height: windowSize)),
            ringDiameter: ringDiameter
        )
        panel.contentView = ringView

        panel.orderFrontRegardless()
        overlayWindow = panel

        animate(panel: panel, ringView: ringView)
    }

    // MARK: - Animation

    private func animate(panel: NSPanel, ringView: RingView) {
        guard let layer = ringView.layer else {
            dismissOverlay()
            return
        }

        // Initial state: scaled up, transparent
        layer.transform = CATransform3DMakeScale(1.35, 1.35, 1.0)

        // Scale down to 1.0
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.35
        scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.22
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false
        layer.add(scaleAnim, forKey: "scale")
        layer.transform = CATransform3DIdentity

        // Fade in the panel
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        // Fade out after a brief hold
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.47
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                self?.dismissOverlay()
            })
        }
    }

    private func dismissOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    private func cgToNS(_ cgPoint: CGPoint) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)
    }
}

// MARK: - Ring View

private class RingView: NSView {

    private let ringDiameter: CGFloat

    init(frame: NSRect, ringDiameter: CGFloat) {
        self.ringDiameter = ringDiameter
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = ringDiameter / 2

        // Soft outer glow — provides contrast on dark backgrounds
        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.2))
        ctx.setLineWidth(5.0)
        ctx.addArc(center: center, radius: radius + 1, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        // Main ring — accent color for a native feel
        let accent = NSColor.controlAccentColor.withAlphaComponent(0.65)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(2.0)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        // Inner subtle shadow — provides contrast on light backgrounds
        ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 0.1))
        ctx.setLineWidth(3.0)
        ctx.addArc(center: center, radius: radius - 2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
    }
}
