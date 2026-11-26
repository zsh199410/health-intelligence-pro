import Foundation

struct Fixture: Decodable {
    let record: String
    let samples: [Double]
    let onset, peak, offset: Double
}

struct Counts {
    var labels = 0, matched = 0
    var onsetErrors: [Double] = [], offsetErrors: [Double] = [], widthErrors: [Double] = []
}

let cases = try JSONDecoder().decode([Fixture].self, from: FileHandle.standardInput.readDataToEndOfFile())
var results = [String: Counts]()
for item in cases {
    var row = results[item.record, default: Counts()]
    row.labels += 1
    let samples = item.samples.enumerated().map { ECGVoltagePoint(seconds: Double($0.offset) / 250, millivolts: $0.element) }
    let trace = try ECGWaveform(samples: samples, samplingFrequency: 250)
    if case let .success(beats) = ECGBeatDetector.detect(in: trace),
       let nearest = beats.peakTimes.min(by: { abs($0 - item.peak) < abs($1 - item.peak) }),
       abs(nearest - item.peak) <= 0.1 {
        row.matched += 1
        if let width = ExperimentalQRSDuration.measure(in: trace, peakSeconds: nearest) {
            row.onsetErrors.append(abs(width.onset.seconds - item.onset) * 1000)
            row.offsetErrors.append(abs(width.offset.seconds - item.offset) * 1000)
            row.widthErrors.append(abs(width.milliseconds - (item.offset - item.onset) * 1000))
        }
    }
    results[item.record] = row
}
func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
for name in results.keys.sorted() {
    let row = results[name]!
    print("\(name) labels=\(row.labels) matched=\(row.matched) widths=\(row.widthErrors.count)",
          String(format: "MAE_ms(onset,offset,width)=%.2f,%.2f,%.2f", mean(row.onsetErrors), mean(row.offsetErrors), mean(row.widthErrors)))
}
precondition(results.count == 4)
// Pinned engineering regression on this conversion. Preserve the observed failures
// as well as coverage; these bounds do not qualify the algorithm for patient use.
let minimumWidths = ["sel100": 28, "sel102": 42, "sel103": 28, "sel104": 27]
let maximumWidthMAE = ["sel100": 25.0, "sel102": 180, "sel103": 22, "sel104": 55]
for (record, minimum) in minimumWidths {
    guard let row = results[record] else { fatalError("Missing record " + record) }
    precondition(row.widthErrors.count >= minimum && mean(row.widthErrors) <= maximumWidthMAE[record]!)
}
