import SwiftUI
import HealthCore

/// V3 shared components for the Home page (GitHub Issue #2).
/// Only the Home page uses these for now; the other screens keep the V2
/// components in Theme.swift until their own V3 pass.
/// Rings show DATA COVERAGE, never a health score. No component here
/// fabricates a value: missing data renders as "—" / "暂无记录".

struct V3Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(HealthTheme.v3Card, in: RoundedRectangle(cornerRadius: HealthTheme.v3CardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HealthTheme.v3CardRadius, style: .continuous)
                    .strokeBorder(HealthTheme.v3Line.opacity(0.7), lineWidth: 0.7)
            )
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06), radius: 14, x: 0, y: 4)
            .accessibilityElement(children: .contain)
    }
}

struct V3Hero<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(heroBackground)
            .clipShape(RoundedRectangle(cornerRadius: HealthTheme.v3HeroRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HealthTheme.v3HeroRadius, style: .continuous)
                    .strokeBorder(HealthTheme.v3Line.opacity(0.5), lineWidth: 0.7)
            )
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06), radius: 14, x: 0, y: 4)
            .accessibilityElement(children: .contain)
    }
    @ViewBuilder
    private var heroBackground: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [HealthTheme.v3Card, HealthTheme.v3SurfaceSecondary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else {
            HealthTheme.v3Card
        }
    }
}

struct V3Pill: View {
    let title: String
    let icon: String
    var tint: Color = HealthTheme.v3BrandText
    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(tint)
            .background(tint.opacity(0.11), in: Capsule())
            .accessibilityLabel(title)
    }
}

