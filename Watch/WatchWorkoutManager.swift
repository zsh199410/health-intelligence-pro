import Foundation
import Combine
import HealthKit

private enum WatchWorkoutError: LocalizedError {
    case collectionFailed, endFailed

    var errorDescription: String? {
        switch self {
        case .collectionFailed: return "无法开始收集训练数据。"
        case .endFailed: return "无法结束训练数据收集。"
        }
    }
}

/// A workout only runs after the person explicitly starts it on Apple Watch.
/// The builder supplies live workout samples; the dashboard's historical
/// HealthKit readings remain a separate, on-demand source.
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle, starting, running, paused, ending, saveFailed, finished
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var heartRate: Double?
    @Published private(set) var heartRateRecordedAt: Date?
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var completedDuration: TimeInterval?
    @Published private(set) var saveConfirmed = false
    @Published private(set) var displayNow = Date()
    @Published var errorMessage: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var didAttemptRecovery = false
    private var finishing = false
    private var didEndCollection = false
    private var finishDate: Date?
    private let activeFlagKey = "watchWorkoutActive"

    private var heartRateType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .heartRate)!
    }

    var isActive: Bool {
        switch phase {
        case .starting, .running, .paused, .ending, .saveFailed: return true
        case .idle, .finished: return false
        }
    }

    var hasRecentHeartRate: Bool {
        guard let heartRateRecordedAt else { return false }
        return displayNow.timeIntervalSince(heartRateRecordedAt) >= 0 &&
            displayNow.timeIntervalSince(heartRateRecordedAt) < 30
    }

    func start(_ activity: HKWorkoutActivityType) async {
        guard session == nil, phase == .idle || phase == .finished else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "当前手表无法使用健康数据。"
            return
        }

        phase = .starting
        errorMessage = nil
        heartRate = nil
        heartRateRecordedAt = nil
        elapsedTime = 0
        completedDuration = nil
        saveConfirmed = false
        didEndCollection = false
        finishDate = nil

        do {
            try await healthStore.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [heartRateType]
            )

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activity
            configuration.locationType = .unknown
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: configuration
            )
            newSession.delegate = self
            newBuilder.delegate = self
            session = newSession
            builder = newBuilder

            let startedAt = Date()
            UserDefaults.standard.set(true, forKey: activeFlagKey)
            newSession.startActivity(with: startedAt)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                newBuilder.beginCollection(withStart: startedAt) { success, error in
                    if success { continuation.resume(returning: ()) }
                    else { continuation.resume(throwing: error ?? WatchWorkoutError.collectionFailed) }
                }
            }
            if phase == .starting { phase = .running }
            startTimer()
        } catch {
            fail("训练启动失败：\(error.localizedDescription)")
        }
    }

    func pause() {
        guard phase == .running else { return }
        session?.pause()
    }

    func resume() {
        guard phase == .paused else { return }
        session?.resume()
    }

    func end() {
        guard phase == .running || phase == .paused, let session else { return }
        phase = .ending
        session.stopActivity(with: Date())
    }

    /// Called on launch so a session interrupted by the app process can be
    /// restored instead of being silently abandoned in HealthKit.
    func recoverActiveWorkoutIfNeeded(force: Bool = false) {
        guard !didAttemptRecovery else { return }
        guard force || UserDefaults.standard.bool(forKey: activeFlagKey) else { return }
        didAttemptRecovery = true
        phase = .starting
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            Task { @MainActor [weak self] in
                guard let self, self.session == nil else { return }
                if let recovered {
                    let recoveredBuilder = recovered.associatedWorkoutBuilder()
                    recoveredBuilder.dataSource = HKLiveWorkoutDataSource(
                        healthStore: self.healthStore,
                        workoutConfiguration: recovered.workoutConfiguration
                    )
                    recovered.delegate = self
                    recoveredBuilder.delegate = self
                    self.session = recovered
                    self.builder = recoveredBuilder
                    self.updateHeartRate(from: recoveredBuilder)
                    self.tick()
                    switch recovered.state {
                    case .running:
                        self.phase = .running
                        self.startTimer()
                    case .paused:
                        self.phase = .paused
                        self.startTimer()
                    case .stopped:
                        self.phase = .ending
                        self.didEndCollection = recoveredBuilder.endDate != nil
                        self.beginFinishing(at: recovered.endDate ?? recoveredBuilder.endDate ?? Date())
                    default:
                        self.session = nil
                        self.builder = nil
                        self.phase = .idle
                        UserDefaults.standard.set(false, forKey: self.activeFlagKey)
                    }
                } else if let error {
                    self.phase = .idle
                    UserDefaults.standard.set(false, forKey: self.activeFlagKey)
                    self.errorMessage = "恢复训练失败：\(error.localizedDescription)"
                } else {
                    self.phase = .idle
                    UserDefaults.standard.set(false, forKey: self.activeFlagKey)
                }
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        tick()
    }

    private func tick() {
        displayNow = Date()
        if let builder { elapsedTime = max(0, builder.elapsedTime(at: displayNow)) }
    }

    private func updateHeartRate(from builder: HKLiveWorkoutBuilder) {
        guard let statistics = builder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity(),
              let interval = statistics.mostRecentQuantityDateInterval() else { return }
        let value = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        guard value.isFinite, value > 0 else { return }
        heartRate = value
        heartRateRecordedAt = interval.end
        displayNow = Date()
    }

    private func beginFinishing(at date: Date) {
        guard !finishing, let builder else { return }
        finishing = true
        finishDate = date
        phase = .ending
        timer?.invalidate()
        timer = nil
        completedDuration = max(0, builder.elapsedTime(at: date))
        Task { @MainActor in
            do {
                if !didEndCollection {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        builder.endCollection(withEnd: date) { success, error in
                            if success { continuation.resume(returning: ()) }
                            else { continuation.resume(throwing: error ?? WatchWorkoutError.endFailed) }
                        }
                    }
                    didEndCollection = true
                }
                // A nil workout with no error can occur while the device is
                // locked. Apple says it may still have saved; report the
                // result as unverified rather than claiming success or retrying.
                let confirmed = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    builder.finishWorkout { workout, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: workout != nil) }
                    }
                }
                saveConfirmed = confirmed
                session?.end()
                session = nil
                self.builder = nil
                phase = .finished
                finishing = false
                UserDefaults.standard.set(false, forKey: activeFlagKey)
            } catch {
                // Keep the stopped builder so the person can retry saving.
                // Discarding here would erase the unsaved workout.
                finishing = false
                phase = .saveFailed
                errorMessage = "训练保存失败：\(error.localizedDescription)"
            }
        }
    }

    func retrySaving() {
        guard phase == .saveFailed, let finishDate else { return }
        errorMessage = nil
        beginFinishing(at: finishDate)
    }

    func discardUnsavedWorkout() {
        guard phase == .saveFailed else { return }
        builder?.discardWorkout()
        session?.end()
        builder = nil
        session = nil
        finishDate = nil
        didEndCollection = false
        phase = .idle
        UserDefaults.standard.set(false, forKey: activeFlagKey)
    }

    private func fail(_ message: String) {
        timer?.invalidate()
        timer = nil
        builder?.discardWorkout()
        session?.end()
        builder = nil
        session = nil
        finishing = false
        finishDate = nil
        didEndCollection = false
        phase = .idle
        UserDefaults.standard.set(false, forKey: activeFlagKey)
        errorMessage = message
    }

}

