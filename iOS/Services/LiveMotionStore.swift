import Foundation
import Combine
import CoreMotion

/// Foreground-only iPhone motion readings. These are never substituted for
/// cross-device HealthKit totals.
@MainActor
final class LiveMotionStore: ObservableObject {
    @Published private(set) var isTracking = false
    @Published private(set) var stepsToday: Int?
    @Published private(set) var activityName: String?
    @Published private(set) var stepsMeasuredAt: Date?
    @Published private(set) var activityObservedAt: Date?
    @Published private(set) var errorMessage: String?

    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()

    var isAvailable: Bool {
        CMPedometer.isStepCountingAvailable() || CMMotionActivityManager.isActivityAvailable()
    }

    func start() {
        guard !isTracking else { return }
        guard isAvailable else {
            errorMessage = "此设备不支持实时活动识别"
            return
        }
        errorMessage = nil
        stepsToday = nil
        stepsMeasuredAt = nil
        activityName = nil
        activityObservedAt = nil
        isTracking = true

        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Calendar.current.startOfDay(for: .now)) { [weak self] data, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isTracking else { return }
                    if let data {
                        self.stepsToday = data.numberOfSteps.intValue
                        self.stepsMeasuredAt = data.endDate
                    } else if error != nil {
                        self.errorMessage = "无法读取 iPhone 步数，请检查运动与健身权限"
                    }
                }
            }
        }

        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                Task { @MainActor [weak self] in
                    guard let self, self.isTracking, let activity else { return }
                    self.activityName = Self.name(for: activity)
                    self.activityObservedAt = .now
                }
            }
        }
    }

    func stop() {
        guard isTracking else { return }
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
        isTracking = false
        stepsToday = nil
        stepsMeasuredAt = nil
        activityName = nil
        activityObservedAt = nil
    }

    private static func name(for activity: CMMotionActivity) -> String {
        if activity.running { return "跑步中" }
        if activity.walking { return "步行中" }
        if activity.cycling { return "骑行中" }
        if activity.automotive { return "乘车中" }
        if activity.stationary { return "静止" }
        return "活动类型未知"
    }
}
