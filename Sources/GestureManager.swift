import Cocoa

/// Detects four-finger taps on the trackpad using the private MultitouchSupport framework.
///
/// This is the standard approach used by macOS trackpad utilities (BetterTouchTool, Jitouch, etc.).
/// The framework ships with every macOS version but is not part of the public SDK, so the struct
/// layout is detected at runtime rather than hardcoded. If the framework is unavailable or the
/// layout changes in a future macOS release, gesture detection gracefully disables itself.
class GestureManager {

    // Static reference for the C callback (MultitouchSupport callbacks have no userData parameter)
    fileprivate static weak var shared: GestureManager?

    private var libHandle: UnsafeMutableRawPointer?
    private var devices: [OpaquePointer] = []
    private var stopDeviceFn: StopDeviceFn?
    fileprivate var onTap: (() -> Void)?

    // Runtime-detected stride of the MTTouch struct in bytes
    fileprivate var touchStride: Int = 0

    // Tap detection state (accessed only from the multitouch I/O thread)
    fileprivate var isTracking = false
    fileprivate var startTime: Double = 0
    fileprivate var peakCount: Int32 = 0
    fileprivate var startCentroid: (x: Float, y: Float) = (0, 0)
    fileprivate var lastCentroid: (x: Float, y: Float) = (0, 0)
    fileprivate var hasPositions = false
    fileprivate var lastTriggerTime: Double = 0

    // MARK: - Tuning

    /// Maximum duration (seconds) from first finger down to last finger up to count as a tap.
    fileprivate let maxTapDuration: Double = 0.28
    /// Maximum centroid movement in normalized trackpad coordinates (0–1) to count as a tap.
    fileprivate let maxMovement: Float = 0.035
    /// Minimum time (seconds) between consecutive triggers.
    fileprivate let cooldown: Double = 0.45
    /// Exact finger count required.
    fileprivate let requiredFingers: Int32 = 4

    // MARK: - Function types for dlsym

    private typealias CreateListFn   = @convention(c) () -> Unmanaged<CFArray>
    private typealias RegisterCBFn   = @convention(c) (
        OpaquePointer,
        @convention(c) (OpaquePointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Void
    ) -> Void
    private typealias StartDeviceFn  = @convention(c) (OpaquePointer, Int32) -> Void
    private typealias StopDeviceFn   = @convention(c) (OpaquePointer) -> Void

    // MARK: - Lifecycle

    func start(callback: @escaping () -> Void) {
        stop()
        self.onTap = callback
        GestureManager.shared = self

        guard let lib = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_LAZY
        ) else {
            NSLog("[D-Switch] Gesture: MultitouchSupport.framework not available — four-finger tap disabled")
            return
        }
        self.libHandle = lib

        guard let createListSym  = dlsym(lib, "MTDeviceCreateList"),
              let registerCBSym  = dlsym(lib, "MTRegisterContactFrameCallback"),
              let startDevSym    = dlsym(lib, "MTDeviceStart") else {
            NSLog("[D-Switch] Gesture: could not resolve MultitouchSupport symbols — four-finger tap disabled")
            dlclose(lib)
            self.libHandle = nil
            return
        }

        if let stopSym = dlsym(lib, "MTDeviceStop") {
            self.stopDeviceFn = unsafeBitCast(stopSym, to: StopDeviceFn.self)
        }

        let createList    = unsafeBitCast(createListSym, to: CreateListFn.self)
        let registerCB    = unsafeBitCast(registerCBSym, to: RegisterCBFn.self)
        let startDevice   = unsafeBitCast(startDevSym,   to: StartDeviceFn.self)

        let deviceArray = createList().takeRetainedValue() as CFArray
        let count = CFArrayGetCount(deviceArray)

        guard count > 0 else {
            NSLog("[D-Switch] Gesture: no multitouch devices found — four-finger tap disabled")
            return
        }

        for i in 0..<count {
            guard let rawPtr = CFArrayGetValueAtIndex(deviceArray, i) else { continue }
            let device = OpaquePointer(rawPtr)
            registerCB(device, gestureCallback)
            startDevice(device, 0)
            devices.append(device)
        }

        NSLog("[D-Switch] Gesture: monitoring \(devices.count) multitouch device(s) for four-finger tap")
    }

    func stop() {
        for device in devices {
            stopDeviceFn?(device)
        }
        devices.removeAll()

        if let lib = libHandle {
            dlclose(lib)
            libHandle = nil
        }

        onTap = nil
        if GestureManager.shared === self {
            GestureManager.shared = nil
        }
    }

    deinit { stop() }

    // MARK: - Touch Handling (called from multitouch I/O thread)

