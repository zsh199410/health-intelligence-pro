import XCTest
@testable import HealthCore

final class ExperimentalQRSDurationTests: XCTestCase {
    func testPolarityAndTimeOriginWithKnownTriangularComplex() throws {
        for sign in [-1.0, 1.0] {
            let points = (0..<500).map { i in
                ECGVoltagePoint(seconds: 10 + Double(i) / 500, millivolts: sign * max(0, 1 - Double(abs(i - 250)) / 20))
            }
            let trace = try ECGWaveform(samples: points, samplingFrequency: 500)
            let measured = try XCTUnwrap(ExperimentalQRSDuration.measure(in: trace, peakSeconds: points[250].seconds))
            XCTAssertEqual(measured.milliseconds, 80, accuracy: 14)
            XCTAssertNil(ExperimentalQRSDuration.measure(in: trace, peakSeconds: points[350].seconds))
            XCTAssertNil(ExperimentalQRSDuration.measure(in: trace, peakSeconds: points[0].seconds))
            let gap = try ECGWaveform(samples: points.filter { $0.seconds != points[245].seconds }, samplingFrequency: 500)
            XCTAssertNil(ExperimentalQRSDuration.measure(in: gap, peakSeconds: points[250].seconds))
        }
    }
}
