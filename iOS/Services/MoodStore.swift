import Combine
import Foundation
import HealthKit

/// A person's own description of how they feel. These choices never come from
/// heart rate, HRV, or any other sensor reading.
enum MoodFeeling: String, CaseIterable, Identifiable, Codable, Hashable {
    case veryUnpleasant, unpleasant, neutral, pleasant, veryPleasant

    var id: Self { self }

    var title: String {
        switch self {
        case .veryUnpleasant: return "很不愉快"
        case .unpleasant: return "有点不愉快"
        case .neutral: return "平静"
        case .pleasant: return "有点愉快"
        case .veryPleasant: return "很愉快"
        }
    }

    var symbol: String {
        switch self {
        case .veryUnpleasant: return "cloud.rain"
        case .unpleasant: return "cloud"
        case .neutral: return "circle"
        case .pleasant: return "sun.horizon"
        case .veryPleasant: return "sun.max"
        }
    }

    /// HealthKit valence is a self-reported value from -1 to 1.
    var valence: Double {
        switch self {
        case .veryUnpleasant: return -0.8
        case .unpleasant: return -0.4
        case .neutral: return 0
        case .pleasant: return 0.4
        case .veryPleasant: return 0.8
        }
    }

    static func description(for valence: Double) -> String {
        switch valence {
        case ..<(-0.6): return veryUnpleasant.title
        case ..<(-0.2): return unpleasant.title
        case ..<0.2: return neutral.title
        case ..<0.6: return pleasant.title
        default: return veryPleasant.title
        }
    }
}

enum MoodLabel: String, CaseIterable, Identifiable, Codable, Hashable {
    case calm, happy, anxious, drained, stressed, relieved

    var id: Self { self }

    var title: String {
        switch self {
        case .calm: return "平静"
        case .happy: return "开心"
        case .anxious: return "焦虑"
        case .drained: return "疲惫"
        case .stressed: return "压力大"
        case .relieved: return "放松"
        }
    }

    var healthKitValue: HKStateOfMind.Label {
        switch self {
        case .calm: return .calm
        case .happy: return .happy
        case .anxious: return .anxious
        case .drained: return .drained
        case .stressed: return .stressed
        case .relieved: return .relieved
        }
    }

    static func title(for value: HKStateOfMind.Label) -> String {
        switch value {
        case .amazed: return "惊喜"
        case .amused: return "觉得有趣"
        case .angry: return "生气"
        case .annoyed: return "烦躁"
        case .anxious: return "焦虑"
        case .ashamed: return "羞愧"
        case .brave: return "勇敢"
        case .calm: return "平静"
        case .confident: return "自信"
        case .content: return "知足"
        case .disappointed: return "失望"
        case .discouraged: return "沮丧"
        case .disgusted: return "厌恶"
        case .drained: return "疲惫"
        case .embarrassed: return "尴尬"
        case .excited: return "兴奋"
        case .frustrated: return "挫败"
        case .grateful: return "感激"
        case .guilty: return "内疚"
        case .happy: return "开心"
        case .hopeful: return "有希望"
        case .hopeless: return "失去希望"
        case .indifferent: return "无所谓"
        case .irritated: return "恼怒"
        case .jealous: return "嫉妒"
        case .joyful: return "喜悦"
        case .lonely: return "孤独"
        case .overwhelmed: return "不堪重负"
        case .passionate: return "热情"
        case .peaceful: return "安宁"
        case .proud: return "自豪"
        case .relieved: return "放松"
        case .sad: return "难过"
        case .satisfied: return "满意"
        case .scared: return "害怕"
        case .stressed: return "压力大"
        case .surprised: return "惊讶"
        case .worried: return "担忧"
        @unknown default: return "其他感受"
        }
    }
}

enum MoodAssociation: String, CaseIterable, Identifiable, Codable, Hashable {
    case work, family, friends, health, fitness, selfCare

    var id: Self { self }

    var title: String {
        switch self {
        case .work: return "工作"
        case .family: return "家人"
        case .friends: return "朋友"
        case .health: return "健康"
        case .fitness: return "运动"
        case .selfCare: return "自我照顾"
        }
    }

    var healthKitValue: HKStateOfMind.Association {
        switch self {
        case .work: return .work
        case .family: return .family
        case .friends: return .friends
        case .health: return .health
        case .fitness: return .fitness
        case .selfCare: return .selfCare
        }
    }

