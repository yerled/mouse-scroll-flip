import CoreFoundation
import CoreGraphics
import Darwin
import os

/// Negates the IOHID scroll fields embedded in a `CGEvent`.
///
/// WebKit (Safari) reads `kIOHIDEventFieldScrollY/X` from that embedded
/// event instead of the Quartz deltas. The symbols are private SPI, loaded
/// with `dlsym` so a missing symbol skips this path instead of failing to
/// launch. The public Quartz deltas are still inverted either way.
enum HIDScroll {
    private static let log = Logger(subsystem: "com.yerled.mousescrollflip", category: "hid")

    /// `kIOHIDEventTypeScroll` is 6. X is field 0, Y is field 1.
    private static let scrollX: UInt32 = (6 << 16) | 0
    private static let scrollY: UInt32 = (6 << 16) | 1

    private typealias CopyFunction = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias GetFunction = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Double
    private typealias SetFunction = @convention(c) (UnsafeMutableRawPointer, UInt32, Double) -> Void

    private struct API {
        var copy: CopyFunction
        var get: GetFunction
        var set: SetFunction
    }

    private static let api: API? = load()

    /// Resolve symbols before the tap thread starts. `dlsym` is not something
    /// to do on the first scroll event.
    static func prepare() {
        if api == nil {
            log.error("IOHID scroll symbols are unavailable. Safari may not follow the flipped wheel.")
        }
    }

    static func negateEmbeddedScroll(in event: CGEvent, vertical: Bool, horizontal: Bool) {
        guard vertical || horizontal, let api else { return }
        let eventPointer = Unmanaged.passUnretained(event).toOpaque()
        guard let hid = api.copy(eventPointer) else { return }
        defer { Unmanaged<CFTypeRef>.fromOpaque(hid).release() }

        if vertical {
            api.set(hid, scrollY, -api.get(hid, scrollY))
        }
        if horizontal {
            api.set(hid, scrollX, -api.get(hid, scrollX))
        }
    }

    private static func load() -> API? {
        guard
            let coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
            let ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_NOW)
                ?? dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        else {
            return nil
        }

        guard
            let copyPointer = dlsym(coreGraphics, "CGEventCopyIOHIDEvent"),
            let getPointer = dlsym(ioKit, "IOHIDEventGetFloatValue"),
            let setPointer = dlsym(ioKit, "IOHIDEventSetFloatValue")
        else {
            return nil
        }

        return API(
            copy: unsafeBitCast(copyPointer, to: CopyFunction.self),
            get: unsafeBitCast(getPointer, to: GetFunction.self),
            set: unsafeBitCast(setPointer, to: SetFunction.self)
        )
    }
}
