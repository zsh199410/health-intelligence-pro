import Foundation
import Combine
import HealthCore

/// User-entered recovery inputs, stored locally only (never written to
/// HealthKit, never uploaded): personal sleep target, daily energy and
/// fatigue ratings (0–10), and per-workout session-RPE ratings (0–10).
/// Ratings are the user's own reports. Nothing is imputed from HRV,
/// heart rate, or any physiological signal.
@MainActor
final class RecoveryInputsStore: ObservableObject {
    struct Rating: Codable, Equatable {
        var value: Double
        var recordedAt: Date
    }

    struct Saved: Codable {
        var sleepTargetMinutes: Double?
        var energyRatings: [String: Rating] = [:]
        var fatigueRatings: [String: Rating] = [:]
        var workoutExertion: [String: Double] = [:]
        // Build 28 P0-1: explicit coverage verification (no inference).
        // A date key is present only when the user explicitly verified that
        // day's sleep / activity coverage. Absence means "not verified",
        // never "complete". New keys default to empty, so files saved
        // before Build 28 still decode.
        var verifiedSleepDays: Set<String> = []
        var verifiedActivityDays: Set<String> = []
    }

    @Published private(set) var saved = Saved()
    @Published var errorMessage: String?

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateRecovery", isDirectory: true)
            .appendingPathComponent("inputs.json")
    }

    init() { load() }

    var sleepTargetMinutes: Double? { saved.sleepTargetMinutes }

    /// Sleep target in minutes, 4–12 hours. Nil means the user has not
    /// set a target; shortfall is not computed until one is set.
    func setSleepTarget(minutes: Double?) {
        if let minutes {
            guard (240...720).contains(minutes) else { return }
            saved.sleepTargetMinutes = minutes
        } else {
            saved.sleepTargetMinutes = nil
        }
        persist()
    }

    func rateEnergy(on date: Date, value: Double) {
        guard (0...10).contains(value) else { return }
        saved.energyRatings[Self.dayKey(for: date)] = Rating(value: value, recordedAt: Date())
        persist()
    }

    func rateFatigue(on date: Date, value: Double) {
        guard (0...10).contains(value) else { return }
        saved.fatigueRatings[Self.dayKey(for: date)] = Rating(value: value, recordedAt: Date())
        persist()
    }

    func energy(on date: Date) -> Double? { saved.energyRatings[Self.dayKey(for: date)]?.value }
    func fatigue(on date: Date) -> Double? { saved.fatigueRatings[Self.dayKey(for: date)]?.value }

    func rateWorkout(id: UUID, exertion: Double?) {
        if let exertion {
            guard (0...10).contains(exertion) else { return }
            saved.workoutExertion[id.uuidString] = exertion
        } else {
            saved.workoutExertion.removeValue(forKey: id.uuidString)
        }
        persist()
    }

    func exertion(for id: UUID) -> Double? { saved.workoutExertion[id.uuidString] }

    /// Coverage verification (Build 28 P0-1): only an explicit user
    /// verification confirms a day's sleep or activity coverage. A sleep
    /// interval, a workout, or a step count never confirms a day.
    /// Unverified days stay unconfirmed; a verified day with no
    /// workouts is a real rest day. Every change persists immediately.
    func verifySleep(on date: Date) {
        saved.verifiedSleepDays.insert(Self.dayKey(for: date))
        persist()
    }

    func unverifySleep(on date: Date) {
        saved.verifiedSleepDays.remove(Self.dayKey(for: date))
        persist()
    }

    func isSleepVerified(on date: Date) -> Bool {
        saved.verifiedSleepDays.contains(Self.dayKey(for: date))
    }

    func verifyActivity(on date: Date) {
        saved.verifiedActivityDays.insert(Self.dayKey(for: date))
        persist()
    }

    func unverifyActivity(on date: Date) {
        saved.verifiedActivityDays.remove(Self.dayKey(for: date))
        persist()
    }

    func isActivityVerified(on date: Date) -> Bool {
        saved.verifiedActivityDays.contains(Self.dayKey(for: date))
    }

    func energyPoints() -> [TrendPoint] {
        saved.energyRatings.values.map { TrendPoint(recordedAt: $0.recordedAt, value: $0.value) }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    func fatiguePoints() -> [TrendPoint] {
        saved.fatigueRatings.values.map { TrendPoint(recordedAt: $0.recordedAt, value: $0.value) }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: fileURL)) }
        catch { errorMessage = "本地恢复记录读取失败：\(error.localizedDescription)" }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(saved)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch { errorMessage = "本地恢复记录保存失败：\(error.localizedDescription)" }
    }
}
