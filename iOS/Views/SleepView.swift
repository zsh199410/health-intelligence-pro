import SwiftUI
import HealthCore

/// V3 Sleep page (GitHub Issue #2): total duration, session window,
/// stage timeline with per-stage minutes, sleep regularity (7 days) and
/// nighttime heart rate / HRV (only when samples exist inside the sleep
/// window). Six states, both themes. Real HealthKit data only — no
/// fabricated values; missing data renders as "—" / "暂无记录".
/// Submitted for independent QA in Draft PR #4; do not merge main directly.
struct SleepView: View {
    @EnvironmentObject private var health: HealthViewModel

    private var hasNoData: Bool { health.sleep == nil }

    private var isStale: Bool {
        guard let last = health.lastRefreshedAt else { return false }
        return Date().timeIntervalSince(last) > 24 * 3600
    }

    /// Night vital metrics with a real sample inside the sleep window,
    /// in display order. Heart rate and HRV are only shown when a sample
    /// exists inside the window — never a daytime fallback.
    private var nightVitalIDs: [String] {
        ["heartRate", "hrv", "oxygenSaturation", "respiratoryRate",
         "sleepingWristTemperature", "appleSleepingBreathingDisturbances"]
            .filter { health.nightReadings[$0] != nil }
    }

    /// Sleep regularity over the last 7 days: bedtime and wake-time
    /// ranges plus the number of recorded nights. Nil when fewer than
    /// two nights are recorded (no regularity can be inferred).
    /// Bedtimes are compared as minutes after noon so a range that
    /// crosses midnight (23:30–00:15) still orders correctly.
    private var regularity: (nights: Int, bedRange: String, wakeRange: String)? {
        let sessions = health.sleepSessions7d
        guard sessions.count >= 2 else { return nil }
        func minutesAfterNoon(_ date: Date) -> Int {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let mins = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            return (mins - 12 * 60 + 1440) % 1440
        }
        func formatAfterNoon(_ mins: Int) -> String {
            let total = (mins + 12 * 60) % 1440
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
        let beds = sessions.map { minutesAfterNoon($0.lowerBound) }
        let wakes = sessions.map { minutesAfterNoon($0.upperBound) }
        guard let bedMin = beds.min(), let bedMax = beds.max(),
              let wakeMin = wakes.min(), let wakeMax = wakes.max() else { return nil }
        return (sessions.count, "\(formatAfterNoon(bedMin))–\(formatAfterNoon(bedMax))",
                "\(formatAfterNoon(wakeMin))–\(formatAfterNoon(wakeMax))")
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
                    Button { Task { await health.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新健康数据").disabled(health.isLoading)
                }
            }
            .refreshable { await health.refresh() }
        }
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("睡眠，是身体的修复时间")
                .font(HealthTheme.v3TitleFont)
                .foregroundStyle(HealthTheme.v3Ink)
            Text("最近 36 小时的已有分期记录")
                .font(HealthTheme.v3BodyFont)
                .foregroundStyle(HealthTheme.v3Muted)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private var stateContent: some View {
        Group {
            if health.sleepReadState == .loading && hasNoData {
                V3LoadingView()
            } else if health.hasRequestedAccess == false {
                permissionCard
            } else if health.sleepReadState == .empty {
                V3EmptyStateView(
                    title: "暂无睡眠记录",
                    detail: "佩戴手表睡眠后再刷新；检查健康授权和睡眠专注设置。",
                    symbol: "moon.zzz.fill"
                )
            } else if health.sleepReadState == .failed {
                V3EmptyStateView(
                    title: "睡眠数据读取失败",
                    detail: "本次未能读取任何睡眠记录，请检查授权后下拉刷新重试。",
                    symbol: "exclamationmark.triangle.fill"
                )
            } else if health.sleepReadState == .notRequested {
                V3EmptyStateView(title: "尚未读取睡眠记录", detail: "刷新以读取 Apple 健康中的睡眠数据。", symbol: "moon.zzz.fill")
            } else {
                if isStale {
                    V3StaleBanner(lastUpdated: health.lastRefreshedAt ?? .now)
                }
                hero
                timelineSection
                nightVitalsSection
                regularitySection
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
                Text("授权后读取真实睡眠记录。未授权、没有记录或设备不支持时，都会保持空状态，不生成测试数值。")
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

    private var hero: some View {
        guard let summary = health.sleep, let window = health.sleepWindow else {
            return AnyView(EmptyView())
        }
        let hours = summary.totalAsleepMinutes / 60
        let minutes = summary.totalAsleepMinutes % 60
        let start = window.lowerBound.formatted(.dateTime.month().day().hour().minute())
        let end = window.upperBound.formatted(.dateTime.month().day().hour().minute())
        return AnyView(
            V3Hero {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        V3Pill(title: "睡眠分期", icon: "moon.stars.fill", tint: HealthTheme.v3SleepText)
                        Spacer()
                        Text("真实记录")
                            .font(HealthTheme.v3AuxFont)
                            .foregroundStyle(HealthTheme.v3Muted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("总睡眠")
                            .font(HealthTheme.v3SectionFont)
                            .foregroundStyle(HealthTheme.v3Ink)
                        Spacer()
                        Text("\(hours) 小时 \(minutes) 分")
                            .font(HealthTheme.v3TitleFont)
                            .foregroundStyle(HealthTheme.v3Ink)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    Text("本次睡眠 \(start) – \(end)")
                        .font(HealthTheme.v3BodyFont)
                        .foregroundStyle(HealthTheme.v3Muted)
                    Text("其中清醒 \(summary.minutesAwake) 分钟。睡眠分期不用于诊断睡眠疾病。")
                        .font(HealthTheme.v3AuxFont)
                        .foregroundStyle(HealthTheme.v3Muted)
                }
            }
        )
    }

    private var timelineSection: some View {
        guard let summary = health.sleep, let window = health.sleepWindow else {
            return AnyView(EmptyView())
        }
        let segments = SleepCalculator.segments(health.sleepIntervals)
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                V3SectionHeadline(title: "睡眠分期", subtitle: "分期时间轴 · 每段时长")
                V3Card {
                    SleepStageTimeline(segments: segments, window: window, summary: summary)
                }
                Text("数据按时间区间去重；多设备冲突可能影响精度。")
                    .font(HealthTheme.v3AuxFont)
                    .foregroundStyle(HealthTheme.v3Muted)
                    .padding(.horizontal, 2)
            }
        )
    }

    private var nightVitalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3SectionHeadline(title: "夜间生命体征", subtitle: "本次睡眠时段内的最近一次记录")
            if nightVitalIDs.isEmpty {
                V3Card {
                    Text("本次睡眠时段内暂无夜间生命体征记录。")
                        .font(HealthTheme.v3BodyFont)
                        .foregroundStyle(HealthTheme.v3Muted)
                }
            } else {
                // Eager grid (not LazyVGrid): all tiles are in the view
                // hierarchy from the start.
                VStack(spacing: 16) {
                    ForEach(nightVitalIDs.chunked(into: 2), id: \.self) { row in
                        HStack(spacing: 16) {
                            ForEach(row, id: \.self) { id in
                                if let metric = HealthCatalog.byID[id] {
                                    NavigationLink {
                                        MetricDetailView(metric: metric)
                                    } label: {
                                        MetricCard(metric: metric, reading: health.nightReadings[id])
                                    }
                                    .buttonStyle(.plain)
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
    }

    private var regularitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            V3SectionHeadline(title: "睡眠规律", subtitle: "近 7 天就寝与起床时间")
            V3Card {
                if health.sleepRegularityFailed {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("睡眠规律读取失败", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                        Text("本次无法读取近 7 天的睡眠规律，其他睡眠记录不受影响。请刷新重试。")
                            .font(HealthTheme.v3BodyFont)
                            .foregroundStyle(HealthTheme.v3Muted)
                    }
                } else if let regularity {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("就寝时间")
                                .font(HealthTheme.v3BodyFont)
                                .foregroundStyle(HealthTheme.v3Muted)
                            Spacer()
                            Text(regularity.bedRange)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(HealthTheme.v3Ink)
                        }
                        HStack {
                            Text("起床时间")
                                .font(HealthTheme.v3BodyFont)
                                .foregroundStyle(HealthTheme.v3Muted)
                            Spacer()
                            Text(regularity.wakeRange)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(HealthTheme.v3Ink)
                        }
                        Text("近 7 天共 \(regularity.nights) 晚有睡眠记录。")
                            .font(HealthTheme.v3AuxFont)
                            .foregroundStyle(HealthTheme.v3Muted)
                    }
                } else {
                    Text("再记录一晚睡眠后，这里会显示近 7 天的就寝与起床时间范围。")
                        .font(HealthTheme.v3BodyFont)
                        .foregroundStyle(HealthTheme.v3Muted)
                }
            }
        }
    }

    private var disclaimerCard: some View {
        V3Card {
            Label("呼吸扰动不等同于睡眠呼吸暂停诊断；具体通知以苹果健康的系统记录为准。", systemImage: "info.circle")
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

private extension Array {
    /// Split into consecutive chunks of `size` (last chunk may be smaller).
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<next]))
            index = next
        }
        return result
    }
}