    static func title(for value: HKStateOfMind.Association) -> String {
        switch value {
        case .community: return "社区"
        case .currentEvents: return "时事"
        case .dating: return "约会"
        case .education: return "学习"
        case .family: return "家人"
        case .fitness: return "运动"
        case .friends: return "朋友"
        case .health: return "健康"
        case .hobbies: return "爱好"
        case .identity: return "自我认同"
        case .money: return "财务"
        case .partner: return "伴侣"
        case .selfCare: return "自我照顾"
        case .spirituality: return "精神生活"
        case .tasks: return "待办事项"
        case .travel: return "旅行"
        case .weather: return "天气"
        case .work: return "工作"
        @unknown default: return "其他因素"
        }
    }
}

struct MoodEntry: Identifiable {
    enum Origin: Equatable { case appleHealth, local }

    let id: UUID
    let recordedAt: Date
    let feeling: String
    let labels: [String]
    let associations: [String]
    let source: String
    let origin: Origin

    init(sample: HKStateOfMind) {
        id = sample.uuid
        recordedAt = sample.startDate
        feeling = MoodFeeling.description(for: sample.valence)
        labels = sample.labels.map(MoodLabel.title(for:))
        associations = sample.associations.map(MoodAssociation.title(for:))
        source = sample.sourceRevision.source.name
        origin = .appleHealth
    }

    init(local: LocalMoodRecord) {
        id = local.id
        recordedAt = local.recordedAt
        feeling = local.feeling.title
        labels = local.labels.map(\.title)
        associations = local.associations.map(\.title)
        source = "本机私密记录"
        origin = .local
    }
}

struct LocalMoodRecord: Codable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let feeling: MoodFeeling
    let labels: [MoodLabel]
    let associations: [MoodAssociation]
}

/// Reads only the latest self-reported momentary emotion. Reading returns an
/// empty result both when there are no samples and when read access is denied;
/// HealthKit intentionally does not let apps distinguish those cases.
@MainActor
final class MoodStore: ObservableObject {
    @Published private(set) var latest: MoodEntry?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var latestNeedsVerification = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var localRecords: [LocalMoodRecord] = []

    private let healthStore = HKHealthStore()
    private var observer: HKObserverQuery?
    private var healthEntry: MoodEntry?
    /// A successful write can be known even when the person declines read
    /// access. Keep that result for this process, marked as unverified after
    /// a later empty read, without persisting a duplicate health record.
    private var lastSavedByThisApp: MoodEntry?
    private var localFileLoadFailed = false

