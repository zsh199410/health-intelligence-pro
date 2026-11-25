import XCTest
@testable import HealthCore

final class PPGPulseEstimatorTests: XCTestCase {
    private func frames(fps: Int = 30, signal: (Double) -> Double) -> [PPGCameraFrame] {
        (0..<(fps * 12)).map { i in
            let t = Double(i) / Double(fps) + 0.002 * sin(Double(i))
            return PPGCameraFrame(timestamp: t + 800, redLevel: signal(t), clippedFraction: 0)
        }
    }

    func testKnownPeriodWithBrightnessDriftAndUnevenTiming() throws {
        for fps in [24, 30, 60] {
            let input = frames(fps: fps) { 0.7 + 0.002 * $0 + 0.015 * cos(2 * .pi * $0 / 0.8) }
            let estimate = try XCTUnwrap(PPGPulseEstimator.estimate(input))
            XCTAssertEqual(estimate.beatsPerMinute, 75, accuracy: 2)
            XCTAssertTrue(estimate.intervals.allSatisfy { abs($0 - 0.8) < 0.05 })
        }
    }

    func testGradualContactChangeAndSingleImpulseAreRejected() {
        XCTAssertNil(PPGPulseEstimator.estimate(frames { 0.5 + $0 * 0.005 }))
        XCTAssertNil(PPGPulseEstimator.estimate(frames { (5...5.2).contains($0) ? 0.8 : 0.7 }))
    }

    func testMissingBeatAndLargeFrameGapRejectEntireEstimate() {
        let input = frames { t in
            0.7 + ((5.0...5.8).contains(t) ? 0 : 0.02 * cos(2 * .pi * t / 0.8))
        }
        XCTAssertNil(PPGPulseEstimator.estimate(input))
        let gapped = frames { 0.7 + 0.02 * cos(2 * .pi * $0 / 0.8) }.filter { !(805...806).contains($0.timestamp) }
        XCTAssertNil(PPGPulseEstimator.estimate(gapped))
    }
}
