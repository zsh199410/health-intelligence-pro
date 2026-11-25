import Foundation

/// Experimental interval estimation from a brief, stationary fingertip recording.
/// Thresholds select analyzable recordings and require paired device validation.
public enum PPGPulseEstimator {
    public struct Estimate {
        public let beatsPerMinute: Double
        public let intervals: [TimeInterval]
    }

    /// Peaks are local maxima of inverted optical intensity after removing its
    /// slow baseline and smoothing camera noise. Filter coefficients use the
    /// actual presentation-time differences, including at variable frame rates.
    public static func estimate(_ frames: [PPGCameraFrame]) -> Estimate? {
        guard PPGCaptureQuality.assess(frames) == .readyForAnalysis,
              let first = frames.first, let last = frames.last else { return nil }

        var baseline = first.redLevel
        var smoothed = 0.0
        var previousTime = first.timestamp
        var samples: [(time: TimeInterval, value: Double)] = []
        for frame in frames.dropFirst() {
            let dt = frame.timestamp - previousTime
            baseline += (1 - exp(-dt / 0.5)) * (frame.redLevel - baseline)
            smoothed += (1 - exp(-dt / 0.06)) * (baseline - frame.redLevel - smoothed)
            previousTime = frame.timestamp
            if frame.timestamp - first.timestamp >= 1 {
                samples.append((frame.timestamp, smoothed))
            }
        }

        let levels = samples.map(\.value).sorted()
        guard levels.count >= 3 else { return nil }
        let p10 = levels[(levels.count - 1) / 10]
        let p90 = levels[(levels.count - 1) * 9 / 10]
        let swing = p90 - p10
        guard swing >= 0.001 else { return nil }
        let lower = p10 + swing * 0.3
        let upper = p10 + swing * 0.7

        // Each excursion must cross both hysteresis thresholds. An isolated
        // spike or multiple local maxima during a single excursion count once.
        var peak: (time: TimeInterval, value: Double)?
        var times: [TimeInterval] = []
        var armed = false
        for sample in samples {
            if sample.value <= lower {
                if let peak { times.append(peak.time) }
                peak = nil
                armed = true
            } else if armed && sample.value >= upper && sample.value > (peak?.value ?? -.infinity) {
                peak = sample
            }
        }

        guard times.count >= 6, let start = times.first, let end = times.last,
              end - start >= 0.65 * (last.timestamp - first.timestamp - 1) else { return nil }
        let intervals = zip(times.dropFirst(), times).map { $0.0 - $0.1 }
        let sorted = intervals.sorted()
        let middle = sorted.count / 2
        let median = (sorted[(sorted.count - 1) / 2] + sorted[middle]) / 2
        // Reject the recording rather than deleting missing or extra beats.
        guard intervals.allSatisfy({ (0.33...1.5).contains($0) && abs($0 - median) <= 0.20 * median }) else {
            return nil
        }
        return Estimate(beatsPerMinute: 60 / median, intervals: intervals)
    }
}
