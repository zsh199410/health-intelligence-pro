import SwiftUI
import HealthCore

/// V3 Stress page (GitHub Issue #2 order: Today -> Sleep -> Recovery ->
/// Stress -> Energy -> Load -> Insights). Six states, both themes.
/// Real HealthKit data only — no fabricated values; missing data renders
/// as "—" / "暂无记录".
///
/// HealthKit has no direct stress type and Bevel's Stress Score algorithm
/// is not public, so this page is a self-developed physiological
/// load-signal estimate (see `StressCalculator`): HRV / resting heart
/// rate against the personal baseline, resting-hour heart-rate elevation,
/// and respiratory rate. It is labeled throughout as an estimate, never
/// as a stress diagnosis, an emotion judgement, or medical advice.
struct StressView: View {
    @EnvironmentObject private var health: HealthViewModel
    @StateObject private var loader: StressDataLoader

    init() {
        _loader = StateObject(wrappedValue: StressDataLoader(repository: HealthKitRepository()))
    }

    private let stressIDs = ["heartRate", "hrv", "respiratoryRate", "stepCount", "activeEnergy"]
    private let constituentIDs = ["hrv", "restingHeartRate", "heartRate", "respiratoryRate"]
    private let trendIDs = ["hrv", "restingHeartRate", "heartRate", "respiratoryRate"]

    /// Two fixed rows of two constituent cards each. Deliberately not a
    /// shared `chunked` helper: SleepView already defines one in this
    /// target, and a second identical extension would redeclare it.
    private var constituentRows: [[String]] {
        [Array(constituentIDs.prefix(2)), Array(constituentIDs.suffix(2))]
    }

    private var restingHeartRateValue: Double? {
        health.readings["restingHeartRate"]?.value
    }

    private var stressHours: [StressHourInput] {
        loader.hourlyInputs(restingHeartRate: restingHeartRateValue)
    }

    private var hasNoData: Bool {
        loader.hasPhysiologicalSamples == false
    }

    private var isStale: Bool {
        guard let last = health.lastRefreshedAt else { return false }
        return Date().timeIntervalSince(last) > 24 * 3600
    }

    private var failedIDs: [String] {
        let combined = Set(loader.failedIDs).union(
            Set(health.failedMetricIDs.filter { stressIDs.contains($0) })
        )
        return combined.sorted()
    }

    private var hrvSummary: BaselineSummary {
        BaselineAnalyzer.summarize(points: health.trends["hrv"] ?? [], now: .now)
    }

    private var restingSummary: BaselineSummary {
        BaselineAnalyzer.summarize(points: health.trends["restingHeartRate"] ?? [], now: .now)
    }

    private var hrvBaseline: Double? { hrvSummary.baseline }
    private var restingBaseline: Double? { restingSummary.baseline }

    private var estimate: StressEstimate {
        StressCalculator.estimate(
            hours: stressHours, hrvBaseline: hrvBaseline, restingBaseline: restingBaseline
        )
    }

    private var hourlyLevelByHour: [Date: StressLevel] {
        var result: [Date: StressLevel] = [:]
        for entry in StressCalculator.hourlyLevels(hours: stressHours) {
            if let level = entry.level {
                result[entry.hourStart] = level
            }
        }
        return result
    }

    private var hourInputByHour: [Date: StressHourInput] {
        Dictionary(uniqueKeysWithValues: stressHours.map { ($0.hourStart, $0) })
    }

    private var last24HourStarts: [Date] {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        guard let currentHour = calendar.date(from: components) else { return [] }
        var result: [Date] = []
        for offset in (0..<24).reversed() {
            if let hour = calendar.date(byAdding: .hour, value: -offset, to: currentHour) {
                result.append(hour)
            }
        }
        return result
    }

