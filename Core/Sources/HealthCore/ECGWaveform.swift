import Foundation

/// Original single-lead samples and a bounded envelope for display. Analysis
/// must use samples; intervals and amplitudes in the envelope are not resampled.
public struct ECGWaveform: Sendable {
    public struct Segment: Identifiable, Sendable {
        public let id: Int
        public let points: [ECGVoltagePoint]
    }

    public enum InputError: Error { case invalidSample }
    public let samples: [ECGVoltagePoint]
    public let samplingFrequency: Double?
    public let segments: [Segment]
    private let runs: [Range<Int>]
    public let gapCount: Int

    public init(samples: [ECGVoltagePoint], samplingFrequency: Double?, displayBudget: Int = 1600) throws {
        var intervals: [Double] = []
        for (index, sample) in samples.enumerated() {
            guard sample.seconds.isFinite, sample.seconds >= 0, sample.millivolts.isFinite else {
                throw InputError.invalidSample
            }
            if index > 0 {
                let delta = sample.seconds - samples[index - 1].seconds
                guard delta > 0 else { throw InputError.invalidSample }
                intervals.append(delta)
            }
        }
        self.samples = samples
        self.samplingFrequency = samplingFrequency.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        // Use the reported sampling clock when available. With at least three
        // observed spacings the median provides a fallback for plotting only.
        let period = self.samplingFrequency.map { 1 / $0 } ??
            (intervals.count >= 3 ? intervals.sorted()[(intervals.count - 1) / 2] : nil)
        var starts: [Int] = samples.isEmpty ? [] : [0]
        if let period {
            for (index, delta) in intervals.enumerated() where delta > 1.5 * period {
                starts.append(index + 1)
            }
        }
        gapCount = max(0, starts.count - 1)
        let ranges = zip(starts, starts.dropFirst() + [samples.count]).map { $0..<$1 }
        runs = ranges
        segments = Self.render(samples, ranges: ranges, displayBudget: displayBudget)
    }

    /// Render directly from original values within the selected time interval,
    /// retaining the gap boundaries established on the complete recording.
    public func segments(in window: ClosedRange<Double>, displayBudget: Int = 1600) -> [Segment] {
        func boundary(_ t: Double, inclusive: Bool) -> Int {
            var lo = 0
            var hi = samples.count
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                if samples[mid].seconds < t || (inclusive && samples[mid].seconds == t) { lo = mid + 1 }
                else { hi = mid }
            }
            return lo
        }
        let slice = boundary(window.lowerBound, inclusive: false)..<boundary(window.upperBound, inclusive: true)
        let visible = runs.compactMap { run -> Range<Int>? in
            let start = max(run.lowerBound, slice.lowerBound)
            let end = min(run.upperBound, slice.upperBound)
            return start < end ? start..<end : nil
        }
        return Self.render(samples, ranges: visible, displayBudget: displayBudget)
    }

    private static func render(_ samples: [ECGVoltagePoint], ranges: [Range<Int>], displayBudget: Int) -> [Segment] {
        let sampleCount = ranges.reduce(0) { $0 + $1.count }
        // Preserve both sides of each acquisition gap. When the display budget
        // cannot represent all runs, keep the raw trace and omit the overview.
        let mandatory = ranges.reduce(0) { $0 + min(2, $1.count) }
        let budget = max(0, min(sampleCount, displayBudget))
        guard mandatory <= budget else { return [] }
        let interior = sampleCount - mandatory
        return ranges.map { range in
            let extra = max(0, range.count - 2)
            let quota = interior == 0 ? 0 : Int(Double(budget - mandatory) * Double(extra) / Double(interior))
            let points = Self.envelope(samples[range], interiorBudget: quota)
            return Segment(id: range.lowerBound, points: points)
        }
    }

    private static func envelope(_ run: ArraySlice<ECGVoltagePoint>, interiorBudget: Int) -> [ECGVoltagePoint] {
        if run.count <= interiorBudget + 2 { return Array(run) }
        let bins = interiorBudget / 2
        let innerCount = run.count - 2
        var selected = [run[run.startIndex]]
        for i in 0..<bins {
            let start = run.startIndex + 1 + i * innerCount / bins
            let end = run.startIndex + 1 + (i + 1) * innerCount / bins
            var low = start
            var high = start
            for j in start..<end {
                if run[j].millivolts < run[low].millivolts { low = j }
                if run[j].millivolts > run[high].millivolts { high = j }
            }
            selected.append(run[min(low, high)])
            if low != high { selected.append(run[max(low, high)]) }
        }
        selected.append(run[run.endIndex - 1])
        return selected
    }
}
