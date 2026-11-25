import Foundation

/// Scalar measurements extracted on-device from one camera region of interest.
public struct PPGCameraFrame {
    /// Monotonic presentation time in seconds, relative to this acquisition.
    public let timestamp: TimeInterval
    /// Mean red-channel intensity normalized to 0...1.
    public let redLevel: Double
    /// Fraction of red-channel pixels at either digital limit.
    public let clippedFraction: Double

    public init(timestamp: TimeInterval, redLevel: Double, clippedFraction: Double) {
        self.timestamp = timestamp
        self.redLevel = redLevel
        self.clippedFraction = clippedFraction
    }
}

/// Exploratory acquisition checks for a short camera window. Passing only
/// indicates that the samples can proceed to later waveform analysis.
/// The thresholds require calibration against actual device recordings.
public enum PPGCaptureQuality {
    public enum Result: Equatable {
        case invalidFrame
        case insufficientDuration
        case irregularTiming
        case excessiveClipping
        case flatSignal
        case readyForAnalysis
    }

    /// Expects frames in capture order, with timestamps taken from the camera.
    public static func assess(_ frames: [PPGCameraFrame]) -> Result {
        guard let first = frames.first, let last = frames.last else { return .insufficientDuration }
        var previous: TimeInterval?
        var largestGap = 0.0
        var clippedFrames = 0
        var mean = 0.0
        var squaredDeviations = 0.0

        for (index, frame) in frames.enumerated() {
            guard frame.timestamp.isFinite,
                  (0...1).contains(frame.redLevel),
                  (0...1).contains(frame.clippedFraction) else { return .invalidFrame }
            if let previous {
                let gap = frame.timestamp - previous
                guard gap > 0 else { return .irregularTiming }
                largestGap = max(largestGap, gap)
            }
            previous = frame.timestamp
            if frame.clippedFraction >= 0.5 { clippedFrames += 1 }

            let delta = frame.redLevel - mean
            mean += delta / Double(index + 1)
            squaredDeviations += delta * (frame.redLevel - mean)
        }

        let duration = last.timestamp - first.timestamp
        guard duration >= 8 else { return .insufficientDuration }
        guard Double(frames.count - 1) / duration >= 20, largestGap <= 0.15 else {
            return .irregularTiming
        }
        guard Double(clippedFrames) / Double(frames.count) < 0.1 else { return .excessiveClipping }
        guard sqrt(squaredDeviations / Double(frames.count)) >= 0.0005 else { return .flatSignal }
        return .readyForAnalysis
    }
}
