import Foundation

/// Fields copied off a `kCGEventScrollWheel` event.
///
/// Axis values are intentionally not part of classification. Direction is
/// decided only from the flags macOS uses to describe the physical device.
public struct ScrollEventTraits: Equatable, Sendable {
    /// `kCGScrollWheelEventIsContinuous` (CGEvent field 88).
    ///
    /// Documented since macOS 10.5. Discrete notched wheels report `0`.
    /// Trackpads and the Magic Mouse report `1` because their scroll
    /// surface is continuous.
    public var isContinuous: Bool

    /// `kCGScrollWheelEventScrollPhase` (CGEvent field 99).
    ///
    /// `0` when the event is not part of a gesture. Trackpads and the
    /// Magic Mouse use the began / changed / ended / cancelled phases
    /// (`1`, `2`, `4`, `8`) and mayBegin (`128`).
    public var scrollPhase: Int64

    /// `kCGScrollWheelEventMomentumPhase` (CGEvent field 123).
    ///
    /// `0` for a notched wheel. Non-zero while a touch device is coasting
    /// after the fingers lift.
    public var momentumPhase: Int64

    public init(isContinuous: Bool, scrollPhase: Int64, momentumPhase: Int64) {
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
    }
}

public enum ScrollSource: Equatable, Sendable {
    /// A notched mouse wheel. These are the only events the app inverts.
    case discreteMouseWheel
    /// Trackpad, Magic Mouse, or any other continuous / gesture scroll.
    case continuousDevice
}

public enum ScrollClassifier {
    /// Decide whether a scroll event came from a discrete mouse wheel.
    ///
    /// A wheel notch is continuous=`false` and carries neither a gesture
    /// phase nor a momentum phase. Requiring all three keeps a trackpad
    /// or Magic Mouse event untouched even if a driver clears the
    /// continuous bit on a single event in the gesture.
    ///
    /// Mice that advertise a high-resolution *continuous* wheel (some
    /// Logitech Options / Logi Options+ "smooth scrolling" modes) look
    /// like a trackpad to macOS. Those events are left alone on purpose:
    /// flipping every continuous event would also flip the Magic Mouse
    /// and the trackpad. Turn the vendor smooth-scroll mode off to get
    /// discrete notches.
    public static func source(of traits: ScrollEventTraits) -> ScrollSource {
        if traits.isContinuous || traits.scrollPhase != 0 || traits.momentumPhase != 0 {
            return .continuousDevice
        }
        return .discreteMouseWheel
    }
}