struct V3SectionHeadline: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(HealthTheme.v3SectionFont)
                .foregroundStyle(HealthTheme.v3Ink)
            if let subtitle {
                Text(subtitle)
                    .font(HealthTheme.v3AuxFont)
                    .foregroundStyle(HealthTheme.v3Muted)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A module's data for the Home page. The ring shows data coverage
/// (inputs present / inputs expected), never a health score.
struct TodayModule: Identifiable {
    enum Kind { case sleep, recovery, stress, energy, load }
    let id: Kind
    let title: String
    let icon: String
    let color: Color
    let textColor: Color
    /// Primary metric id for the detail page; nil for Sleep (opens the Sleep tab).
    let primaryMetricID: String?
    let primaryValue: String
    let primaryUnit: String
    let supportingLine: String
    /// e.g. "近期记录 · 2/2 项指标" / "部分记录 · 1/2 项指标" / "暂无记录".
    let levelLine: String
    let levelColor: Color
    let presentCount: Int
    let totalCount: Int
    var coverage: Double {
        if totalCount <= 0 { return 0 }
        return Double(presentCount) / Double(totalCount)
    }
    var coverageText: String { "\(presentCount)/\(totalCount)" }
}

/// Coverage ring: the fill is the fraction of the module's expected data
/// inputs that are present. Center shows the fraction (e.g. "2/2"), not a
/// score. Static geometry; never animated as a heartbeat or ECG trace.
struct StatusRing: View {
    let progress: Double
    let color: Color
    let center: String
    var caption: String? = nil
    var size: CGFloat = 76
    var lineWidth: CGFloat = 7
    var body: some View {
        ZStack {
            Circle()
                .stroke(HealthTheme.v3Line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(center)
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .foregroundStyle(HealthTheme.v3Ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HealthTheme.v3Muted)
                        .lineLimit(1)
                }
            }
            .padding(lineWidth + 4)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("数据覆盖 \(center)")
    }
    private var clampedProgress: Double {
        if progress < 0 { return 0 }
        if progress > 1 { return 1 }
        return progress
    }
}

/// The tappable module card body (ring + value + level + coverage).
/// The caller wraps it in a NavigationLink (metric detail) or a Button
/// (Sleep tab switch); the content is identical either way.
struct ModuleCardContent: View {
    @Environment(\.colorScheme) private var colorScheme
    let module: TodayModule
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            StatusRing(
                progress: module.coverage, color: module.color,
                center: module.coverageText, caption: "项指标", size: 76
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: module.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(module.textColor)
                        .accessibilityHidden(true)
                    Text(module.title)
                        .font(HealthTheme.v3SectionFont)
                        .foregroundStyle(HealthTheme.v3Ink)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(module.primaryValue)
                        .font(HealthTheme.v3TitleFont)
                        .foregroundStyle(HealthTheme.v3Ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if module.primaryUnit.isEmpty == false {
                        Text(module.primaryUnit)
                            .font(HealthTheme.v3AuxFont)
                            .foregroundStyle(HealthTheme.v3Muted)
                            .lineLimit(1)
                    }
                }
                if module.supportingLine.isEmpty == false {
                    Text(module.supportingLine)
                        .font(HealthTheme.v3AuxFont)
                        .foregroundStyle(HealthTheme.v3Muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(module.levelLine)
                    .font(HealthTheme.v3AuxFont)
                    .foregroundStyle(module.levelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HealthTheme.v3Muted)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(HealthTheme.v3Card, in: RoundedRectangle(cornerRadius: HealthTheme.v3CardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HealthTheme.v3CardRadius, style: .continuous)
                .strokeBorder(HealthTheme.v3Line.opacity(0.7), lineWidth: 0.7)
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06), radius: 14, x: 0, y: 4)
    }
}

/// One metric with its value, unit, recorded time and source, plus a
/// personal-baseline line when trend data is already available. The Home
/// page does not load trends, so the baseline line is omitted there; the
/// component still renders metric/unit/time/source honestly.
struct MetricCard: View {
    let metric: HealthMetric
    let reading: MetricReading?
    var trendPoints: [TrendPoint]? = nil
    var emptyText = "暂无记录 · 可检查授权"
    var body: some View {
        V3Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: metric.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconTint)
                        .frame(width: 34, height: 34)
                        .background(baseTint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HealthTheme.v3Muted)
                        .accessibilityHidden(true)
                }
                Text(metric.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HealthTheme.v3Muted)
                    .lineLimit(2)
                    .frame(minHeight: 32, alignment: .top)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(reading.map { metric.display($0.value) } ?? "—")
                        .font(HealthTheme.v3TitleFont)
                        .foregroundStyle(HealthTheme.v3Ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    if reading != nil {
                        Text(metric.unitText)
                            .font(.caption2)
                            .foregroundStyle(HealthTheme.v3Muted)
                            .lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.map { $0.recordedAt.formatted(date: .abbreviated, time: .shortened) } ?? emptyText)
                        .font(.caption2)
                        .foregroundStyle(HealthTheme.v3Muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(reading.map { $0.source.isEmpty ? "来源未知" : $0.source } ?? "来源 —")
                        .font(.caption2)
                        .foregroundStyle(HealthTheme.v3Muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let baselineLine {
                    Text(baselineLine)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(HealthTheme.v3Muted)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var baselineLine: String? {
        guard let points = trendPoints, points.isEmpty == false else { return nil }
        let summary = BaselineAnalyzer.summarize(points: points, now: .now)
        if summary.direction == .insufficient { return nil }
        return summary.direction.rawValue
    }
    /// Icon glyph color: the darkened text variant, for legibility on the chip.
    private var iconTint: Color {
        switch metric.group {
        case .heart: return HealthTheme.v3RiskText
        case .breathing: return HealthTheme.v3SleepText
        case .body: return HealthTheme.v3RecoveryText
        case .mobility: return HealthTheme.v3EnergyText
        case .environment: return HealthTheme.v3StressText
        }
    }
    /// Chip fill color: the base semantic at 10% opacity.
    private var baseTint: Color {
        switch metric.group {
        case .heart: return HealthTheme.v3Risk
        case .breathing: return HealthTheme.v3Sleep
        case .body: return HealthTheme.v3Recovery
        case .mobility: return HealthTheme.v3Energy
        case .environment: return HealthTheme.v3Stress
        }
    }
}

/// One insight: title, explanation, and the evidence it rests on.
/// The evidence line names the supporting metrics; when there are none
/// (the "not enough records" insight) the line is omitted.
struct InsightCard: View {
    let insight: HealthInsight
    var body: some View {
        V3Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(HealthTheme.v3BrandText)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.title)
                        .font(.headline)
                        .foregroundStyle(HealthTheme.v3Ink)
                    Text(insight.body)
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.v3Muted)
                    if evidenceNames.isEmpty == false {
                        Text("依据：" + evidenceNames.joined(separator: "、"))
                            .font(HealthTheme.v3AuxFont)
                            .foregroundStyle(HealthTheme.v3Muted)
                    }
                }
            }
        }
    }
    private var evidenceNames: [String] {
        insight.supportingMetricIDs.compactMap { id in
            if id == "sleep" { return "睡眠" }
            return HealthCatalog.byID[id]?.name
        }
    }
}

/// V3 primary button: 48pt, 16pt radius, brand background.
/// The background is the semantic TEXT color (darkened in light mode) and
/// the label is the canvas color (near-white in light, near-black in dark),
/// so the label stays >= 4.5:1 in light mode and >= 3:1 (large text) in
/// dark mode in every state. Reduce Motion disables the press scale.
struct V3PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var state: PrimaryButtonState = .idle
    var disabled: Bool = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if state == .loading {
                    ProgressView().tint(HealthTheme.v3Canvas)
                } else if state == .success {
                    Image(systemName: "checkmark.circle.fill")
                } else if state == .failure {
                    Image(systemName: "exclamationmark.circle.fill")
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(V3PrimaryButtonStyle(state: state))
        .disabled(disabled || state == .loading)
        .accessibilityLabel(title)
    }
}

