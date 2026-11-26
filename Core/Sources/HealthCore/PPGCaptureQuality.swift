import Foundation

/// Scalar measurements extracted on-device from one camera region of interest.
public struct PPGCameraFrame {
    /// Monotonic presentation time in seconds, relative to this acquisition.
    public let timestamp: TimeInterval
    /// Mean red-channel intensity normalized to 0...1.
    public let redLevel: Double
    /// Fraction of red-channel pixels at either digital limit.
    public let clippedFraction: Double

    /// Half-differences in normalized mean red level: left minus right, top minus bottom.
    /// Optional for scalar-only recordings. No images or pixel locations are retained.
    public let spatialContrast: SIMD2<Double>?

    public init(timestamp: TimeInterval, redLevel: Double, clippedFraction: Double,
                spatialContrast: SIMD2<Double>? = nil) {
        self.timestamp = timestamp
        self.redLevel = redLevel
        self.clippedFraction = clippedFraction
        self.spatialContrast = spatialContrast
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
        case unstableContact
        case readyForAnalysis
    }

    /// Expects frames in capture order, with timestamps taken from the camera.
    public static func assess(_ frames: [PPGCameraFrame]) -> Result {
        guard let first = frames.first, let last = frames.last else { return .insufficientDuration }
        var previous: TimeInterval?
        var baseline = first.redLevel
        var contrastBaseline = first.spatialContrast ?? .zero
        var commonEnergy = 0.0
        var contrastEnergy = SIMD2<Double>.zero
        var largestGap = 0.0
        var clippedFrames = 0
        var mean = 0.0
        var squaredDeviations = 0.0

        for (index, frame) in frames.enumerated() {
            guard frame.timestamp.isFinite,
                  (0...1).contains(frame.redLevel),
                  (0...1).contains(frame.clippedFraction) else { return .invalidFrame }
            guard (frame.spatialContrast == nil) == (first.spatialContrast == nil) else { return .invalidFrame }
            if let contrast = frame.spatialContrast {
                guard (-0.5...0.5).contains(contrast.x), (-0.5...0.5).contains(contrast.y) else {
                    return .invalidFrame
                }
            }
            if let previous {
                let gap = frame.timestamp - previous
                guard gap > 0 else { return .irregularTiming }
                largestGap = max(largestGap, gap)
                if let contrast = frame.spatialContrast {
                    // Compare common pulsation energy to changing left/right or top/bottom
                    // contrast. Remove static illumination and weight by real elapsed time.
                    let alpha = 1 - exp(-gap / 0.4)
                    baseline += alpha * (frame.redLevel - baseline)
                    contrastBaseline += alpha * (contrast - contrastBaseline)
                    let ac = frame.redLevel - baseline
                    let differential = contrast - contrastBaseline
                    commonEnergy += ac * ac * gap
                    contrastEnergy += differential * differential * gap
                }
            }
            // A high-rate burst must not hide a low-rate section of the recording.
            if index >= 18 && frame.timestamp - frames[index - 18].timestamp > 1.0 {
                return .irregularTiming
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
        if first.spatialContrast != nil && max(contrastEnergy.x, contrastEnergy.y) > 0.64 * commonEnergy {
            return .unstableContact
        }
        return .readyForAnalysis
    }
}
