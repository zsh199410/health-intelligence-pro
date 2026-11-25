import Foundation

// Fixed public WFDB fixture 100: 360 Hz, packed format 212, MLII channel 0,
// baseline 1024, 200 ADC units/mV (100.hea). check.sh verifies blob identities.
let signal = [UInt8](try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let annotations = [UInt8](try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
precondition(signal.count == 650_000 * 3)
var reference = [Int]()
var cursor = 0
var position = 0
while cursor + 1 < annotations.count {
    let word = Int(annotations[cursor]) | Int(annotations[cursor + 1]) << 8
    cursor += 2
    if word == 0 { break }
    let kind = word >> 10, value = word & 1023
    switch kind {
    case 63: cursor += (value + 1) / 2 * 2 // padded AUX text
    case 61: break // SUB metadata
    case 1, 5, 8, 28:
        position += value
        if kind != 28 { reference.append(position) } // N, V, A beats; exclude rhythm marker
    default: fatalError("Unexpected annotation in pinned record")
    }
}
precondition(reference.count == 2273)
let rate = 360, window = 30 * rate
var predicted = [Int]()
var rejected = 0, windows = 0
var rrErrors = [Double]()
var timingErrors = [Double]()
var truePositive = 0
for start in stride(from: 0, to: signal.count / 3, by: window) {
    windows += 1
    let stop = min(start + window, signal.count / 3)
    let samples = (start..<stop).map { index -> ECGVoltagePoint in
        let offset = 3 * index
        let encoded = Int(signal[offset]) | (Int(signal[offset + 1]) & 15) << 8
        let adc = encoded >= 2048 ? encoded - 4096 : encoded
        return ECGVoltagePoint(seconds: Double(index) / Double(rate), millivolts: Double(adc - 1024) / 200)
    }
    let trace = try ECGWaveform(samples: samples, samplingFrequency: Double(rate))
    guard case let .success(beats) = ECGBeatDetector.detect(in: trace) else { rejected += 1; continue }
    let found = beats.peakTimes.map { Int(($0 * Double(rate)).rounded()) }
    predicted.append(contentsOf: found)
    let expected = reference.filter { $0 >= start && $0 < stop }
    var j = 0
    var previous: (predictionIndex: Int, labelIndex: Int)?
    for (i, sample) in found.enumerated() {
        // One-to-one matching, +/-100 ms. All reference beats, including
        // window boundaries and rejected windows, enter the sensitivity denominator.
        while j < expected.count && expected[j] < sample - 36 { j += 1 }
        guard j < expected.count, abs(sample - expected[j]) <= 36 else { continue }
        truePositive += 1
        timingErrors.append(Double(abs(sample - expected[j])) * 1000 / Double(rate))
        if let previous, previous.predictionIndex + 1 == i, previous.labelIndex + 1 == j {
            let error = (sample - found[i - 1]) - (expected[j] - expected[j - 1])
            rrErrors.append(Double(abs(error)) * 1000 / Double(rate))
        }
        previous = (i, j)
        j += 1
    }
}
func mean(_ values: [Double]) -> Double { values.isEmpty ? .nan : values.reduce(0, +) / Double(values.count) }
print("windows=\(windows) rejected=\(rejected) labels=\(reference.count) predictions=\(predicted.count)")
print("TP=\(truePositive) FP=\(predicted.count - truePositive) FN=\(reference.count - truePositive)")
print(String(format: "sensitivity=%.4f PPV=%.4f timing_MAE_ms=%.2f RR_pairs=%d RR_MAE_ms=%.2f",
             Double(truePositive) / Double(reference.count), Double(truePositive) / Double(predicted.count),
             mean(timingErrors), rrErrors.count, mean(rrErrors)))
// Engineering regression floor on this one record, not a clinical acceptance threshold.
precondition(truePositive >= 2150 && predicted.count - truePositive <= 100)
