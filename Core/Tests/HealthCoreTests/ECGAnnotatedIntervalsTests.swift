import XCTest
@testable import HealthCore

final class ECGAnnotatedIntervalsTests: XCTestCase {
    func testIntervalsUseSecondsAndPrecedingRRDespiteDifferentFollowingRR() throws {
        let beat = try ECGAnnotatedIntervals(within: 0...4, previousR: 0.2, pOnset: 0.8,
                                             qrsOnset: 0.96, rPeak: 1, qrsOffset: 1.06, tEnd: 1.36,
                                             nextR: 2.2, usePrecedingRRForCorrection: true)
        XCTAssertEqual(try XCTUnwrap(beat.prSeconds), 0.16, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(beat.qrsSeconds), 0.10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(beat.qtSeconds), 0.40, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(beat.precedingRRSeconds), 0.80, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(beat.qtcFridericiaSeconds), 0.430887, accuracy: 1e-6)
    }

    func testAmbiguousTEndSuppressesQTButPreservesQRS() throws {
        let beat = try ECGAnnotatedIntervals(within: 0...2, previousR: 0, qrsOnset: 0.96,
                                             rPeak: 1, qrsOffset: 1.06, tEnd: nil,
                                             usePrecedingRRForCorrection: true)
        XCTAssertNil(beat.prSeconds)
        XCTAssertNil(beat.qtSeconds)
        XCTAssertNil(beat.qtcFridericiaSeconds)
        XCTAssertEqual(try XCTUnwrap(beat.qrsSeconds), 0.1, accuracy: 1e-9)
    }

    func testCorrectionRequiresBothPrecedingRRAndExplicitSuitability() throws {
        let unreviewed = try ECGAnnotatedIntervals(within: 0...2, previousR: 0, qrsOnset: 0.96, rPeak: 1, tEnd: 1.36)
        let insufficient = try ECGAnnotatedIntervals(within: 0...2, qrsOnset: 0.96, rPeak: 1, tEnd: 1.36,
                                                     nextR: 1.9, usePrecedingRRForCorrection: true)
        XCTAssertNotNil(unreviewed.qtSeconds)
        XCTAssertNil(unreviewed.qtcFridericiaSeconds)
        XCTAssertNil(insufficient.qtcFridericiaSeconds)
    }

    func testRejectsCrossSegmentNonfiniteAndOutOfOrderLandmarks() {
        for qrs in [-1.0, .nan, .infinity, 3] {
            XCTAssertThrowsError(try ECGAnnotatedIntervals(within: 0...2, qrsOnset: qrs))
        }
        XCTAssertThrowsError(try ECGAnnotatedIntervals(within: 1...1, qrsOnset: 1))
        XCTAssertThrowsError(try ECGAnnotatedIntervals(within: 0...2, qrsOnset: 1, qrsOffset: 1))
        XCTAssertThrowsError(try ECGAnnotatedIntervals(within: 0...2, qrsOnset: 1.1, tEnd: 1))
        XCTAssertThrowsError(try ECGAnnotatedIntervals(within: 0...2, qrsOnset: 0.8, tEnd: 1.5, nextR: 1.3))
    }
}
