import Foundation
import Combine
import HealthCore


/// User-entered recovery inputs, stored locally only (never written to
/// HealthKit, never uploaded): personal sleep target, daily energy and
/// fatigue ratings (0-10), and per-workout session-RPE ratings (0-10).
/// Ratings are the user's own reports. Nothing is imputed from HRV,
/// heart rate, or any physiological signal.
/// Build 28 P1-5: per-day delete, clear-all, temp-file save with re-read
/// validation, .bak kept, .bak fallback on load, and PrivateRecovery
/// excluded from backup. Day keys stay yyyy-MM-dd calendar-date strings.
@MainActor
final class RecoveryInputsStore: ObservableObject {
    struct Rating: Codable, Equatable {
        var value: Double
        var recordedAt: Date
    }


    struct Saved: Codable, Equatable {
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


    /// Last copy written to disk successfully; persist() rolls the
    /// in-memory state back to this copy when a save fails.
    private var lastPersistedSaved: Saved?


    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateRecovery", isDirectory: true)
            .appendingPathComponent("inputs.json")
    }


    private var directoryURL: URL { fileURL.deletingLastPathComponent() }
    private var backupURL: URL { fileURL.appendingPathExtension("bak") }
    private var tempURL: URL { fileURL.appendingPathExtension("tmp") }


    init() {
        ensurePrivateDirectory()
        load()
    }


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


    /// Build 28 P1-5: delete one day's energy rating. The day is the
    /// yyyy-MM-dd key, so only that calendar date is removed.
    func deleteEnergy(on date: Date) {
        saved.energyRatings.removeValue(forKey: Self.dayKey(for: date))
        persist()
    }


    /// Build 28 P1-5: delete one day's fatigue rating.
    func deleteFatigue(on date: Date) {
        saved.fatigueRatings.removeValue(forKey: Self.dayKey(for: date))
        persist()
    }


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


    /// Build 28 P1-5: clear all self-ratings (energy, fatigue and
    /// workout RPE). Sleep target and explicit coverage verification are
    /// kept: they are a setting and a verification, not ratings. The UI
    /// asks for confirmation before calling this.
    func clearAllSelfRatings() {
        saved.energyRatings.removeAll()
        saved.fatigueRatings.removeAll()
        saved.workoutExertion.removeAll()
        persist()
    }


    /// Build 28 P1-5: whether any self-rating is stored.
    var hasAnySelfRating: Bool {
        !saved.energyRatings.isEmpty || !saved.fatigueRatings.isEmpty || !saved.workoutExertion.isEmpty
    }


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


    /// Build 28 P1-5: the day key is the yyyy-MM-dd calendar-date string
    /// in the current calendar at save time. It is stored as a string, so
    /// a later time-zone change does not move a rating to another date.
    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }


    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: fileURL))
            lastPersistedSaved = saved
        } catch {
            // Build 28 P1-5: fall back to the .bak copy kept by persist().
            if let backupData = try? Data(contentsOf: backupURL),
               let restored = try? JSONDecoder().decode(Saved.self, from: backupData) {
                saved = restored
                lastPersistedSaved = restored
                errorMessage = "本地恢复记录已从备份恢复"
            } else {
                errorMessage = "本地恢复记录读取失败：\(error.localizedDescription)"
            }
        }
    }


    /// Build 28 P1-5: make the PrivateRecovery directory excluded from
    /// backup. Self-ratings stay on this device only.
    private func ensurePrivateDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL,
                                                 withIntermediateDirectories: true)
        var url = directoryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }


    private func persist() {
        let previous = lastPersistedSaved ?? Saved()
        do {
            ensurePrivateDirectory()
            let data = try JSONEncoder().encode(saved)
            try data.write(to: tempURL, options: [.completeFileProtection])
            // Validate by reading the temp file back before replacing.
            let roundTripped = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: tempURL))
            guard roundTripped == saved else {
                throw NSError(domain: "RecoveryInputsStore", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "校验重读与待保存内容不一致"])
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: backupURL)
                }
                try FileManager.default.moveItem(at: fileURL, to: backupURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
            lastPersistedSaved = saved
            errorMessage = nil
        } catch {
            // Build 28 P1-5: roll back in-memory state to the last saved
            // copy; the .bak file remains for the next load().
            try? FileManager.default.removeItem(at: tempURL)
            saved = previous
            errorMessage = "本地恢复记录保存失败：\(error.localizedDescription)"
        }
    }
}
