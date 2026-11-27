import Foundation

/// Local timing descriptors for research on premature beats. Early timing and a
/// subsequent pause can occur with different rhythms, noise and missed detections.
/// The ratios neither distinguish atrial/ventricular origin nor establish sinus rhythm.
public struct ECGBeatTimingContext: Sendable {
    public let peakSeconds: Double
    public let baselineRRSeconds: Double
    public let baselineMADSeconds: Double
    /// Immediately preceding coupling interval divided by the earlier local median.
    public let couplingRatio: Double
    /// Immediately following interval divided by the same local median.
    public let followingRatio: Double

    public static func measure(beats: ECGBeatDetector.Beats, at index: Int) -> Self? {
        // Eight reference intervals end at the beat immediately *before* the coupling interval.
        let peaks = beats.peakTimes
        guard index >= 9, index < peaks.count - 1 else { return nil }
        let before = peaks[(index - 9)..<index]
        let previous = zip(before.dropFirst(), before).map(-).sorted()
        let median = previous[3] / 2 + previous[4] / 2
        let deviations = previous.map { abs($0 - median) }.sorted()
        let mad = deviations[3] / 2 + deviations[4] / 2
        // Conservative engineering gate for an appreciably irregular reference sequence.
        guard median > 0, mad <= 0.10 * median else { return nil }
        return Self(peakSeconds: peaks[index], baselineRRSeconds: median, baselineMADSeconds: mad,
                    couplingRatio: (peaks[index] - peaks[index - 1]) / median,
                    followingRatio: (peaks[index + 1] - peaks[index]) / median)
    }
}