    fileprivate func handleTouches(_ touches: UnsafeRawPointer?, count: Int32, timestamp: Double) {
        if count > 0 && !isTracking {
            // Fingers just landed
            isTracking = true
            startTime = timestamp
            peakCount = count
            hasPositions = false
            if count >= requiredFingers {
                recordCentroid(touches: touches, count: count, isStart: true)
            }

        } else if isTracking && count > 0 {
            // Still touching
            if count > peakCount { peakCount = count }
            if count >= requiredFingers {
                if !hasPositions {
                    recordCentroid(touches: touches, count: count, isStart: true)
                }
                recordCentroid(touches: touches, count: count, isStart: false)
            }

        } else if isTracking && count == 0 {
            // All fingers lifted — evaluate
            evaluate(timestamp: timestamp)
            resetState()
        }
    }

    // MARK: - Position Reading

    /// Records the centroid of all touches. On first call for a gesture, saves as start centroid.
    private func recordCentroid(touches: UnsafeRawPointer?, count: Int32, isStart: Bool) {
        guard let touches = touches, count > 0 else { return }

        // Ensure we know the struct stride
        if touchStride == 0 {
            guard detectStride(touches: touches, count: count) else { return }
        }
        guard touchStride > 0 else { return }

        var sumX: Float = 0, sumY: Float = 0
        var valid = true
        for i in 0..<Int(count) {
            let base = i * touchStride
            let x = touches.load(fromByteOffset: base + 32, as: Float.self)
            let y = touches.load(fromByteOffset: base + 36, as: Float.self)
            // Sanity: normalized positions should be roughly in [0, 1]
            if x < -0.5 || x > 1.5 || y < -0.5 || y > 1.5 {
                valid = false
                break
            }
            sumX += x
            sumY += y
        }

        guard valid else { return }
        let n = Float(count)
        let centroid = (x: sumX / n, y: sumY / n)

        if isStart && !hasPositions {
            startCentroid = centroid
            hasPositions = true
        }
        lastCentroid = centroid
    }

    /// Tries common MTTouch struct sizes to find the correct stride.
    /// Validates by checking that the second touch's identifier looks reasonable.
    private func detectStride(touches: UnsafeRawPointer, count: Int32) -> Bool {
        guard count >= 2 else { return false }

        // identifier field is at byte offset 16 in all known layouts
        let id0 = touches.load(fromByteOffset: 16, as: Int32.self)

        for candidateStride in stride(from: 72, through: 200, by: 8) {
            let id1 = touches.load(fromByteOffset: candidateStride + 16, as: Int32.self)
            let x1  = touches.load(fromByteOffset: candidateStride + 32, as: Float.self)
            let y1  = touches.load(fromByteOffset: candidateStride + 36, as: Float.self)

            let idsValid = id0 >= 0 && id0 < 30 && id1 >= 0 && id1 < 30 && id0 != id1
            let posValid = x1 >= -0.5 && x1 <= 1.5 && y1 >= -0.5 && y1 <= 1.5

            if idsValid && posValid {
                touchStride = candidateStride
                NSLog("[D-Switch] Gesture: detected MTTouch stride = \(candidateStride) bytes")
                return true
            }
        }

        NSLog("[D-Switch] Gesture: could not detect MTTouch struct layout — position checking disabled, using timing only")
        // Set a sentinel so we don't retry detection every frame
        touchStride = -1
        return false
    }

    // MARK: - Tap Evaluation

    private func evaluate(timestamp: Double) {
        let duration = timestamp - startTime
        let cooldownOK = (timestamp - lastTriggerTime) > cooldown

        guard peakCount == requiredFingers else { return }
        guard duration > 0.04 && duration < maxTapDuration else { return }  // min 40ms to reject phantom touches
        guard cooldownOK else { return }

        // Movement check (skip if positions aren't available)
        if hasPositions {
            let dx = abs(lastCentroid.x - startCentroid.x)
            let dy = abs(lastCentroid.y - startCentroid.y)
            guard dx < maxMovement && dy < maxMovement else { return }
        }

        lastTriggerTime = timestamp
        DispatchQueue.main.async { [weak self] in
            self?.onTap?()
        }
    }

    private func resetState() {
        isTracking = false
        peakCount = 0
        hasPositions = false
    }
}

// MARK: - C Callback

/// Top-level C-compatible function. MultitouchSupport callbacks carry no user-data pointer,
/// so we route through the static `GestureManager.shared` reference.
private func gestureCallback(
    _: OpaquePointer?,
    touches: UnsafeRawPointer?,
    numTouches: Int32,
    timestamp: Double,
    _: Int32
) {
    GestureManager.shared?.handleTouches(touches, count: numTouches, timestamp: timestamp)
}
