import SwiftUI
import HealthCore

struct TodayView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var health: HealthViewModel
    @AppStorage("themePreference") private var themePreference: AppThemePreference = .system
    @State private var showSettings = false
    /// Set by RootView so the Sleep module card can switch to the Sleep tab.
    var onOpenSleepTab: () -> Void = {}

    private let primary = ["restingHeartRate", "hrv", "oxygenSaturation", "respiratoryRate"]

    private var resolvedColorScheme: ColorScheme? {
        ThemeResolver.resolvedColorScheme(preference: themePreference)
    }

    private var hasNoData: Bool { health.readings.isEmpty && health.sleep == nil }

    private var isStale: Bool {
        guard let last = health.lastRefreshedAt else { return false }
        return Date().timeIntervalSince(last) > 24 * 3600
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeading
                    if !hasNoData { hero }
                    stateContent
                    footer
                }
                .padding(.horizontal, HealthTheme.v3Margin)
                .padding(.bottom, 28)
            }
            .background(HealthTheme.v3Canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await health.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新健康数据").disabled(health.isLoading)
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置与隐私")
                }
            }
            .sheet(isPresented: $showSettings) {
                // Sheets do not reliably inherit the TabView's color scheme
                // (same as the onboarding sheet in RootView), so apply it here.
                SettingsView()
                    .preferredColorScheme(resolvedColorScheme)
            }
            .refreshable { await health.refresh() }
            .task {
                if health.lastRefreshedAt == nil && UserDefaults.standard.bool(forKey: "onboardingComplete") {
                    await health.refresh()
                }
            }
        }
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("读懂身体的每一天")
                .font(.largeTitle.bold())
                .foregroundStyle(HealthTheme.v3Ink)
            Text(Date.now.formatted(.dateTime.year().month(.wide).day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                .font(.subheadline)
                .foregroundStyle(HealthTheme.v3Muted)
        }
        .padding(.top, 16)
    }

    private var hero: some View {
        V3Hero {
            VStack(alignment: .leading, spacing: 16) {
                if let sample = latestVital, let metric = HealthCatalog.byID[sample.id] {
                    Label("最近一次生命体征记录", systemImage: "waveform.path.ecg")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(HealthTheme.v3BrandText)
                    Text(metric.name).font(.headline)
                    Text("\(metric.display(sample.value)) \(sample.unit)")
                        .font(.largeTitle.bold()).monospacedDigit()
                    Text("\(sample.recordedAt.formatted(sampleDateStyle)) · \(sample.source)")
                        .font(.subheadline).foregroundStyle(HealthTheme.v3Muted)
                    let status = freshness(of: sample.recordedAt)
                    Text(status.0).font(.footnote.weight(.semibold)).foregroundStyle(status.1)
                } else if let window = health.sleepWindow, health.sleep != nil {
                    Label("最近一次睡眠", systemImage: "moon.zzz.fill")
                        .font(.headline).foregroundStyle(HealthTheme.v3SleepText)
                    Text(sleepDurationText).font(.largeTitle.bold()).monospacedDigit()
                    Text("\(window.lowerBound.formatted(sampleDateStyle)) 至 \(window.upperBound.formatted(sampleDateStyle))")
                        .font(.subheadline).foregroundStyle(HealthTheme.v3Muted)
                } else {
                    Text("健康记录概览").font(.title2.bold())
                }
                Divider()
                Text("已读取 \(health.readings.count) 项指标 · \(modulesWithData)/5 个模块有记录")
                    .font(.subheadline).foregroundStyle(HealthTheme.v3Muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sampleDateStyle: Date.FormatStyle {
        .dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN"))
    }

    private var latestVital: MetricReading? {
        (["heartRate"] + primary).compactMap { health.readings[$0] }.max { $0.recordedAt < $1.recordedAt }
    }

    @ViewBuilder
    private var stateContent: some View {
        if health.isLoading && hasNoData {
            V3LoadingView()
        } else if hasNoData && !health.hasRequestedAccess && health.failedMetricIDs.isEmpty {
            permissionCard
        } else if hasNoData && health.failedMetricIDs.isEmpty {
            V3EmptyStateView(
                title: "暂无健康记录",
                detail: "授权后将显示真实记录。没有记录时不会填充模拟健康数据。"
            )
        } else if hasNoData {
            V3EmptyStateView(
                title: "健康数据读取失败",
                detail: "本次未能读取任何指标，请检查授权后下拉刷新重试。",
                symbol: "exclamationmark.triangle.fill"
            )
        } else {
            if health.failedMetricIDs.isEmpty == false {
                V3ErrorBanner(failedCount: health.failedMetricIDs.count)
            }
            if isStale {
                V3StaleBanner(lastUpdated: health.lastRefreshedAt ?? .now)
            }
            vitalsSection
            modulesSection
            insightsSection
        }
    }

    private var permissionCard: some View {
        V3Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("连接 Apple 健康", systemImage: "heart.text.clipboard")
                    .font(HealthTheme.v3SectionFont)
                    .foregroundStyle(HealthTheme.v3Ink)
                Text("授权后读取真实健康记录。未授权、没有记录或设备不支持时，都会保持空状态，不生成测试数值。")
                    .font(HealthTheme.v3BodyFont)
                    .foregroundStyle(HealthTheme.v3Muted)
                V3PrimaryButton(
                    title: health.isLoading ? "正在请求授权" : "授权并读取数据",
                    icon: "lock.open.fill",
                    state: health.isLoading ? .loading : .idle,
                    disabled: health.isHealthAvailable == false
                ) {
                    Task { await health.connectAndRefresh() }
                }
            }
        }
    }

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3SectionHeadline(title: "今日模块", subtitle: "点按查看详情；圆环为数据覆盖，不是健康评分")
            ForEach(modules) { module in
                if module.id == .sleep {
                    Button(action: onOpenSleepTab) {
                        ModuleCardContent(module: module)
                    }
                    .buttonStyle(.plain)
                } else if let metricID = module.primaryMetricID, let metric = HealthCatalog.byID[metricID] {
                    NavigationLink {
                        MetricDetailView(metric: metric)
                    } label: {
                        ModuleCardContent(module: module)
                    }
                    .buttonStyle(.plain)
                } else {
                    ModuleCardContent(module: module)
                }
            }
        }
    }

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3SectionHeadline(title: "核心生命体征", subtitle: "数据直接来自 Apple 健康")
            if typeSize.isAccessibilitySize {
                ForEach(primary, id: \.self) { id in vitalTile(id: id) }
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow { vitalTile(id: primary[0]); vitalTile(id: primary[1]) }
                    GridRow { vitalTile(id: primary[2]); vitalTile(id: primary[3]) }
                }
            }
        }
    }

    private func vitalTile(id: String) -> some View {
        Group {
            if let metric = HealthCatalog.byID[id] {
                NavigationLink {
                    MetricDetailView(metric: metric)
                } label: {
                    MetricCard(metric: metric, reading: health.readings[id])
                }
                .buttonStyle(.plain)
                // Stable identifier for UI tests: the card's
                // accessibility label is not the metric name
                // (V3Card exposes children separately), so the
                // screenshot test finds the tile by this id.
                .accessibilityIdentifier("metric-tile-\(id)")
                // Explicit button label, so the tile is also
                // findable by its metric name ("静息心率").
                .accessibilityLabel(metric.name)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3SectionHeadline(title: "今日洞察", subtitle: "可追溯的本地解释，不使用虚构评分")
            ForEach(health.insights) { insight in
                InsightCard(insight: insight)
            }
        }
    }

    private var footer: some View {
        Text("本产品用于健康记录与趋势理解，不提供急救监护或疾病诊断。出现胸痛、严重呼吸困难等症状，应立即寻求急救。")
            .font(.footnote)
            .foregroundStyle(HealthTheme.v3Muted)
    }

    // MARK: - Module data (real readings only, no fabricated scores)

    private var modulesWithData: Int { modules.filter { $0.presentCount > 0 }.count }

    private var sleepDurationText: String {
        guard let sleep = health.sleep, sleep.totalAsleepMinutes > 0 else { return "—" }
        return "\(sleep.totalAsleepMinutes / 60)小时 \(sleep.totalAsleepMinutes % 60)分"
    }

    private func freshness(of recordedAt: Date?) -> (String, Color) {
        guard let recordedAt else { return ("暂无记录", HealthTheme.v3Muted) }
        switch FreshnessEvaluator.evaluate(recordedAt: recordedAt, now: .now, acceptableAge: 24 * 3600) {
        case .recent: return ("近期记录", HealthTheme.v3RecoveryText)
        case .old: return ("记录较旧", HealthTheme.v3EnergyText)
        case .future: return ("时间异常", HealthTheme.v3EnergyText)
        case .noData: return ("暂无记录", HealthTheme.v3Muted)
        }
    }

    private func levelLine(present: Int, total: Int, primaryRecordedAt: Date?) -> (String, Color) {
        if present == 0 { return ("暂无记录", HealthTheme.v3Muted) }
        if present < total {
            return ("部分记录 · \(present)/\(total) 项指标", HealthTheme.v3EnergyText)
        }
        let (fresh, color) = freshness(of: primaryRecordedAt)
        return ("\(fresh) · \(present)/\(total) 项指标", color)
    }

    private func displayValue(_ id: String) -> (String, String) {
        guard let metric = HealthCatalog.byID[id], let reading = health.readings[id] else { return ("—", "") }
        return (metric.display(reading.value), metric.unitText)
    }

    private func supportingValue(_ id: String, label: String) -> String {
        guard let metric = HealthCatalog.byID[id], let reading = health.readings[id] else { return "" }
        return "\(label) \(metric.display(reading.value)) \(metric.unitText)"
    }

    private var modules: [TodayModule] {
        let readings = health.readings
        let sleep = health.sleep
        let sleepMinutes = sleep?.totalAsleepMinutes ?? 0
        let sleepPresent = sleepMinutes > 0 ? 1 : 0

        let sleepSupporting: String
        if let window = health.sleepWindow {
            sleepSupporting = "\(window.lowerBound.formatted(date: .omitted, time: .shortened)) – \(window.upperBound.formatted(date: .omitted, time: .shortened))"
        } else if sleepMinutes > 0, let sleep {
            sleepSupporting = "深睡 \(sleep.minutesByStage[.deep] ?? 0)分 · REM \(sleep.minutesByStage[.rem] ?? 0)分"
        } else {
            sleepSupporting = ""
        }
        let sleepLevel: (String, Color)
        if sleepPresent == 0 {
            sleepLevel = ("暂无记录", HealthTheme.v3Muted)
        } else if let window = health.sleepWindow {
            let (fresh, color) = freshness(of: window.upperBound)
            sleepLevel = ("\(fresh) · 1/1 项指标", color)
        } else {
            sleepLevel = ("已记录 · 1/1 项指标", HealthTheme.v3RecoveryText)
        }
        let sleepModule = TodayModule(
            id: .sleep, title: "睡眠", icon: "moon.zzz.fill",
            color: HealthTheme.v3Sleep, textColor: HealthTheme.v3SleepText,
            primaryMetricID: nil,
            primaryValue: sleepDurationText, primaryUnit: "",
            supportingLine: sleepSupporting,
            levelLine: sleepLevel.0, levelColor: sleepLevel.1,
            presentCount: sleepPresent, totalCount: 1
        )

        let hrv = readings["hrv"]
        let rhr = readings["restingHeartRate"]
        let recoveryPresent = [hrv, rhr].compactMap { $0 }.count
        let (hrvValue, hrvUnit) = displayValue("hrv")
        let recoveryLevel = levelLine(present: recoveryPresent, total: 2, primaryRecordedAt: hrv?.recordedAt)
        let recoveryModule = TodayModule(
            id: .recovery, title: "恢复", icon: "waveform.path.ecg",
            color: HealthTheme.v3Recovery, textColor: HealthTheme.v3RecoveryText,
            primaryMetricID: "hrv",
            primaryValue: hrvValue, primaryUnit: hrvUnit,
            supportingLine: supportingValue("restingHeartRate", label: "静息心率"),
            levelLine: recoveryLevel.0, levelColor: recoveryLevel.1,
            presentCount: recoveryPresent, totalCount: 2
        )

        let rr = readings["respiratoryRate"]
        let stressPresent = [hrv, rr].compactMap { $0 }.count
        let (rrValue, rrUnit) = displayValue("respiratoryRate")
        let stressLevel = levelLine(present: stressPresent, total: 2, primaryRecordedAt: rr?.recordedAt)
        let stressModule = TodayModule(
            id: .stress, title: "压力", icon: "wind",
            color: HealthTheme.v3Stress, textColor: HealthTheme.v3StressText,
            primaryMetricID: "respiratoryRate",
            primaryValue: rrValue, primaryUnit: rrUnit,
            supportingLine: supportingValue("hrv", label: "HRV"),
            levelLine: stressLevel.0, levelColor: stressLevel.1,
            presentCount: stressPresent, totalCount: 2
        )

        let active = readings["activeEnergy"]
        let basal = readings["basalEnergy"]
        let steps = readings["stepCount"]
        let energyPresent = [active, basal, steps].compactMap { $0 }.count
        let (activeValue, activeUnit) = displayValue("activeEnergy")
        let basalSupporting = supportingValue("basalEnergy", label: "静息能量")
        let energySupporting: String
        if basalSupporting.isEmpty {
            energySupporting = supportingValue("stepCount", label: "步数")
        } else {
            energySupporting = basalSupporting
        }
        let energyLevel = levelLine(present: energyPresent, total: 3, primaryRecordedAt: active?.recordedAt)
        let energyModule = TodayModule(
            id: .energy, title: "身体能量", icon: "flame.fill",
            color: HealthTheme.v3Energy, textColor: HealthTheme.v3EnergyText,
            primaryMetricID: "activeEnergy",
            primaryValue: activeValue, primaryUnit: activeUnit,
            supportingLine: energySupporting,
            levelLine: energyLevel.0, levelColor: energyLevel.1,
            presentCount: energyPresent, totalCount: 3
        )

        let walkHR = readings["walkingHeartRateAverage"]
        let vo2 = readings["vo2Max"]
        let loadPresent = [active, steps, walkHR, vo2].compactMap { $0 }.count
        let (stepsValue, stepsUnit) = displayValue("stepCount")
        let loadLevel = levelLine(present: loadPresent, total: 4, primaryRecordedAt: steps?.recordedAt)
        let loadModule = TodayModule(
            id: .load, title: "运动负荷", icon: "figure.walk",
            color: HealthTheme.v3Load, textColor: HealthTheme.v3LoadText,
            primaryMetricID: "stepCount",
            primaryValue: stepsValue, primaryUnit: stepsUnit,
            supportingLine: supportingValue("activeEnergy", label: "活动能量"),
            levelLine: loadLevel.0, levelColor: loadLevel.1,
            presentCount: loadPresent, totalCount: 4
        )

        return [sleepModule, recoveryModule, stressModule, energyModule, loadModule]
    }
}
