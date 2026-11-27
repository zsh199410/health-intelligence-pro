import Foundation
import Combine
import HealthCore

/// User-entered recovery inputs, stored locally only (never written to
/// HealthKit, never uploaded): personal sleep target, daily energy and
/// fatigue ratings (0-10), and per-workout session-RPE ratings (0-10).
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

    /// Sleep target in minutes, 4-12 hours. Nil means the user has not
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
