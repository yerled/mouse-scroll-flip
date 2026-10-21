import Foundation

/// One axis of a scroll wheel event, in every representation consumers read.
///
/// - `line` is `kCGScrollWheelEventDeltaAxis*` (notches, acceleration not included).
/// - `point` is `kCGScrollWheelEventPointDeltaAxis*` (pixel delta, accelerated).
/// - `fixedPoint` is `kCGScrollWheelEventFixedPtDeltaAxis*` (what `NSEvent.scrollingDelta*` uses).
/// - `hid` is the embedded IOHID scroll value WebKit/Safari read (`kIOHIDEventFieldScrollY/X`).
public struct ScrollAxisDeltas: Equatable, Sendable {
    public var line: Int64
    public var point: Int64
    public var fixedPoint: Double
    public var hid: Double

    public init(line: Int64, point: Int64, fixedPoint: Double, hid: Double) {
        self.line = line
        self.point = point
        self.fixedPoint = fixedPoint
        self.hid = hid
    }
}

/// Vertical is CGEvent axis 1. Horizontal is CGEvent axis 2.
public struct ScrollSample: Equatable, Sendable {
    public var vertical: ScrollAxisDeltas
    public var horizontal: ScrollAxisDeltas

    public init(vertical: ScrollAxisDeltas, horizontal: ScrollAxisDeltas) {
        self.vertical = vertical
        self.horizontal = horizontal
    }
}

public enum ScrollInverter {
    /// Order callers must use when writing an axis back onto a `CGEvent`.
    ///
    /// Assigning the line delta makes the window server recompute the point
    /// delta (historically an 8× scale) and the fixed-point delta. Writing
    /// line first, then fixed-point, then point, then the IOHID value, is
    /// what keeps AppKit, Chromium, and WebKit on the same direction.
    public static let fieldWriteOrder = ["line", "fixedPoint", "point", "hid"]

    /// Returns a copy with the requested axes negated.
    ///
    /// Vertical is always flipped for a discrete wheel. Horizontal is flipped
    /// only when the menu option is on. Axes that are not selected are
    /// returned unchanged so the caller can avoid writing them (writing a
    /// line delta, even with the same number, retriggers the point-delta rewrite).
    public static func invert(_ sample: ScrollSample, horizontal: Bool) -> ScrollSample {
        ScrollSample(
            vertical: negate(sample.vertical),
            horizontal: horizontal ? negate(sample.horizontal) : sample.horizontal
        )
    }

    public static func negate(_ axis: ScrollAxisDeltas) -> ScrollAxisDeltas {
        ScrollAxisDeltas(
            line: negate(axis.line),
            point: negate(axis.point),
            fixedPoint: -axis.fixedPoint,
            hid: -axis.hid
        )
    }

    /// `Int64.min` cannot be negated in two's complement. Scroll deltas never
    /// reach it; the clamp keeps a hostile or synthetic event from trapping.
    public static func negate(_ value: Int64) -> Int64 {
        value == Int64.min ? Int64.max : -value
    }
}
