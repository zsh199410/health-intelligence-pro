import SwiftUI
import HealthCore

/// A recent HealthKit sample, never presented as a continuous sensor stream.
/// The status is recalculated each minute so a card cannot remain "recent"
/// after its sample ages while the page stays open.
struct LatestHeartRateCard: View {
    let reading: MetricReading?
    let readFailed: Bool
    let accessRequested: Bool
    let lastCheckedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HealthCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.headline)
                            .foregroundStyle(HealthTheme.v3RiskText)
                            .frame(width: 42, height: 42)
                            .background(HealthTheme.v3Risk.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近测得心率")
                                .font(.headline)
                                .foregroundStyle(HealthTheme.v3Ink)
                            Text("Apple 健康中的最新记录")
                                .font(.subheadline)
                                .foregroundStyle(HealthTheme.v3Muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HealthTheme.v3Muted)
                            .accessibilityHidden(true)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(reading.map { String(Int($0.value.rounded())) } ?? "—")
                            .font(.largeTitle.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(HealthTheme.v3Ink)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: reading?.value)
                        if reading != nil {
                            Text("次/分")
                                .font(.subheadline)
                                .foregroundStyle(HealthTheme.v3Muted)
                        }
                    }

                    Text(status(at: timeline.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(at: timeline.date))
                    if let reading {
                        Text("测量于 \(ChineseDateTime.full(reading.recordedAt))")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.v3Muted)
                        Text("来源：\(reading.source.isEmpty ? "未知设备" : reading.source)")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.v3Muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(accessRequested
                             ? "暂未读取到心率；请检查手表佩戴与健康访问设置。"
                             : "连接 Apple 健康后可查看最新心率记录。")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.v3Muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let lastCheckedAt {
                        Text("本机检查于 \(ChineseDateTime.full(lastCheckedAt))")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.v3Muted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(at: timeline.date))
        }
    }

    private func status(at now: Date) -> String {
        if readFailed { return "本次读取失败" }
        guard let reading else { return "暂无记录" }
        switch FreshnessEvaluator.evaluate(recordedAt: reading.recordedAt, now: now, acceptableAge: 10 * 60) {
        case .recent: return "近 10 分钟内测得"
        case .old: return "较早的测量记录"
        case .future: return "记录时间异常"
        case .noData: return "暂无记录"
        }
    }

    private func statusColor(at now: Date) -> Color {
        if readFailed { return HealthTheme.v3RiskText }
        guard let reading else { return HealthTheme.v3Muted }
        switch FreshnessEvaluator.evaluate(recordedAt: reading.recordedAt, now: now, acceptableAge: 10 * 60) {
        case .recent: return HealthTheme.v3RecoveryText
        case .old, .future: return HealthTheme.v3EnergyText
        case .noData: return HealthTheme.v3Muted
        }
    }

    private func accessibilityText(at now: Date) -> String {
        guard let reading else { return "最近测得心率，\(status(at: now))" }
        let source = reading.source.isEmpty ? "未知设备" : reading.source
        let checked = lastCheckedAt.map { "本机检查于 \(ChineseDateTime.full($0))。" } ?? ""
        return "最近测得心率，\(Int(reading.value.rounded())) 次每分钟。\(status(at: now))。测量于 \(ChineseDateTime.full(reading.recordedAt))。来源：\(source)。\(checked)"
    }
}

/// Only describes motion from this iPhone while the person has explicitly
/// started observation. HealthKit's cross-device daily totals stay separate.
struct LiveMotionCard: View {
    @ObservedObject var motion: LiveMotionStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.walk")
                            .font(.headline)
                            .foregroundStyle(HealthTheme.v3LoadText)
                            .frame(width: 42, height: 42)
                            .background(HealthTheme.v3Load.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("当前活动")
                                .font(.headline)
                                .foregroundStyle(HealthTheme.v3Ink)
                            Text("仅来自这台 iPhone")
                                .font(.subheadline)
                                .foregroundStyle(HealthTheme.v3Muted)
                        }
                    }

                    Text(activityLabel(at: timeline.date))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HealthTheme.v3Ink)
                    if let steps = motion.stepsToday {
                        Text("本机今日步数：\(steps.formatted()) 步")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.v3Muted)
                    }
                    if let activityObservedAt = motion.activityObservedAt {
                        Text("活动最近识别于 \(ChineseDateTime.full(activityObservedAt))")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.v3Muted)
                    }
                    if let stepsMeasuredAt = motion.stepsMeasuredAt {
                        Text("本机步数统计至 \(ChineseDateTime.full(stepsMeasuredAt))")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.v3Muted)
                    }
                    if let error = motion.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.v3RiskText)
                    } else {
                        Text("仅在首页打开期间观察；与 Apple 健康的跨设备总步数分开显示。")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.v3Muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        motion.isTracking ? motion.stop() : motion.start()
                    } label: {
                        Text(motion.isTracking ? "停止观察" : "开始观察")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(HealthTheme.v4Accent)
                    .disabled(!motion.isTracking && !motion.isAvailable)
                    .accessibilityHint("开启后会请求运动与健身访问权限")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func activityLabel(at now: Date) -> String {
        guard motion.isAvailable else { return "此设备不支持活动识别" }
        guard motion.isTracking else { return "尚未开始观察" }
        guard let activity = motion.activityName,
              let activityObservedAt = motion.activityObservedAt else {
            return motion.stepsToday == nil ? "正在等待本机运动数据" : "已读取本机步数"
        }
        if now.timeIntervalSince(activityObservedAt) > 2 * 60 {
            return "上次识别：\(activity.replacingOccurrences(of: "中", with: ""))"
        }
        return activity
    }
}

/// The time shown here is the actual record time, never the query time.
struct OlderSamplesNotice: View {
    let recordedAt: Date
    let context: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(HealthTheme.v3EnergyText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("最近可用记录较早")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HealthTheme.v3Ink)
                Text("\(context)最近样本测量于 \(ChineseDateTime.full(recordedAt))。刷新页面不会产生新的测量。")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.v3Muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HealthTheme.v3Energy.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// Keeps the freshness warning accurate even when a page remains open.
struct StaleSamplesNotice: View {
    let recordedAt: Date
    let context: String
    let maximumAge: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            if timeline.date.timeIntervalSince(recordedAt) > maximumAge {
                OlderSamplesNotice(recordedAt: recordedAt, context: context)
            }
        }
    }
}
