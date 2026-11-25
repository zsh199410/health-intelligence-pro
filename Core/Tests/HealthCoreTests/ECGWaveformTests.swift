import XCTest
@testable import HealthCore

final class ECGWaveformTests: XCTestCase {
    func testOverviewKeepsNarrowPeaksInOrderAndOriginalSamples() throws {
        let raw = (0..<6400).map { i in
            ECGVoltagePoint(seconds: Double(i) / 512, millivolts: i == 101 ? 2 : (i == 102 ? -1 : 0))
        }
        let trace = try ECGWaveform(samples: raw, samplingFrequency: 512)
        let points = try XCTUnwrap(trace.segments.first?.points)
        XCTAssertEqual(trace.samples, raw)
        XCTAssertEqual(points.first, raw.first)
        XCTAssertEqual(points.last, raw.last)
        XCTAssertEqual(points.filter { $0.millivolts != 0 }, Array(raw[101...102]))
        XCTAssertLessThanOrEqual(points.count, 1600)
        XCTAssertEqual(points.map(\.seconds), points.map(\.seconds).sorted())
    }

    func testAcquisitionGapIsNeverConnected() throws {
        let raw = [0, 0.01, 0.02, 0.5, 0.51].map { ECGVoltagePoint(seconds: $0, millivolts: 0) }
        for rate: Double? in [100, nil] {
            let trace = try ECGWaveform(samples: raw, samplingFrequency: rate)
            XCTAssertEqual(trace.segments.map { $0.points.count }, [3, 2])
            XCTAssertEqual(trace.gapCount, 1)
        }
        let small = try ECGWaveform(samples: raw, samplingFrequency: 100, displayBudget: 2)
        XCTAssertEqual(small.samples, raw)
        XCTAssertTrue(small.segments.isEmpty)
    }

    func testRejectsInvalidTimesOrVoltages() {
        for (t, v) in [(0.0, 0.0), (-0.1, 0), (.nan, 0), (0.1, .infinity)] {
            let raw = [ECGVoltagePoint(seconds: 0, millivolts: 0), ECGVoltagePoint(seconds: t, millivolts: v)]
            XCTAssertThrowsError(try ECGWaveform(samples: raw, samplingFrequency: 128))
        }
    }
}
