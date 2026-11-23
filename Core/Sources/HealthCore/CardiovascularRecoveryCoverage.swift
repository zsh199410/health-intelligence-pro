import Foundation

/// Describes available measurements only. This is NOT a recovery, risk, or
/// disease score; an older HealthKit sample must not be shown as live data.
public enum CardiovascularRecoveryCoverage {
    public static let metricIDs: [String] = [
        "heartRateRecoveryOneMinute",
        "hrv",
        "restingHeartRate",
        "vo2Max"
    ]

    public static func availableMetricIDs(in readings: [String: MetricReading]) -> [String] {
        metricIDs.filter { id in
            guard let reading = readings[id] else { return false }
            return reading.value.isFinite && (id == "heartRateRecoveryOneMinute" || reading.value >= 0)
        }
    }

    /// A recorded, finite one-minute post-exercise heart-rate change (signed).
    /// Nil does not imply that authorization was denied or recovery is poor.
    public static func oneMinuteRecovery(in readings: [String: MetricReading]) -> MetricReading? {
        guard availableMetricIDs(in: readings).contains("heartRateRecoveryOneMinute") else {
            return nil
        }
        return readings["heartRateRecoveryOneMinute"]
    }
}
