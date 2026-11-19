import SwiftUI
import HealthCore

struct SleepView: View {
    @EnvironmentObject private var health: HealthViewModel
    private let stages: [(SleepStage, Color)] = [
        (.deep, HealthTheme.stageColor(.deep)), (.core, HealthTheme.stageColor(.core)),
        (.rem, HealthTheme.stageColor(.rem)), (.unspecified, HealthTheme.stageColor(.unspecified)), (.awake, HealthTheme.stageColor(.awake))
    ]
    /// The statistic shown is the latest sample inside the latest sleep
    /// session ("夜间最近一次"), never a daytime reading.
    private var nightSubtitle: String {
        guard let window = health.sleepWindow else { return "暂无睡眠记录" }
        let start = ChineseDateTime.full(window.lowerBound)
        let end = ChineseDateTime.full(window.upperBound)
        return "本次睡眠 \(start) – \(end) · 夜间最近一次"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("睡眠，是身体的修复时间")
                            .font(.title2.bold()).foregroundStyle(HealthTheme.ink)
                        Text("最近 36 小时的已有分期记录")
                            .font(.subheadline).foregroundStyle(HealthTheme.muted)
                    }
                    HealthCard {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                HealthPill(title: "睡眠分期", icon: "moon.stars.fill", tint: HealthTheme.indigo)
                                Spacer()
                                Text("真实记录").font(.caption2).foregroundStyle(HealthTheme.muted)
                            }
                            if let summary = health.sleep, summary.totalAsleepMinutes > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("总睡眠").font(.caption).foregroundStyle(HealthTheme.muted)
                                    Text("\(summary.totalAsleepMinutes / 60) 小时 \(summary.totalAsleepMinutes % 60) 分")
                                        .font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(HealthTheme.ink)
                                }
                                // Decorative bar: the legend below carries the
                                // same stage minutes as text, so VoiceOver skips it.
                                GeometryReader { geometry in
                                    HStack(spacing: 3) {
                                        ForEach(stages, id: \.0) { entry in
                                            let stage = entry.0
                                            let tint = entry.1
                                            let mins = summary.minutesByStage[stage] ?? 0
                                            if mins > 0 {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(tint)
                                                    .frame(width: max(1, (geometry.size.width - 12) * CGFloat(mins) / CGFloat(max(1, summary.totalAsleepMinutes + summary.minutesAwake))))
                                            }
                                        }
                                    }
                                }.frame(height: 15).accessibilityHidden(true)
                                ForEach(stages, id: \.0) { entry in
                                    let stage = entry.0
                                    let tint = entry.1
                                    HStack {
                                        Circle().fill(tint).frame(width: 9, height: 9)
                                        Text(stage.rawValue).font(.subheadline).foregroundStyle(HealthTheme.ink)
                                        Spacer()
                                        Text("\(summary.minutesByStage[stage] ?? 0) 分钟")
                                            .font(.subheadline.monospacedDigit()).foregroundStyle(HealthTheme.muted)
                                    }
                                }
                            } else {
                                EmptyHealthState(title: "尚无可读取睡眠记录", detail: "佩戴手表睡眠后再刷新；检查健康授权和睡眠专注设置。", symbol: "moon.zzz.fill")
                            }
                            Text("数据按时间区间去重；多设备冲突可能影响精度。睡眠分期不用于诊断睡眠疾病。")
                                .font(.caption2).foregroundStyle(HealthTheme.muted)
                        }
                    }
                    SectionHeadline(title: "夜间生命体征", subtitle: nightSubtitle)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(["oxygenSaturation", "respiratoryRate", "sleepingWristTemperature", "appleSleepingBreathingDisturbances"], id: \.self) { id in
                            if let metric = HealthCatalog.byID[id] {
                                NavigationLink { MetricDetailView(metric: metric) } label: {
                                    MetricTile(metric: metric, reading: health.nightReadings[id], emptyText: "无夜间记录")
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    HealthCard {
                        Label("呼吸扰动不等同于睡眠呼吸暂停诊断；具体通知以苹果健康的系统记录为准。", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(HealthTheme.muted)
                    }
                }.padding(18)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("睡眠健康")
            .refreshable { await health.refresh() }
        }
    }
}
