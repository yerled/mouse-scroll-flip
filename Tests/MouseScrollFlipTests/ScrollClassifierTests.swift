import XCTest
@testable import MouseScrollFlipCore

final class ScrollClassifierTests: XCTestCase {
    func testDiscreteWheelIsNotchedAndPhaseless() {
        let traits = ScrollEventTraits(isContinuous: false, scrollPhase: 0, momentumPhase: 0)
        XCTAssertEqual(ScrollClassifier.source(of: traits), .discreteMouseWheel)
    }

    func testTrackpadContinuousIsLeftAlone() {
        let traits = ScrollEventTraits(isContinuous: true, scrollPhase: 0, momentumPhase: 0)
        XCTAssertEqual(ScrollClassifier.source(of: traits), .continuousDevice)
    }

    func testMagicMouseGesturePhasesAreLeftAlone() {
        let began = ScrollEventTraits(isContinuous: true, scrollPhase: 1, momentumPhase: 0)
        let changed = ScrollEventTraits(isContinuous: true, scrollPhase: 2, momentumPhase: 0)
        let ended = ScrollEventTraits(isContinuous: true, scrollPhase: 4, momentumPhase: 0)
        let momentum = ScrollEventTraits(isContinuous: true, scrollPhase: 0, momentumPhase: 2)
        XCTAssertEqual(ScrollClassifier.source(of: began), .continuousDevice)
        XCTAssertEqual(ScrollClassifier.source(of: changed), .continuousDevice)
        XCTAssertEqual(ScrollClassifier.source(of: ended), .continuousDevice)
        XCTAssertEqual(ScrollClassifier.source(of: momentum), .continuousDevice)
    }

    func testPhaseOrMomentumVetoesAMislabelledDiscreteEvent() {
        // A touch device must not be flipped if a driver clears the
        // continuous bit on one event of the gesture.
        let phased = ScrollEventTraits(isContinuous: false, scrollPhase: 2, momentumPhase: 0)
        let coasting = ScrollEventTraits(isContinuous: false, scrollPhase: 0, momentumPhase: 1)
        let mayBegin = ScrollEventTraits(isContinuous: false, scrollPhase: 128, momentumPhase: 0)
        XCTAssertEqual(ScrollClassifier.source(of: phased), .continuousDevice)
        XCTAssertEqual(ScrollClassifier.source(of: coasting), .continuousDevice)
        XCTAssertEqual(ScrollClassifier.source(of: mayBegin), .continuousDevice)
    }

    func testAcceleratedNotchIsStillAWheel() {
        // Acceleration changes the delta, not the continuous/phase flags.
        // The classifier ignores magnitudes, so a fast flick stays a wheel.
        let traits = ScrollEventTraits(isContinuous: false, scrollPhase: 0, momentumPhase: 0)
        XCTAssertEqual(ScrollClassifier.source(of: traits), .discreteMouseWheel)
    }
}
