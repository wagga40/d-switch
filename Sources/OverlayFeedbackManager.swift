import Cocoa
import QuartzCore

enum RingPreset: String, CaseIterable {
    case subtle, standard, prominent

    static let `default`: RingPreset = .standard
    static let storageKey = "ringPreset"

    static func current() -> RingPreset {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let preset = RingPreset(rawValue: raw) {
            return preset
        }
        return .default
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }

    var displayName: String {
        switch self {
        case .subtle:    return "Subtle"
        case .standard:  return "Standard"
        case .prominent: return "Prominent"
        }
    }

    var ringDiameter: CGFloat {
        switch self {
        case .subtle:    return 60
        case .standard:  return 90
        case .prominent: return 120
        }
    }

    /// Big enough for the largest wave (2.0× ring diameter) plus stroke margin.
    var windowSize: CGFloat { ringDiameter * 2.6 }

    /// Duration of one pulse cycle (scale up and back to rest).
    var pulseDuration: CFTimeInterval {
        switch self {
        case .subtle:    return 0.45
        case .standard:  return 0.55
        case .prominent: return 0.70
        }
    }

    /// How many times the core ring pulses.
    var pulseCount: Int {
        switch self {
        case .subtle:    return 2
        case .standard:  return 3
        case .prominent: return 4
        }
    }

    /// Duration of a single sonar wave (expand + fade out).
    var waveDuration: CFTimeInterval {
        switch self {
        case .subtle:    return 0.85
        case .standard:  return 1.05
        case .prominent: return 1.30
        }
    }

    /// Number of staggered sonar waves.
    var waveCount: Int {
        switch self {
        case .subtle:    return 2
        case .standard:  return 2
        case .prominent: return 3
        }
    }

    var panelFadeIn: CFTimeInterval  { 0.10 }
    var panelFadeOut: CFTimeInterval { 0.30 }

    /// Total wall-clock duration the overlay should stay on screen.
    var totalDuration: CFTimeInterval {
        let pulseTotal = pulseDuration * Double(pulseCount)
        let waveStagger = waveDuration * 0.5
        let waveTotal = waveDuration + waveStagger * Double(max(0, waveCount - 1))
        return panelFadeIn + max(pulseTotal, waveTotal) + panelFadeOut
    }
}

class OverlayFeedbackManager {

    private var overlayWindow: NSPanel?

    func showHint(at cgPoint: CGPoint, on screen: NSScreen) {
        dismissOverlay()

        let preset = RingPreset.current()
        let nsPoint = cgToNS(cgPoint)
        let windowSize = preset.windowSize

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
            preset: preset
        )
        panel.contentView = ringView

        panel.orderFrontRegardless()
        overlayWindow = panel

        // Quick panel fade-in.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = preset.panelFadeIn
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        // Drive the layer animations.
        ringView.startAnimation()

        // Fade out + dismiss.
        let fadeOutAt = preset.totalDuration - preset.panelFadeOut
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutAt) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = preset.panelFadeOut
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

    private let preset: RingPreset
    private var coreLayers: [CAShapeLayer] = []
    private var waveLayers: [CAShapeLayer] = []

    init(frame: NSRect, preset: RingPreset) {
        self.preset = preset
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        buildLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildLayers() {
        guard let host = layer else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = preset.ringDiameter / 2
        // Stroke widths scale with diameter so the larger presets stay proportional.
        let scale = preset.ringDiameter / 48.0
        let glowWidth   = 5.0 * scale
        let mainWidth   = 2.0 * scale
        let shadowWidth = 3.0 * scale
        let waveWidth   = mainWidth * 1.6

        let mainPath = circlePath(center: center, radius: radius)
        let shadowPath = circlePath(center: center, radius: max(1, radius - 2))

        // Outer soft glow — readable on dark backgrounds.
        let glow = makeShape(path: mainPath, stroke: CGColor(gray: 1.0, alpha: 0.25), width: glowWidth)
        host.addSublayer(glow)
        coreLayers.append(glow)

        // Main accent ring.
        let core = makeShape(
            path: mainPath,
            stroke: NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor,
            width: mainWidth
        )
        host.addSublayer(core)
        coreLayers.append(core)

        // Inner shadow — readable on light backgrounds.
        let shadow = makeShape(path: shadowPath, stroke: CGColor(gray: 0.0, alpha: 0.12), width: shadowWidth)
        host.addSublayer(shadow)
        coreLayers.append(shadow)

        // Pre-build sonar wave layers; they animate from 0.8× to 2.0× scale.
        for _ in 0..<preset.waveCount {
            let wave = makeShape(
                path: mainPath,
                stroke: NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor,
                width: waveWidth
            )
            wave.opacity = 0
            host.addSublayer(wave)
            waveLayers.append(wave)
        }
    }

    func startAnimation() {
        animatePulse()
        for (i, wave) in waveLayers.enumerated() {
            let stagger = preset.waveDuration * 0.5 * Double(i)
            DispatchQueue.main.asyncAfter(deadline: .now() + stagger) { [weak self] in
                self?.animateWave(on: wave)
            }
        }
    }

    // MARK: animations

    private func animatePulse() {
        for layer in coreLayers {
            let anim = CAKeyframeAnimation(keyPath: "transform.scale")
            anim.values    = [1.0, 1.18, 1.0]
            anim.keyTimes  = [0.0, 0.5, 1.0]
            anim.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn)
            ]
            anim.duration    = preset.pulseDuration
            anim.repeatCount = Float(preset.pulseCount)
            layer.add(anim, forKey: "pulse")
        }
    }

    private func animateWave(on wave: CAShapeLayer) {
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.8
        scaleAnim.toValue   = 2.0
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.85
        opacityAnim.toValue   = 0.0
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let lineAnim = CABasicAnimation(keyPath: "lineWidth")
        lineAnim.fromValue = wave.lineWidth
        lineAnim.toValue   = wave.lineWidth * 0.4
        lineAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let group = CAAnimationGroup()
        group.animations = [scaleAnim, opacityAnim, lineAnim]
        group.duration   = preset.waveDuration
        group.fillMode   = .forwards
        group.isRemovedOnCompletion = false
        wave.add(group, forKey: "wave")
    }

    // MARK: helpers

    private func circlePath(center: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ),
            transform: nil
        )
    }

    private func makeShape(path: CGPath, stroke: CGColor, width: CGFloat) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.frame       = bounds
        shape.path        = path
        shape.fillColor   = NSColor.clear.cgColor
        shape.strokeColor = stroke
        shape.lineWidth   = width
        shape.lineCap     = .round
        // Default anchorPoint (0.5, 0.5) means transforms scale around the layer center,
        // which is also the path's center since we built it around bounds' midpoint.
        return shape
    }
}