    init() {
        do {
            if FileManager.default.fileExists(atPath: localFileURL.path) {
                let data = try Data(contentsOf: localFileURL)
                localRecords = try JSONDecoder().decode([LocalMoodRecord].self, from: data)
            }
            updateLatest()
        } catch {
            localFileLoadFailed = true
            errorMessage = "本机心情记录读取失败，请检查设备存储。"
        }
    }

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthEntry = lastSavedByThisApp
            latestNeedsVerification = lastSavedByThisApp != nil
            updateLatest()
            errorMessage = "当前设备无法读取 Apple 健康，本机记录仍可使用。"
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let sample = try await newestMomentaryEmotion()
            if let sample {
                healthEntry = MoodEntry(sample: sample)
                latestNeedsVerification = false
            } else {
                healthEntry = lastSavedByThisApp
                latestNeedsVerification = lastSavedByThisApp != nil
            }
            updateLatest()
            errorMessage = localFileLoadFailed ? "本机心情记录读取失败，请检查设备存储。" : nil
        } catch {
            errorMessage = "心情记录读取失败，请稍后重试。"
        }
    }

    /// Requests read access only after the person explicitly chooses to load
    /// their Apple Health mood history. Completion is not proof of a grant.
    func connectHealthHistory() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "当前设备无法使用 Apple 健康。"
            return
        }
        do {
            try await healthStore.requestAuthorization(
                toShare: [], read: [HKObjectType.stateOfMindType()]
            )
            await refresh()
        } catch {
            errorMessage = "无法请求读取心情记录，请检查 Apple 健康权限。"
        }
    }

    /// A write request is deliberately delayed until Save is tapped. The
    /// selected feeling, labels, and associations come solely from the user.
    @discardableResult
    func save(
        feeling: MoodFeeling,
        labels: Set<MoodLabel>,
        associations: Set<MoodAssociation>
    ) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "当前设备无法使用 Apple 健康。"
            return false
        }
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let sampleType = HKObjectType.stateOfMindType()
        do {
            try await healthStore.requestAuthorization(toShare: [sampleType], read: [sampleType])
            guard healthStore.authorizationStatus(for: sampleType) == .sharingAuthorized else {
                errorMessage = "未获得心情记录的写入权限，可在 Apple 健康中调整。"
                return false
            }
            let sample = HKStateOfMind(
                date: Date(),
                kind: .momentaryEmotion,
                valence: feeling.valence,
                labels: MoodLabel.allCases.filter(labels.contains).map(\.healthKitValue),
                associations: MoodAssociation.allCases.filter(associations.contains).map(\.healthKitValue)
            )
            try await healthStore.save(sample)
            let saved = MoodEntry(sample: sample)
            lastSavedByThisApp = saved
            healthEntry = saved
            latestNeedsVerification = false
            updateLatest()
            hasLoaded = true
            errorMessage = localFileLoadFailed ? "本机心情记录读取失败，请检查设备存储。" : nil
            return true
        } catch {
            errorMessage = "心情记录未保存到 Apple 健康，请重试。"
            return false
        }
    }

    /// An explicit private alternative when HealthKit is unavailable or the
    /// person prefers not to write a self-report to Apple Health.
    @discardableResult
    func saveLocally(
        feeling: MoodFeeling,
        labels: Set<MoodLabel>,
        associations: Set<MoodAssociation>,
        replacing id: UUID? = nil
    ) -> Bool {
        var updated = localRecords
        let original = id.flatMap { identifier in updated.first { $0.id == identifier } }
        if id != nil && original == nil {
            errorMessage = "找不到要修改的本机记录。"
            return false
        }
        let record = LocalMoodRecord(
            id: original?.id ?? UUID(),
            recordedAt: original?.recordedAt ?? Date(),
            feeling: feeling,
            labels: MoodLabel.allCases.filter(labels.contains),
            associations: MoodAssociation.allCases.filter(associations.contains)
        )
        if let index = updated.firstIndex(where: { $0.id == record.id }) {
            updated[index] = record
        } else {
            updated.append(record)
        }
        return persist(updated)
    }

    @discardableResult
    func deleteLocal(id: UUID) -> Bool {
        let updated = localRecords.filter { $0.id != id }
        guard updated.count != localRecords.count else {
            errorMessage = "找不到要删除的本机记录。"
            return false
        }
        return persist(updated)
    }

    /// Observe changes while the card is visible, including entries added in
    /// Apple's Mindfulness app. No polling or background-delivery claim.
    func startObserving() {
        guard HKHealthStore.isHealthDataAvailable(), observer == nil else { return }
        let query = HKObserverQuery(sampleType: HKObjectType.stateOfMindType(), predicate: nil) {
            [weak self] _, completion, _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
                completion()
            }
        }
        observer = query
        healthStore.execute(query)
    }

    func stopObserving() {
        guard let observer else { return }
        healthStore.stop(observer)
        self.observer = nil
    }

    private func newestMomentaryEmotion() async throws -> HKStateOfMind? {
        let predicate = HKQuery.predicateForStatesOfMind(with: HKStateOfMind.Kind.momentaryEmotion)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.stateOfMindType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKStateOfMind)
                }
            }
            healthStore.execute(query)
        }
    }

    private var localFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateMood", isDirectory: true)
            .appendingPathComponent("entries.json")
    }

    private func persist(_ records: [LocalMoodRecord]) -> Bool {
        guard !localFileLoadFailed else {
            errorMessage = "本机记录暂不可读取，已停止写入以保护原有数据。"
            return false
        }
        do {
            var directory = localFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try directory.setResourceValues(resourceValues)
            let data = try JSONEncoder().encode(records)
            try data.write(to: localFileURL, options: [.atomic, .completeFileProtection])
            localRecords = records
            updateLatest()
            hasLoaded = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = "本机心情记录保存失败，原有记录未更改。"
            return false
        }
    }

    private func updateLatest() {
        let local = localRecords.max { $0.recordedAt < $1.recordedAt }.map(MoodEntry.init(local:))
        latest = [healthEntry, local].compactMap { $0 }.max { $0.recordedAt < $1.recordedAt }
    }
}
