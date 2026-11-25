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
