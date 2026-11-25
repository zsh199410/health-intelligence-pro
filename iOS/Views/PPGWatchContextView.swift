import HealthCore
import HealthKit
import SwiftUI

/// Reference measurements are read separately from the optical recording.
struct PPGWatchContextView: View {
    let acquisition: ClosedRange<Date>?
    private let timeStyle = Date.FormatStyle.dateTime.month().day().hour().minute().second().locale(Locale(identifier: "zh_CN"))

    private struct Reading: Identifiable {
        let metric: HealthMetric
        let sample: HKQuantitySample
        var id: String { metric.id }
    }

    @State private var readings: [Reading] = []
    @State private var status: String?
    @State private var isReading = false

    var body: some View {
        Section("Apple Watch 参考记录") {
            Button(acquisition == nil ? "读取手表最近记录" : "核对采集时段的手表记录") { Task { await load() } }
                .disabled(isReading)
            if let acquisition {
                Text("相机采集：\(acquisition.lowerBound.formatted(timeStyle)) – \(acquisition.upperBound.formatted(timeStyle))")
                Text("优先展示采集时段内有交集的记录，缺失时标注最近独立测量。时段重叠不能验证逐搏同步。")
                    .font(.footnote)
            }
            Text("列出可读取且带 Apple Watch 设备标记的样本，具体系列以实际配对设备为准。")
                .font(.footnote)
            if let status { Text(status).font(.footnote) }
            ForEach(readings) { row in
                let metric = row.metric
                let sample = row.sample
                let value = sample.quantity.doubleValue(for: metric.unit) * metric.multiplier
                VStack(alignment: .leading) {
                    LabeledContent(metric.name, value: "\(metric.display(value)) \(metric.unitText)")
                    Text("\(sample.startDate.formatted(timeStyle)) – \(sample.endDate.formatted(timeStyle))")
                    if let acquisition {
                        Text(relation(sample: sample, acquisition: acquisition)).font(.footnote)
                    }
                    Text([sample.sourceRevision.source.name, sample.device?.hardwareVersion]
                        .compactMap { $0 }.joined(separator: " · "))
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isReading else { return }
        readings = []
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "当前设备无法读取健康记录。"
            return
        }
        isReading = true
        defer { isReading = false }
        status = "正在读取…"
        let store = HKHealthStore()
        let metrics = ["heartRate", "hrv", "restingHeartRate"].compactMap { HealthCatalog.byID[$0] }
        do {
            try await store.requestAuthorization(toShare: [], read: Set(metrics.map { $0.quantityType as HKObjectType }))
        } catch {
            status = "健康访问请求失败，请稍后重试。"
            return
        }

        let end = Date()
        let start = end.addingTimeInterval(-7 * 24 * 3600)
        let devicePredicates = [
            HKQuery.predicateForObjects(withDeviceProperty: HKDevicePropertyKeyModel, allowedValues: ["Watch", "Apple Watch"]),
            HKQuery.predicateForObjects(withDeviceProperty: HKDevicePropertyKeyManufacturer, allowedValues: ["Apple Inc."])
        ]
        let recent = NSCompoundPredicate(andPredicateWithSubpredicates: devicePredicates + [
            HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
        ])
        let overlap = acquisition.map { window in
            NSCompoundPredicate(andPredicateWithSubpredicates: devicePredicates + [
                HKQuery.predicateForSamples(withStart: window.lowerBound, end: window.upperBound)
            ])
        }
        var failed: [String] = []
        for metric in metrics {
            do {
                var sample: HKQuantitySample?
                if let overlap { sample = try await latest(store: store, metric: metric, predicate: overlap) }
                if sample == nil { sample = try await latest(store: store, metric: metric, predicate: recent) }
                if let sample { readings.append(Reading(metric: metric, sample: sample)) }
            } catch {
                failed.append(metric.name)
            }
        }
        if !failed.isEmpty { status = "读取失败：" + failed.joined(separator: "、") }
        else { status = readings.isEmpty ? "近七天暂无可读取且带有 Apple Watch 设备标记的记录。" : nil }
    }

    private func latest(store: HKHealthStore, metric: HealthMetric, predicate: NSPredicate) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            store.execute(HKSampleQuery(sampleType: metric.quantityType, predicate: predicate,
                                        limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKQuantitySample) }
            })
        }
    }

    private func relation(sample: HKQuantitySample, acquisition: ClosedRange<Date>) -> String {
        switch PPGTimeAlignment.compare(sample: sample.startDate...sample.endDate, acquisition: acquisition) {
        case .overlaps: return "样本时段与相机采集重叠"
        case .before(let seconds): return "历史参考 · 采集前 \(Int(seconds.rounded())) 秒结束"
        case .after(let seconds): return "独立参考 · 采集后 \(Int(seconds.rounded())) 秒开始"
        }
    }
}
