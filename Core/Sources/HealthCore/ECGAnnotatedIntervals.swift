import Foundation

/// Research measurements for one annotated beat within a continuous ECG segment.
/// All inputs are seconds from the same recording origin. Supply nil for each
/// absent or ambiguous landmark. The caller establishes beat identity and signal
/// quality from the original signal before supplying annotations.
public struct ECGAnnotatedIntervals: Equatable, Sendable {
    public let prSeconds: TimeInterval?
    public let qrsSeconds: TimeInterval?
    public let qtSeconds: TimeInterval?
    public let precedingRRSeconds: TimeInterval?
    public let qtcFridericiaSeconds: TimeInterval?

    public enum AnnotationError: Error, Equatable {
        case invalidSegment, outsideSegment, inconsistentOrder
    }

    /// QTcF = QT / cbrt(RR), with QT and the immediately preceding RR in seconds.
    /// Set usePrecedingRRForCorrection only after independent assessment that the
    /// preceding RR is representative (for example, stable rate without ectopy).
    public init(
        within continuousSegment: ClosedRange<TimeInterval>,
        previousR: TimeInterval? = nil,
        pOnset: TimeInterval? = nil,
        qrsOnset: TimeInterval? = nil,
        rPeak: TimeInterval? = nil,
        qrsOffset: TimeInterval? = nil,
        tEnd: TimeInterval? = nil,
        nextR: TimeInterval? = nil,
        usePrecedingRRForCorrection: Bool = false
    ) throws {
        guard continuousSegment.lowerBound.isFinite, continuousSegment.upperBound.isFinite,
              continuousSegment.lowerBound >= 0, continuousSegment.upperBound > continuousSegment.lowerBound else {
            throw AnnotationError.invalidSegment
        }
        let landmarks = [previousR, pOnset, qrsOnset, rPeak, qrsOffset, tEnd, nextR].compactMap { $0 }
        guard landmarks.allSatisfy({ $0.isFinite && continuousSegment.contains($0) }) else {
            throw AnnotationError.outsideSegment
        }
        // Strict ordering rejects unresolved coincident boundaries as well as
        // negative intervals, even when an intervening landmark is absent.
        guard zip(landmarks, landmarks.dropFirst()).allSatisfy(<) else {
            throw AnnotationError.inconsistentOrder
        }
        func duration(from start: Double?, to end: Double?) -> TimeInterval? {
            guard let start, let end else { return nil }
            return end - start
        }
        prSeconds = duration(from: pOnset, to: qrsOnset)
        qrsSeconds = duration(from: qrsOnset, to: qrsOffset)
        qtSeconds = duration(from: qrsOnset, to: tEnd)
        precedingRRSeconds = duration(from: previousR, to: rPeak)
        if usePrecedingRRForCorrection, let qtSeconds, let precedingRRSeconds {
            qtcFridericiaSeconds = qtSeconds / cbrt(precedingRRSeconds)
        } else {
            qtcFridericiaSeconds = nil
        }
    }
}
