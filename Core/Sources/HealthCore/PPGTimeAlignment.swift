import Foundation

/// Compares timestamped sample intervals. Overlap establishes common wall-clock
/// time only; averaged quantities and asynchronous devices are not beat pairs.
public enum PPGTimeAlignment: Equatable {
    case before(seconds: TimeInterval)
    case overlaps
    case after(seconds: TimeInterval)

    public static func compare(sample: ClosedRange<Date>, acquisition: ClosedRange<Date>) -> Self {
        if sample.upperBound < acquisition.lowerBound {
            return .before(seconds: acquisition.lowerBound.timeIntervalSince(sample.upperBound))
        }
        if sample.lowerBound > acquisition.upperBound {
            return .after(seconds: sample.lowerBound.timeIntervalSince(acquisition.upperBound))
        }
        return .overlaps
    }
}
