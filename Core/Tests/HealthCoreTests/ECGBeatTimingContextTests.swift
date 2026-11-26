import XCTest
@testable import HealthCore

final class ECGBeatTimingContextTests: XCTestCase {
    func testEarlyIntervalExcludedFromReferenceAndFollowingBeatRequired() throws {
        let peaks: [Double] = (0...8).map(Double.init) + [8.6, 10, 11]
        let beats = ECGBeatDetector.Beats(peakTimes: peaks)
        let context = try XCTUnwrap(ECGBeatTimingContext.measure(beats: beats, at: 9))
        XCTAssertEqual(context.baselineRRSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(context.couplingRatio, 0.6, accuracy: 1e-9)
        XCTAssertEqual(context.followingRatio, 1.4, accuracy: 1e-9)
        XCTAssertNil(ECGBeatTimingContext.measure(beats: beats, at: 8))
        XCTAssertNil(ECGBeatTimingContext.measure(beats: beats, at: 11))
    }
    func testIrregularReferenceSuppressesRatios() {
        let peaks: [Double] = [0, 0.5, 2, 2.5, 4, 4.5, 6, 6.5, 8, 9, 10]
        let beats = ECGBeatDetector.Beats(peakTimes: peaks)
        XCTAssertNil(ECGBeatTimingContext.measure(beats: beats, at: 9))
    }
}
