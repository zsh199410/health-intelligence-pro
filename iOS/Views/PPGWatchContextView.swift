import HealthKit
import SwiftUI

/// Reference measurements are read separately from the optical recording.
struct PPGWatchContextView: View {
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
            Button("读取手表最近记录") { Task { await load() } }
                .disabled(isReading)
            Text("列出近七天的独立测量。请核对来源与时间，设备系列以实际配对信息为准。")
                .font(.footnote)
            if let status { Text(status).font(.footnote) }
            ForEach(readings) { row in
                let metric = row.metric
                let sample = row.sample
                let value = sample.quantity.doubleValue(for: metric.unit) * metric.multiplier
                VStack(alignment: .leading) {
                    LabeledContent(metric.name, value: "\(metric.display(value)) \(metric.unitText)")
                    Text(sample.endDate.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))
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
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate]),
            HKQuery.predicateForObjects(withDeviceProperty: HKDevicePropertyKeyModel, allowedValues: ["Watch", "Apple Watch"]),
            HKQuery.predicateForObjects(withDeviceProperty: HKDevicePropertyKeyManufacturer, allowedValues: ["Apple Inc."])
        ])
        var failed: [String] = []
        for metric in metrics {
            do {
                let sample: HKQuantitySample? = try await withCheckedThrowingContinuation { continuation in
                    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
                    store.execute(HKSampleQuery(sampleType: metric.quantityType, predicate: predicate,
                                                limit: 1, sortDescriptors: [sort]) { _, samples, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: samples?.first as? HKQuantitySample) }
                    })
                }
                if let sample { readings.append(Reading(metric: metric, sample: sample)) }
            } catch {
                failed.append(metric.name)
            }
        }
        if !failed.isEmpty { status = "读取失败：" + failed.joined(separator: "、") }
        else { status = readings.isEmpty ? "近七天暂无可读取且带有 Apple Watch 设备标记的记录。" : nil }
    }
}
