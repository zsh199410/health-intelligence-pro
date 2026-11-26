import Foundation

/// Research-only detector for short, continuous single-lead recordings.
/// Peaks are candidate QRS fiducials. An accepted signal has no rhythm classification.
public enum ECGBeatDetector {
    public enum Rejection: Error, Equatable {
        case insufficientDuration, unsupportedCadence, interruptedSampling, weakOrNoisySignal, tooFewBeats
    }

    public struct Beats: Sendable {
        public let peakTimes: [TimeInterval]
        public var rrIntervals: [TimeInterval] { zip(peakTimes.dropFirst(), peakTimes).map(-) }
    }

    public static func detect(in trace: ECGWaveform) -> Result<Beats, Rejection> {
        let samples = trace.samples
        guard let first = samples.first, let last = samples.last,
              last.seconds - first.seconds >= 5 else { return .failure(.insufficientDuration) }
        let spacings = zip(samples.dropFirst(), samples).map { $0.seconds - $1.seconds }.sorted()
        let period = spacings[spacings.count / 2]
        let hz = 1 / period
        guard (100...2048).contains(hz) else { return .failure(.unsupportedCadence) }
        guard trace.gapCount == 0, spacings.first! >= 0.5 * period, spacings.last! <= 1.5 * period else {
            return .failure(.interruptedSampling)
        }

        // A digitally frozen section can otherwise be misreported as one long RR.
        var lastChange = first.seconds
        for (previous, sample) in zip(samples, samples.dropFirst()) {
            if sample.millivolts != previous.millivolts {
                lastChange = sample.seconds
            } else if sample.seconds - lastChange >= 1 {
                return .failure(.weakOrNoisySignal)
            }
        }

        // Difference across 16 ms suppresses slow drift. Smooth its absolute
        // magnitude over 64 ms to obtain a polarity-independent QRS activity envelope.
        let lag = max(1, Int((0.016 * hz).rounded()))
        let width = max(1, Int((0.064 * hz).rounded()))
        let radius = max(1, Int((0.085 * hz).rounded()))
        let margin = radius + width + lag
        var envelope = [Double](repeating: 0, count: samples.count)
        var prefix = [Double](repeating: 0, count: samples.count + 1)
        for i in lag..<samples.count {
            let step = abs(samples[i].millivolts - samples[i - lag].millivolts)
            prefix[i + 1] = prefix[i] + step
            if i >= width + lag {
                envelope[i] = (prefix[i + 1] - prefix[i + 1 - width]) / Double(width)
            }
        }
        guard samples.count > 2 * margin else { return .failure(.insufficientDuration) }
        let interior = margin..<(samples.count - margin)
        let ordered = envelope[interior].sorted()
        let floor = ordered[ordered.count / 2]
        let high = ordered[(ordered.count - 1) * 95 / 100]
        guard high.isFinite, high > max(0.025, 3 * floor) else { return .failure(.weakOrNoisySignal) }
        let threshold = floor + 0.45 * (high - floor)
        var peaks: [(time: Double, strength: Double)] = []
        var i = interior.lowerBound
        while i < interior.upperBound {
            guard envelope[i] >= threshold else { i += 1; continue }
            var strongest = i
            repeat {
                if envelope[i] > envelope[strongest] { strongest = i }
                i += 1
            } while i < interior.upperBound && envelope[i] >= threshold

            let center = strongest - (width + lag) / 2
            let window = (center - radius)...(center + radius)
            let baseline = (samples[window.lowerBound].millivolts + samples[window.upperBound].millivolts) / 2
            let index = window.max {
                abs(samples[$0].millivolts - baseline) < abs(samples[$1].millivolts - baseline)
            }!
            let peak = (time: samples[index].seconds, strength: envelope[strongest])
            if let prior = peaks.last, peak.time - prior.time < 0.25 {
                if peak.strength > prior.strength { peaks[peaks.count - 1] = peak }
            } else {
                peaks.append(peak)
            }
        }
        guard peaks.count >= 3 else { return .failure(.tooFewBeats) }
        return .success(Beats(peakTimes: peaks.map(\.time)))
    }
}