    private var hourFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter
    }

    private var dataSourceText: String {
        if let loaded = loader.loadedAt {
            return "数据来源：Apple 健康 · 更新于 \(ChineseDateTime.full(loaded))"
        }
        if let last = health.lastRefreshedAt {
            return "数据来源：Apple 健康 · 更新于 \(ChineseDateTime.full(last))"
        }
        return "数据来源：Apple 健康"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeading
                    stateContent
                    footer
                }
                .padding(.horizontal, HealthTheme.v3Margin)
                .padding(.bottom, 28)
            }
            .background(HealthTheme.v3Canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await health.refresh(); await loadAll() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新健康数据").disabled(health.isLoading || loader.isLoading)
                }
            }
            .refreshable { await health.refresh(); await loadAll() }
            .task { await loadAll() }
        }
    }

    private func loadAll() async {
        for id in trendIDs {
            if let metric = HealthCatalog.byID[id] {
                await health.loadTrend(for: metric, days: 30)
            }
        }
        if health.hasRequestedAccess {
            await loader.load()
        }
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("压力，是身体的信号")
                .font(HealthTheme.v3TitleFont)
                .foregroundStyle(HealthTheme.v3Ink)
            Text("最近 24 小时的已有记录")
                .font(HealthTheme.v3BodyFont)
                .foregroundStyle(HealthTheme.v3Muted)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private var stateContent: some View {
        Group {
            if loader.isLoading && hasNoData {
                V3LoadingView()
            } else if health.hasRequestedAccess == false {
                permissionCard
            } else if hasNoData && failedIDs.isEmpty {
                V3EmptyStateView(
                    title: "暂无压力相关记录",
                    detail: "佩戴手表并记录心率、HRV 后再刷新；检查健康授权设置。",
                    symbol: "wind"
                )
            } else if hasNoData {
                V3EmptyStateView(
                    title: "压力数据读取失败",
                    detail: "本次未能读取任何压力相关记录，请检查授权后下拉刷新重试。",
                    symbol: "exclamationmark.triangle.fill"
                )
            } else {
                if failedIDs.isEmpty == false {
                    V3ErrorBanner(failedCount: failedIDs.count)
                }
                if isStale {
                    V3StaleBanner(lastUpdated: health.lastRefreshedAt ?? .now)
                }
                hero
                trendSection
                constituentsSection
                baselineSection
                activityNoteCard
                disclaimerCard
            }
        }
    }

    private var permissionCard: some View {
        V3Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("连接 Apple 健康", systemImage: "heart.text.clipboard")
                    .font(HealthTheme.v3SectionFont)
                    .foregroundStyle(HealthTheme.v3Ink)
                Text("授权后只读 HRV、心率、呼吸与活动数据，用于估算生理负荷信号。未授权、没有记录或设备不支持时，都会保持空状态，不生成测试数值。")
                    .font(HealthTheme.v3BodyFont)
                    .foregroundStyle(HealthTheme.v3Muted)
                V3PrimaryButton(
                    title: health.isLoading ? "正在请求授权" : "授权并读取数据",
                    icon: "lock.open.fill",
                    state: health.isLoading ? .loading : .idle,
                    disabled: health.isHealthAvailable == false
                ) {
                    Task { await health.connectAndRefresh(); await loadAll() }
                }
            }
        }
    }

    private var hero: some View {
        V3Hero {
            VStack(alignment: .leading, spacing: 14) {
                Label("今日生理负荷", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HealthTheme.v3Muted)
                Text(estimate.level == .insufficient ? "数据不足" : estimate.level.rawValue)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(levelColor(estimate.level))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("基于最近可用的 HRV、心率、呼吸和活动记录估算")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.v3Muted)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        summaryMetric(id: "hrv", title: "今日 HRV", unit: "毫秒", baseline: hrvBaseline)
                        summaryMetric(id: "restingHeartRate", title: "静息心率", unit: "次/分", baseline: restingBaseline)
                    }
                    VStack(spacing: 10) {
                        summaryMetric(id: "hrv", title: "今日 HRV", unit: "毫秒", baseline: hrvBaseline)
                        summaryMetric(id: "restingHeartRate", title: "静息心率", unit: "次/分", baseline: restingBaseline)
                    }
                }
                .padding(.vertical, 4)
                Text("输入覆盖 \(estimate.coveredInputs)/\(estimate.totalInputs) · 置信度：\(estimate.confidence.rawValue)")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.v3Muted)
                ForEach(estimate.drivers, id: \.self) { driver in
                    Text(driver)
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.v3Ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(dataSourceText)
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.v3Muted)
            }
        }
    }

    private func summaryMetric(id: String, title: String, unit: String, baseline: Double?) -> some View {
        let reading = health.readings[id]
        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(HealthTheme.v3Muted)
            Text(reading.map { String(format: "%.0f %@", $0.value, unit) } ?? "—")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(HealthTheme.v3Ink)
            Text(baseline.map { String(format: "个人基线 %.0f %@", $0, unit) } ?? "个人基线数据不足")
                .font(.caption)
                .foregroundStyle(HealthTheme.v3Muted)
            Text(reading.map { ChineseDateTime.full($0.recordedAt) } ?? "暂无记录")
                .font(.caption2)
                .foregroundStyle(HealthTheme.v3Muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(HealthTheme.v3SurfaceSecondary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var coverageProgress: Double {
        if estimate.totalInputs <= 0 { return 0 }
        return Double(estimate.coveredInputs) / Double(estimate.totalInputs)
    }

    private func levelColor(_ level: StressLevel) -> Color {
        switch level {
        case .low: return HealthTheme.v3RecoveryText
        case .moderate: return HealthTheme.v3EnergyText
        case .elevated: return HealthTheme.v3RiskText
        case .insufficient: return HealthTheme.v3Muted
        }
    }

    private func levelShortText(_ level: StressLevel) -> String {
        switch level {
        case .low: return "较低"
        case .moderate: return "中等"
        case .elevated: return "偏高"
        case .insufficient: return "不足"
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3SectionHeadline(title: "全天趋势", subtitle: "最近 24 小时 · 每小时生理负荷信号")
            V3Card {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 12) {
                    ForEach(last24HourStarts, id: \.self) { hourStart in
                        trendCell(hourStart: hourStart)
                    }
                }
            }
            Text("没有记录的小时留空，标注“无数据”，不补零、不连线。")
                .font(HealthTheme.v3AuxFont)
                .foregroundStyle(HealthTheme.v3Muted)
                .padding(.horizontal, 2)
        }
    }

    private func trendCell(hourStart: Date) -> some View {
        let level = hourlyLevelByHour[hourStart]
        let input = hourInputByHour[hourStart]
        let isActivityHour = input.map { $0.hasActivityData && $0.isRestingHour == false } ?? false
        return VStack(spacing: 2) {
            Text(hourFormatter.string(from: hourStart) + "时")
                .font(.caption2)
                .foregroundStyle(HealthTheme.v3Muted)
            if let level {
                Text(levelShortText(level))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor(level))
            } else {
                Text("无数据")
                    .font(.caption2)
                    .foregroundStyle(HealthTheme.v3Muted)
            }
            if isActivityHour {
                Text("活动")
                    .font(.caption2)
                    .foregroundStyle(HealthTheme.v3EnergyText)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hourFormatter.string(from: hourStart) + "时 " + (level.map { levelShortText($0) } ?? "无数据") + (isActivityHour ? " 活动" : ""))
    }

    private var constituentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3SectionHeadline(title: "构成指标", subtitle: "每项只在有真实值时显示数值与来源时间")
            VStack(spacing: 16) {
                ForEach(constituentRows, id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(row, id: \.self) { id in
                            if let metric = HealthCatalog.byID[id] {
                                MetricCard(metric: metric, reading: health.readings[id], trendPoints: health.trends[id])
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        if row.count == 1 {
                            Spacer().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var baselineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3SectionHeadline(title: "个人基线对比", subtitle: "近 30 天趋势 · 至少 7 天数据才算有效基线")
            V3Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("HRV 基线")
                            .font(HealthTheme.v3BodyFont)
                            .foregroundStyle(HealthTheme.v3Muted)
                        Spacer()
                        Text(baselineText(summary: hrvSummary, unit: "毫秒"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(HealthTheme.v3Ink)
                    }
                    HStack {
                        Text("静息心率基线")
                            .font(HealthTheme.v3BodyFont)
                            .foregroundStyle(HealthTheme.v3Muted)
                        Spacer()
                        Text(baselineText(summary: restingSummary, unit: "次/分"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(HealthTheme.v3Ink)
                    }
                    Text("基线取最近 30 天内、除当日外至少 7 个不同日期的日中位数。不足 7 天时不作基线对比，估算置信度降为中。")
                        .font(HealthTheme.v3AuxFont)
                        .foregroundStyle(HealthTheme.v3Muted)
                }
            }
        }
    }

    private func baselineText(summary: BaselineSummary, unit: String) -> String {
        guard let baseline = summary.baseline else { return "—（数据不足 7 天）" }
        let formatted = String(format: "%.1f", baseline)
        if let change = summary.percentageChange {
            let percent = Int((change * 100).rounded())
            let sign = change > 0 ? "+" : ""
            return "\(formatted) \(unit)（当日 \(sign)\(percent)%）"
        }
        return "\(formatted) \(unit)"
    }

    private var activityNoteCard: some View {
        V3Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("活动与静息的区分", systemImage: "figure.walk")
                    .font(HealthTheme.v3SectionFont)
                    .foregroundStyle(HealthTheme.v3Ink)
                Text("只有该小时的步数和活动能量均有记录，才判断活动状态。静息时段指步数少于 100 步且活动能量少于 20 千卡。静息时段心率高于静息心率 15 次/分以上时计入负荷信号；活动时段的心率升高由活动可解释，不计入负荷信号，并在趋势中标注“活动”。")
                    .font(HealthTheme.v3BodyFont)
                    .foregroundStyle(HealthTheme.v3Muted)
            }
        }
    }

    private var disclaimerCard: some View {
        V3Card {
            Label("仅为生理信号估算，不是压力诊断、情绪判断或医疗建议。出现持续不适请咨询专业人员。", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(HealthTheme.v3Muted)
        }
    }

    private var footer: some View {
        Text("本产品用于健康记录与趋势理解，不提供急救监护或疾病诊断。出现胸痛、严重呼吸困难等症状，应立即寻求急救。")
            .font(.footnote)
            .foregroundStyle(HealthTheme.v3Muted)
    }
}