struct V3PrimaryButtonStyle: ButtonStyle {
    var state: PrimaryButtonState = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: HealthTheme.v3ButtonHeight)
            .padding(.horizontal, 16)
            .foregroundStyle(HealthTheme.v3Canvas)
            .background(background, in: RoundedRectangle(cornerRadius: HealthTheme.v3ButtonRadius, style: .continuous))
            .scaleEffect(configuration.isPressed && reduceMotion == false ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
    private var background: Color {
        if isEnabled == false { return HealthTheme.v3Muted }
        switch state {
        case .success: return HealthTheme.v3RecoveryText
        case .failure: return HealthTheme.v3RiskText
        default: return HealthTheme.v3BrandText
        }
    }
}

struct V3LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(HealthTheme.v3BrandText)
            Text("正在读取健康数据…")
                .font(.subheadline)
                .foregroundStyle(HealthTheme.v3Muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在读取健康数据")
    }
}

struct V3EmptyStateView: View {
    let title: String
    let detail: String
    var symbol = "waveform.path.ecg"
    var body: some View {
        V3Card {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(HealthTheme.v3BrandText)
                    .frame(width: 60, height: 60)
                    .background(HealthTheme.v3Brand.opacity(0.08), in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(HealthTheme.v3Ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.v3Muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

/// Partial read failure: shown as a banner above the content that did
/// load. A thrown HealthKit query is a read error; empty data and a
/// denied read look identical by HealthKit design and are NOT reported here.
struct V3ErrorBanner: View {
    let failedCount: Int
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HealthTheme.v3RiskText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("部分指标读取失败（\(failedCount) 项）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HealthTheme.v3Ink)
                Text("其余数据正常显示，可下拉刷新重试。")
                    .font(HealthTheme.v3AuxFont)
                    .foregroundStyle(HealthTheme.v3Muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(HealthTheme.v3Risk.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Sleep stage timeline: a horizontal bar of the latest sleep session,
/// each segment colored by stage and sized by its duration, with bedtime
/// and wake time on the axis and a per-stage minutes legend below.
/// Segments come from `SleepCalculator.segments` (deduplicated, same
/// precedence as the summary), so the bar and the legend always agree.
/// Decorative bar only — the legend carries the same minutes as text,
/// so VoiceOver skips the bar.
struct SleepStageTimeline: View {
    let segments: [SleepInterval]
    let window: ClosedRange<Date>
    let summary: SleepSummary
    private var stages: [(SleepStage, Color)] {
        [(.deep, HealthTheme.stageColor(.deep)), (.core, HealthTheme.stageColor(.core)),
         (.rem, HealthTheme.stageColor(.rem)), (.unspecified, HealthTheme.stageColor(.unspecified)),
         (.awake, HealthTheme.stageColor(.awake))]
    }
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                let runs = SleepTimelineLayout.runs(
                    segments: segments, window: window, width: Double(geometry.size.width)
                )
                ZStack(alignment: .leading) {
                    // Neutral track makes missing samples visibly unrecorded,
                    // not awake. All runs share one absolute-time coordinate.
                    Capsule()
                        .fill(HealthTheme.v3Line.opacity(0.35))
                    ForEach(Array(runs.enumerated()), id: \.offset) { item in
                        if let stage = item.element.stage {
                            Rectangle()
                                .fill(HealthTheme.stageColor(stage))
                                .frame(width: CGFloat(item.element.width))
                                .offset(x: CGFloat(item.element.x))
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(Capsule())
            }
            .frame(height: 15)
            .accessibilityHidden(true)
            HStack {
                Text(timeFormatter.string(from: window.lowerBound))
                Spacer()
                Text(timeFormatter.string(from: window.upperBound))
            }
            .font(HealthTheme.v3AuxFont)
            .foregroundStyle(HealthTheme.v3Muted)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("就寝 \(timeFormatter.string(from: window.lowerBound))，起床 \(timeFormatter.string(from: window.upperBound))")
            ForEach(stages, id: \.0) { entry in
                let stage = entry.0
                let tint = entry.1
                HStack {
                    Circle().fill(tint).frame(width: 9, height: 9)
                    Text(stage.rawValue).font(.subheadline).foregroundStyle(HealthTheme.v3Ink)
                    Spacer()
                    Text("\(summary.minutesByStage[stage] ?? 0) 分钟")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(HealthTheme.v3Muted)
                }
            }
        }
    }
}

/// Stale data: the last successful refresh is over 24 hours old.
struct V3StaleBanner: View {
    let lastUpdated: Date
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(HealthTheme.v3EnergyText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("数据已超过 24 小时未更新")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HealthTheme.v3Ink)
                Text("上次更新于 \(lastUpdated.formatted(date: .abbreviated, time: .shortened))，下拉刷新以获取最新记录。")
                    .font(HealthTheme.v3AuxFont)
                    .foregroundStyle(HealthTheme.v3Muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(HealthTheme.v3Energy.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
