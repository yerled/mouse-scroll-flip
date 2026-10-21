import XCTest
@testable import MouseScrollFlipCore

final class ScrollInverterTests: XCTestCase {
    private func sample() -> ScrollSample {
        ScrollSample(
            vertical: ScrollAxisDeltas(line: 3, point: 24, fixedPoint: 0.3, hid: 2.5),
            horizontal: ScrollAxisDeltas(line: -1, point: -8, fixedPoint: -0.1, hid: -1.25)
        )
    }

    func testVerticalAxisIsNegatedAndHorizontalIsPreservedByDefault() {
        let flipped = ScrollInverter.invert(sample(), horizontal: false)
        XCTAssertEqual(flipped.vertical, ScrollAxisDeltas(line: -3, point: -24, fixedPoint: -0.3, hid: -2.5))
        XCTAssertEqual(flipped.horizontal, sample().horizontal)
    }

    func testHorizontalOptionNegatesBothAxes() {
        let flipped = ScrollInverter.invert(sample(), horizontal: true)
        XCTAssertEqual(flipped.vertical.line, -3)
        XCTAssertEqual(flipped.horizontal, ScrollAxisDeltas(line: 1, point: 8, fixedPoint: 0.1, hid: 1.25))
    }

    func testNegatingTwiceRestoresTheOriginalSample() {
        let original = sample()
        let twice = ScrollInverter.invert(ScrollInverter.invert(original, horizontal: true), horizontal: true)
        XCTAssertEqual(twice, original)
    }

    func testIntegerMinDoesNotTrap() {
        XCTAssertEqual(ScrollInverter.negate(Int64.min), Int64.max)
        XCTAssertEqual(ScrollInverter.negate(Int64(0)), 0)
        XCTAssertEqual(ScrollInverter.negate(Int64(-4)), 4)
    }

    func testFieldWriteOrderKeepsPointDeltaAfterLineDelta() {
        // Lock the contract the event tap relies on. See ScrollInverter.fieldWriteOrder.
        XCTAssertEqual(ScrollInverter.fieldWriteOrder, ["line", "fixedPoint", "point", "hid"])
    }
}
