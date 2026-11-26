import Foundation

/// Research-only single-lead QRS boundaries around one candidate fiducial.
/// Output is the local slope envelope's active duration. Bundle branch block,
/// pacing, baseline artifact and low-amplitude tails can change both boundaries.
public struct ExperimentalQRSDuration: Sendable {
    public let onset: ECGVoltagePoint
    public let offset: ECGVoltagePoint
    public var milliseconds: Double { (offset.seconds - onset.seconds) * 1000 }

    /// peakSeconds must be a raw sample timestamp from this trace's accepted beat list.
    public static func measure(in trace: ECGWaveform, peakSeconds: Double) -> Self? {
        let points = trace.samples
        guard peakSeconds.isFinite else { return nil }
        var lo = 0, hi = points.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if points[mid].seconds < peakSeconds { lo = mid + 1 } else { hi = mid }
        }
        let peak = lo
        guard peak > 0, peak < points.count - 1, points[peak].seconds == peakSeconds else { return nil }
        let period = (points[peak + 1].seconds - points[peak - 1].seconds) / 2
        guard (100...2048).contains(1 / period) else { return nil }
        let radius = Int((0.14 / period).rounded()), lag = max(1, Int((0.006 / period).rounded()))
        let quiet = max(2, Int((0.012 / period).rounded()))
        let start = peak - radius, end = peak + radius
        guard start >= lag, end + lag < points.count else { return nil }
        for i in (start - lag + 1)...(end + lag) {
            guard (0.5 * period ... 1.5 * period).contains(points[i].seconds - points[i - 1].seconds) else { return nil }
        }
        // Total variation over a centered 12 ms window also captures a change
        // of slope at the apex of a biphasic complex.
        var variation = [Double](repeating: 0, count: 2 * radius + 1)
        var sum = 0.0
        for i in (start - lag + 1)...(start + lag) {
            sum += abs(points[i].millivolts - points[i - 1].millivolts)
        }
        variation[0] = sum
        for i in (start + 1)...end {
            sum += abs(points[i + lag].millivolts - points[i + lag - 1].millivolts)
            sum -= abs(points[i - lag].millivolts - points[i - lag - 1].millivolts)
            variation[i - start] = max(0, sum)
        }
        let flank = max(2, Int((0.020 / period).rounded()))
        let outer = (Array(variation.prefix(flank)) + variation.suffix(flank)).sorted()
        let noise = outer[outer.count / 2]
        let central = max(1, Int((0.028 / period).rounded()))
        guard let strongest = (radius - central...radius + central).max(by: { variation[$0] < variation[$1] }) else { return nil }
        let amplitude = variation[strongest]
        guard amplitude.isFinite, amplitude > max(0.035, 4 * noise) else { return nil }
        let threshold = max(2.5 * noise, 0.09 * amplitude)
        func edge(step: Int) -> Int? {
            var index = strongest, count = 0
            while variation.indices.contains(index) {
                count = variation[index] <= threshold ? count + 1 : 0
                if count == quiet { return start + index - step * (quiet - 1) }
                index += step
            }
            return nil
        }
        guard let left = edge(step: -1), let right = edge(step: 1), left < peak, right > peak else { return nil }
        let result = Self(onset: points[left], offset: points[right])
        guard (35...180).contains(result.milliseconds) else { return nil }
        return result
    }
}
