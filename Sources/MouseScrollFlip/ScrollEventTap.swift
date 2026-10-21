import AppKit
import CoreGraphics
import MouseScrollFlipCore
import os

/// Session-level scroll-wheel tap that negates discrete mouse-wheel events.
///
/// The callback runs on a dedicated thread. macOS delivers
/// `.tapDisabledByTimeout` and `.tapDisabledByUserInput` when it drops the
/// tap; those are re-enabled in place, and the tap is built again if the
/// port will not come back. `start` / `stop` / `revive` are main-thread only.
final class ScrollEventTap: @unchecked Sendable {
    static let shared = ScrollEventTap()

    private static let log = Logger(subsystem: "com.yerled.mousescrollflip", category: "event-tap")

    private struct Config {
        var inverting = false
        var reverseHorizontal = false
    }

    private struct Engine {
        var runLoop: CFRunLoop?
        var port: CFMachPort?
        var restartWhenExited = false
        var stopRequested = false
        var loggedCreateFailure = false
    }

    private let config = OSAllocatedUnfairLock(initialState: Config())
    private let engine = OSAllocatedUnfairLock(initialState: Engine())
    private let gate = ThreadGate()

    private init() {
        HIDScroll.prepare()
    }

    func setReverseHorizontal(_ enabled: Bool) {
        config.withLock { $0.reverseHorizontal = enabled }
    }

    var isTapEnabled: Bool {
        engine.withLock { engine in
            guard let port = engine.port else { return false }
            return CGEvent.tapIsEnabled(tap: port)
        }
    }

    /// Stop flipping events, then wait until the tap port is gone.
    func stop() {
        config.withLock { $0.inverting = false }
        // Fast path: the health timer calls stop while the feature is paused.
        if gate.isIdle {
            engine.withLock { $0.restartWhenExited = false }
            return
        }
        let loop = engine.withLock { engine -> CFRunLoop? in
            engine.stopRequested = true
            engine.restartWhenExited = false
            return engine.runLoop
        }
        if let loop {
            CFRunLoopStop(loop)
        }
        gate.waitUntilIdle()
        engine.withLock { $0.stopRequested = false }
    }

    private var wantsInversion: Bool {
        config.withLock { $0.inverting }
    }

