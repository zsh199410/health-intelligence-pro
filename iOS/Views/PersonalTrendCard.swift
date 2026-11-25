import SwiftUI
import Charts
import HealthCore

/// Reached from the metric rows of the Health Library.
struct PersonalTrendCard: View {
    let metric: HealthMetric
    @State private var days = 7
    @State private var snapshot: Snapshot?
    @State private var failed = false

    private struct Snapshot {
        let profile: DailyTrendProfile
        let reading: MetricReading?
        let partialChange: Double?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let snapshot {
                    MetricTile(metric: metric, reading: snapshot.reading)
                    if let reading = snapshot.reading {
                        LabeledContent("最近记录来源", value: reading.source)
                        LabeledContent("采样时间", value: reading.recordedAt.formatted(
                            .dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))
                    }
                    HealthCard { trend(snapshot) }
                    HealthCard { reference(snapshot.profile) }
                } else if failed {
                    EmptyHealthState(title: "趋势读取失败", detail: "下拉重新读取此指标。", symbol: "exclamationmark.triangle")
                } else {
                    ProgressView("正在读取健康趋势")
                }
            }.padding(18)
        }
        .background(HealthTheme.canvas.ignoresSafeArea())
        .navigationTitle(metric.name)
        .task(id: metric.id) { await load() }
        .refreshable { await load() }
    }

    private func trend(_ snapshot: Snapshot) -> some View {
        let profile = snapshot.profile
        let runs = profile.runs(days: days)
        let start = profile.calendar.date(byAdding: .day, value: 1 - days, to: profile.calendar.startOfDay(for: profile.end))!
        let count = runs.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 12) {
            Picker("日期范围", selection: $days) {
                ForEach([7, 30, 90], id: \.self) { Text("\($0) 天").tag($0) }
            }.pickerStyle(.segmented)
            if runs.isEmpty {
                Text("此时段暂无可读取记录。")
            } else {
                Chart {
                    ForEach(runs.indices, id: \.self) { index in
                        ForEach(runs[index]) { point in
                            LineMark(x: .value("日期", point.recordedAt), y: .value(metric.unitText, point.value),
                                     series: .value("连续记录", index))
                            PointMark(x: .value("日期", point.recordedAt), y: .value(metric.unitText, point.value))
                        }
                    }
                }
                .chartXScale(domain: start...profile.end)
                .foregroundStyle(HealthTheme.teal)
                .frame(height: 180)
            }
            LabeledContent("有记录日期", value: "\(count) / \(days) 天")
            Text(metric.aggregation == .sumToday ? "各日累计 · 今天截至本次读取" : "各日日均值 · 今天截至本次读取")
                .font(.footnote)
            if let delta = snapshot.partialChange {
                let unit = metric.unitText == "%" ? "百分点" : metric.unitText
                LabeledContent("较昨日同期", value: "\(delta > 0 ? "+" : "")\(metric.display(delta)) \(unit)")
            } else {
                LabeledContent("较昨日同期", value: "暂无可比记录")
            }
            Text("同期按本地零点起相同经过时长比较。数据来源为 Apple 健康汇总，\(profile.calendar.timeZone.identifier)。")
                .font(.caption).foregroundStyle(HealthTheme.muted)
        }
    }

    private func reference(_ profile: DailyTrendProfile) -> some View {
        let b = profile.baseline
        return VStack(alignment: .leading, spacing: 10) {
            Text("个人基线").font(.headline)
            if let middle = b.median, let band = b.middleHalf {
                LabeledContent("历史中位数", value: "\(metric.display(middle)) \(metric.unitText)")
                LabeledContent("中间 50% 区间", value: "\(metric.display(band.lowerBound))–\(metric.display(band.upperBound)) \(metric.unitText)")
                if let yesterday = b.yesterday {
                    let position = yesterday < band.lowerBound ? "低于历史区间" : (yesterday > band.upperBound ? "高于历史区间" : "位于历史区间")
                    LabeledContent("昨日全天", value: "\(metric.display(yesterday)) \(metric.unitText) · \(position)")
                }
            } else {
                Text("历史覆盖不足，至少需 7 个有记录日期。")
            }
            Text("取昨天之前 30 天内的每日汇总，覆盖 \(b.count)/30 天。该区间仅描述个人历史分布。")
                .font(.footnote).foregroundStyle(HealthTheme.muted)
        }
    }

    @MainActor private func load() async {
        let repository = HealthKitRepository()
        let end = Date()
        let calendar = Calendar.current
        do {
            let points = try await repository.trend(metric, days: 90, endingAt: end, calendar: calendar)
            let reading = try await repository.reading(metric)
            var change: Double?
            if let previous = DailyTrendProfile.previousCutoff(end: end, calendar: calendar) {
                let today = try await repository.trend(metric, days: 1, endingAt: end, calendar: calendar)
                let yesterday = try await repository.trend(metric, days: 1, endingAt: previous, calendar: calendar)
                if let lhs = today.first?.value, let rhs = yesterday.first?.value { change = lhs - rhs }
            }
            try Task.checkCancellation()
            snapshot = Snapshot(profile: DailyTrendProfile(points: points, end: end, calendar: calendar),
                                reading: reading, partialChange: change)
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            snapshot = nil
            failed = true
        }
    }
}
