import Foundation
import XCTest
@testable import HealthCore

final class ECGBeatDetectorTests: XCTestCase {
    private func signal(hz: Int, polarity: Double) -> [ECGVoltagePoint] {
        (0..<(hz * 10)).map { i in
            let t = Double(i) / Double(hz)
            let phase = t.truncatingRemainder(dividingBy: 1)
            let qrs = exp(-pow((phase - 0.5) / 0.014, 2))
            let tWave = 0.2 * exp(-pow((phase - 0.76) / 0.070, 2))
            return ECGVoltagePoint(seconds: t, millivolts: polarity * (qrs + tWave) + 0.1 * sin(t))
        }
    }

    func testPolarityCadenceAndDisplayDecimationDoNotChangeRawIntervals() throws {
        for hz in [128, 360, 512] {
            for polarity in [-1.0, 1.0] {
                let trace = try ECGWaveform(samples: signal(hz: hz, polarity: polarity), samplingFrequency: nil, displayBudget: 8)
                let beats = try ECGBeatDetector.detect(in: trace).get()
                XCTAssertEqual(beats.peakTimes.count, 10)
                for (i, time) in beats.peakTimes.enumerated() { XCTAssertEqual(time, Double(i) + 0.5, accuracy: 0.012) }
                for rr in beats.rrIntervals { XCTAssertEqual(rr, 1, accuracy: 0.012) }
            }
        }
    }

    func testRefusesMissingFramesAndFlatRecording() throws {
        var input = signal(hz: 250, polarity: 1)
        input.removeSubrange(400..<420)
        let gap = try ECGWaveform(samples: input, samplingFrequency: 250)
        XCTAssertThrowsError(try ECGBeatDetector.detect(in: gap).get()) { XCTAssertEqual($0 as? ECGBeatDetector.Rejection, .interruptedSampling) }
        let flat = try ECGWaveform(samples: signal(hz: 250, polarity: 1).map { ECGVoltagePoint(seconds: $0.seconds, millivolts: 0) }, samplingFrequency: 250)
        XCTAssertThrowsError(try ECGBeatDetector.detect(in: flat).get()) { XCTAssertEqual($0 as? ECGBeatDetector.Rejection, .weakOrNoisySignal) }
    }
}