    /// Create the tap if one is not already alive.
    func start() {
        guard gate.tryEnter() else { return }
        config.withLock { $0.inverting = true }
        engine.withLock { $0.stopRequested = false }
        let thread = Thread { [self] in
            self.threadMain()
        }
        thread.name = "com.yerled.mousescrollflip.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Re-enable a tap macOS disabled, or start one if it is missing.
    /// Called on a one-second timer so granting Accessibility permission
    /// takes effect without relaunching the app.
    func revive() {
        config.withLock { $0.inverting = true }
        let snapshot = engine.withLock { engine in
            (port: engine.port, loop: engine.runLoop, stopRequested: engine.stopRequested)
        }
        if snapshot.stopRequested {
            return
        }
        if let port = snapshot.port {
            if CGEvent.tapIsEnabled(tap: port) {
                return
            }
            CGEvent.tapEnable(tap: port, enable: true)
            if CGEvent.tapIsEnabled(tap: port) {
                return
            }
            engine.withLock { $0.restartWhenExited = true }
            if let loop = snapshot.loop {
                CFRunLoopStop(loop)
            }
            return
        }
        start()
    }

    // MARK: - Tap thread

    private func threadMain() {
        var restart = false
        defer {
            // Leave the gate before asking main to start a replacement.
            // A queued start that arrives after the user paused sees
            // `wantsInversion == false` and does nothing, so two taps
            // cannot invert twice and cancel out.
            gate.leave()
            if restart {
                DispatchQueue.main.async { [self] in
                    guard self.wantsInversion else { return }
                    self.start()
                }
            }
        }

        if isStopRequested {
            return
        }

        guard let installed = installTap() else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .scrollTapUnavailable, object: nil)
            }
            return
        }

        if isStopRequested {
            discard(installed)
            return
        }

        CFRunLoopAddSource(installed.loop, installed.source, .commonModes)
        CGEvent.tapEnable(tap: installed.port, enable: true)
        CFRunLoopRun()

        CFRunLoopRemoveSource(installed.loop, installed.source, .commonModes)
        CGEvent.tapEnable(tap: installed.port, enable: false)
        CFMachPortInvalidate(installed.port)
        restart = engine.withLock { engine -> Bool in
            let shouldRestart = engine.restartWhenExited && !engine.stopRequested
            engine.restartWhenExited = false
            if engine.port == installed.port {
                engine.port = nil
                engine.runLoop = nil
            }
            return shouldRestart
        }
    }

    private var isStopRequested: Bool {
        engine.withLock { $0.stopRequested }
    }

    private func installTap() -> InstalledTap? {
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let port = makeTap(events: mask) else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return nil
        }
        let loop = CFRunLoopGetCurrent()
        engine.withLock { engine in
            engine.port = port
            engine.runLoop = loop
            engine.loggedCreateFailure = false
        }
        return InstalledTap(port: port, source: source, loop: loop)
    }

    private func discard(_ installed: InstalledTap) {
        CFMachPortInvalidate(installed.port)
        engine.withLock { engine in
            engine.restartWhenExited = false
            if engine.port == installed.port {
                engine.port = nil
                engine.runLoop = nil
            }
        }
    }

    /// Session tap first, so Shift-scroll has already been turned into a
    /// horizontal wheel event and "reverse horizontal" matches what apps see.
    /// HID tap is the fallback when the session tap is refused.
    private func makeTap(events: CGEventMask) -> CFMachPort? {
        let locations: [CGEventTapLocation] = [.cgSessionEventTap, .cghidEventTap]
        for location in locations {
            if let port = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: events,
                callback: scrollEventCallback,
                userInfo: nil
            ) {
                return port
            }
        }
        let shouldLog = engine.withLock { engine -> Bool in
            if engine.loggedCreateFailure { return false }
            engine.loggedCreateFailure = true
            return true
        }
        if shouldLog {
            Self.log.error("CGEvent.tapCreate failed. Accessibility permission is required.")
        }
        return nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleDisabled(type)
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        let cfg = config.withLock { $0 }
        guard cfg.inverting else {
            return Unmanaged.passUnretained(event)
        }

        let traits = ScrollEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        )
        guard ScrollClassifier.source(of: traits) == .discreteMouseWheel else {
            return Unmanaged.passUnretained(event)
        }

        invert(event, horizontal: cfg.reverseHorizontal)
        return Unmanaged.passUnretained(event)
    }

    /// Runs on the tap thread. Re-enable outside the lock: `tapEnable` is the
    /// documented way to recover, and the lock is not recursive.
    private func handleDisabled(_ type: CGEventType) {
        let inverting = config.withLock { $0.inverting }
        let port = engine.withLock { $0.port }
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            if CGEvent.tapIsEnabled(tap: port) {
                return
            }
        }
        let loop = engine.withLock { engine -> CFRunLoop? in
            if inverting && !engine.stopRequested {
                engine.restartWhenExited = true
            }
            return engine.runLoop
        }
        guard let loop else { return }
        Self.log.error("Scroll event tap disabled (\(type.rawValue, privacy: .public)). Recreating it.")
        CFRunLoopStop(loop)
    }

    /// Read every delta first. Write line, then fixed-point, then point.
    /// Setting the line delta makes the window server rewrite the other two,
    /// so they have to be stored again afterwards. WebKit also reads the
    /// embedded IOHID scroll fields, which are negated separately.
    private func invert(_ event: CGEvent, horizontal: Bool) {
        let vertical = ScrollAxisDeltas(
            line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            hid: 0
        )
        let horizontalDeltas = ScrollAxisDeltas(
            line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
            fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            hid: 0
        )
        let flipped = ScrollInverter.invert(
            ScrollSample(vertical: vertical, horizontal: horizontalDeltas),
            horizontal: horizontal
        )

        write(
            flipped.vertical,
            to: event,
            line: .scrollWheelEventDeltaAxis1,
            fixed: .scrollWheelEventFixedPtDeltaAxis1,
            point: .scrollWheelEventPointDeltaAxis1
        )
        if horizontal {
            write(
                flipped.horizontal,
                to: event,
                line: .scrollWheelEventDeltaAxis2,
                fixed: .scrollWheelEventFixedPtDeltaAxis2,
                point: .scrollWheelEventPointDeltaAxis2
            )
        }
        HIDScroll.negateEmbeddedScroll(in: event, vertical: true, horizontal: horizontal)
    }

    private func write(
        _ axis: ScrollAxisDeltas,
        to event: CGEvent,
        line: CGEventField,
        fixed: CGEventField,
        point: CGEventField
    ) {
        event.setIntegerValueField(line, value: axis.line)
        event.setDoubleValueField(fixed, value: axis.fixedPoint)
        event.setIntegerValueField(point, value: axis.point)
    }
}

private struct InstalledTap {
    let port: CFMachPort
    let source: CFRunLoopSource
    let loop: CFRunLoop
}

/// Counts tap threads so a new tap is not created until the previous port
/// has been invalidated. Two live taps invert twice and cancel each other.
private final class ThreadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let idle = DispatchSemaphore(value: 0)
    private var alive = 0

    var isIdle: Bool {
        lock.lock()
        defer { lock.unlock() }
        return alive == 0
    }

    func tryEnter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if alive > 0 { return false }
        alive = 1
        return true
    }

    func leave() {
        lock.lock()
        alive -= 1
        let nowIdle = alive == 0
        lock.unlock()
        if nowIdle {
            idle.signal()
        }
    }

    func waitUntilIdle() {
        while true {
            lock.lock()
            let busy = alive > 0
            lock.unlock()
            if !busy { return }
            idle.wait()
        }
    }
}

private let scrollEventCallback: CGEventTapCallBack = { _, type, event, _ in
    ScrollEventTap.shared.handle(type: type, event: event)
}

extension Notification.Name {
    static let scrollTapUnavailable = Notification.Name("com.yerled.mousescrollflip.tapUnavailable")
}