extension WatchWorkoutManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            switch toState {
            case .running:
                if self.phase != .ending { self.phase = .running; self.startTimer() }
            case .paused:
                if self.phase != .ending { self.phase = .paused; self.tick() }
            case .stopped:
                self.phase = .ending
                self.beginFinishing(at: date)
            case .ended:
                if !self.finishing && self.phase != .finished && self.phase != .saveFailed {
                    if self.builder != nil {
                        self.errorMessage = "训练意外结束，正在保存已采集的部分。"
                        self.beginFinishing(at: date)
                    } else {
                        self.fail("训练意外结束，请重新开始。")
                    }
                }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === workoutSession else { return }
            if self.phase == .ending && self.finishing {
                self.errorMessage = "训练连接中断，正在核对保存结果。"
            } else if self.phase == .ending || self.phase == .saveFailed {
                self.finishing = false
                self.phase = .saveFailed
                self.errorMessage = "训练保存中断：\(error.localizedDescription)"
            } else if self.phase == .running || self.phase == .paused {
                self.errorMessage = "训练中断，正在尝试保存已采集的部分。"
                self.beginFinishing(at: Date())
            } else {
                self.fail("训练中断：\(error.localizedDescription)")
            }
        }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            if collectedTypes.contains(self.heartRateType) { self.updateHeartRate(from: workoutBuilder) }
            self.tick()
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            self.tick()
        }
    }
}
