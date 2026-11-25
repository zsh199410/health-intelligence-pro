import XCTest
@testable import HealthCore

final class PPGCaptureQualityTests: XCTestCase {
    private func frames(count: Int = 271, fps: Double = 30, clipped: Double = 0) -> [PPGCameraFrame] {
        (0..<count).map { index in
            let t = Double(index) / fps
            return PPGCameraFrame(timestamp: t, redLevel: 0.7 + 0.02 * sin(2 * .pi * t),
                                  clippedFraction: clipped)
        }
    }

    func testSyntheticWindowReachesWaveformAnalysis() {
        XCTAssertEqual(PPGCaptureQuality.assess(frames()), .readyForAnalysis)
    }

    func testRejectsAbsentOrShortWindow() {
        XCTAssertEqual(PPGCaptureQuality.assess([]), .insufficientDuration)
        XCTAssertEqual(PPGCaptureQuality.assess(frames(count: 200)), .insufficientDuration)
    }

    func testRejectsDuplicateTimeAndSamplingGaps() {
        var capture = frames()
        capture.insert(capture[0], at: 1)
        XCTAssertEqual(PPGCaptureQuality.assess(capture), .irregularTiming)
        capture = frames()
        capture.removeSubrange(30..<40)
        XCTAssertEqual(PPGCaptureQuality.assess(capture), .irregularTiming)
        XCTAssertEqual(PPGCaptureQuality.assess(frames(count: 100, fps: 10)), .irregularTiming)
    }

    func testRejectsClippedAndFlatWindows() {
        XCTAssertEqual(PPGCaptureQuality.assess(frames(clipped: 0.8)), .excessiveClipping)
        let flat = frames().map { PPGCameraFrame(timestamp: $0.timestamp, redLevel: 0.6, clippedFraction: 0) }
        XCTAssertEqual(PPGCaptureQuality.assess(flat), .flatSignal)
    }

    func testLocalDropoutCannotBeHiddenByHighMeanFrameRate() {
        // Three seconds sampled at 10 Hz in the middle of a 60 Hz recording.
        let input = frames(count: 720, fps: 60).enumerated().compactMap { index, frame in
            !(180..<360).contains(index) || index.isMultiple(of: 6) ? frame : nil
        }
        XCTAssertEqual(PPGCaptureQuality.assess(input), .irregularTiming)
        XCTAssertNil(PPGPulseEstimator.estimate(input))
    }

    func testPeriodicOneSidedContactChangeCanMimicPulseInTheScalarSignal() {
        let scalar = frames(count: 360)
        XCTAssertNotNil(PPGPulseEstimator.estimate(scalar))
        for axis in [SIMD2<Double>(1, 0), SIMD2<Double>(0, 1)] {
            let oneSided = scalar.map { frame in
                PPGCameraFrame(timestamp: frame.timestamp, redLevel: frame.redLevel,
                               clippedFraction: 0, spatialContrast: axis * (frame.redLevel - 0.7))
            }
            XCTAssertEqual(PPGCaptureQuality.assess(oneSided), .unstableContact)
            XCTAssertNil(PPGPulseEstimator.estimate(oneSided))
        }
    }

    func testUniformPulsationWithUnevenStaticIlluminationIsRetained() throws {
        let input = frames(count: 360).map { frame in
            PPGCameraFrame(timestamp: frame.timestamp, redLevel: frame.redLevel, clippedFraction: 0,
                           spatialContrast: SIMD2(0.1 + 0.2 * (frame.redLevel - 0.7), -0.05))
        }
        XCTAssertEqual(PPGCaptureQuality.assess(input), .readyForAnalysis)
        XCTAssertEqual(try XCTUnwrap(PPGPulseEstimator.estimate(input)).beatsPerMinute, 60, accuracy: 2)
    }

    func testRejectsInvalidFrameMetadata() {
        for invalid in [
            PPGCameraFrame(timestamp: .nan, redLevel: 0.5, clippedFraction: 0),
            PPGCameraFrame(timestamp: 10, redLevel: .nan, clippedFraction: 0),
            PPGCameraFrame(timestamp: 10, redLevel: 0.5, clippedFraction: 1.1)
        ] {
            XCTAssertEqual(PPGCaptureQuality.assess(frames() + [invalid]), .invalidFrame)
        }
    }
}
