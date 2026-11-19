import SwiftUI
import UIKit
import HealthCore

/// Health Intelligence Design System 2.0 — contrast-aware, dynamic and content first.
/// All colors resolve from HealthDesignTokens (HealthCore), the single source
/// of truth; this enum only adapts them to SwiftUI.
enum HealthTheme {
    private static func color(_ token: HealthDesignTokens.Token) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? token.dark : token.light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }

    static let jade = color(HealthDesignTokens.jade)
    static let teal = color(HealthDesignTokens.teal)
    static let coral = color(HealthDesignTokens.heart)
    static let indigo = color(HealthDesignTokens.sleep)
    static let sleep = color(HealthDesignTokens.sleep)
    static let amber = color(HealthDesignTokens.amber)
    static let mint = teal
    static let sky = color(HealthDesignTokens.sky)
    static let ink = color(HealthDesignTokens.ink)
    static let muted = color(HealthDesignTokens.muted)
    static let canvas = color(HealthDesignTokens.canvas)
    static let surface = color(HealthDesignTokens.surface)
    static let line = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.12) : UIColor(red: 0.839, green: 0.886, blue: 0.882, alpha: 1) })

    /// Hero cards are intentionally dark in both schemes.
    static let heroTop = Color(red: 0.035, green: 0.28, blue: 0.32)
    static let heroBottom = Color(red: 0.045, green: 0.15, blue: 0.22)

    /// Sleep stage color, shared with the Watch app through the same token.
    static func stageColor(_ stage: SleepStage) -> Color { color(HealthDesignTokens.stageToken(for: stage)) }
}

struct HealthCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(HealthTheme.surface, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).strokeBorder(HealthTheme.line.opacity(0.65), lineWidth: 0.7))
            .accessibilityElement(children: .contain)
    }
}

struct SectionHeadline: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(HealthTheme.ink)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(HealthTheme.muted) }
            }
            Spacer()
        }.padding(.horizontal, 2)
    }
}

struct HealthPill: View {
    let title: String
    let icon: String
    var tint: Color = HealthTheme.teal
    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(tint)
            .background(tint.opacity(0.11), in: Capsule())
            .accessibilityLabel(title)
    }
}

struct MetricTile: View {
    let metric: HealthMetric
    let reading: MetricReading?
    /// Text shown when there is no reading. Night tiles pass their own
    /// wording ("无夜间记录") instead of the generic authorization hint.
    var emptyText = "暂无记录 · 可检查授权"
    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: metric.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold)).foregroundStyle(HealthTheme.muted)
                }
                // Two lines of height even for one-line names, so tiles in a
                // row keep the same height (Issue #1 item 7). minHeight does
                // not cap growth under Dynamic Type.
                Text(metric.name).font(.caption.weight(.medium)).foregroundStyle(HealthTheme.muted).lineLimit(2)
                    .frame(minHeight: 32, alignment: .top)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(reading.map { metric.display($0.value) } ?? "—")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(HealthTheme.ink)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText())
                    if reading != nil {
                        Text(metric.unitText).font(.caption2).foregroundStyle(HealthTheme.muted).lineLimit(1)
                    }
                }
                // Time and source are always two lines, so a tile with no
                // reading is exactly as tall as one with a reading.
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.map { ChineseDateTime.full($0.recordedAt) } ?? emptyText)
                        .font(.caption2).foregroundStyle(HealthTheme.muted).lineLimit(1).minimumScaleFactor(0.8)
                    Text(reading.map { $0.source.isEmpty ? "来源未知" : $0.source } ?? "来源 —")
                        .font(.caption2).foregroundStyle(HealthTheme.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
    private var tint: Color {
        switch metric.group {
        case .heart: return HealthTheme.coral
        case .breathing: return HealthTheme.indigo
        case .body: return HealthTheme.teal
        case .mobility: return HealthTheme.amber
        case .environment: return HealthTheme.sky
        }
    }
}

/// Abstract decorative wave for the Today hero. Deliberately smooth and
/// sinusoidal: it must not read as an ECG trace or imply a real measurement.
/// Static geometry, never driven by a live ECG sample, and hidden from
/// assistive technologies.
struct AbstractWave: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 48
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + t * rect.width
            // Two gentle swells, no sharp spikes.
            let y = rect.midY + sin(t * .pi * 2) * rect.height * 0.18
                + sin(t * .pi * 4 + 1.2) * rect.height * 0.07
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

struct EmptyHealthState: View {
    let title: String
    let detail: String
    var symbol = "waveform.path.ecg"
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.title).foregroundStyle(HealthTheme.teal)
                .frame(width: 60, height: 60)
                .background(HealthTheme.teal.opacity(0.08), in: Circle())
            Text(title).font(.headline).foregroundStyle(HealthTheme.ink)
            Text(detail).font(.subheadline).foregroundStyle(HealthTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

/// Shared primary action: minimum 48pt target, restrained press feedback and
/// no scale animation when the user enables Reduce Motion.
struct HealthPrimaryButtonStyle: ButtonStyle {
    var state: PrimaryButtonState = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var background: Color {
        if !isEnabled { return HealthTheme.muted }
        switch state {
        case .success: return HealthTheme.teal
        case .failure: return HealthTheme.coral
        default: return HealthTheme.jade
        }
    }
}

/// Shared hero container (Issue #1 item 6): one radius (28pt, the official
/// hero token), one padding (18pt), one gradient. The Today and Report
/// heroes both use this; neither page sets its own radius or gradient.
struct HealthHero<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [HealthTheme.heroTop, HealthTheme.heroBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            content.padding(18)
        }
        .frame(minHeight: 220)
        .accessibilityElement(children: .combine)
    }
}
/// The six states a primary action can be in. Pressed is handled by the
/// style; success and failure are caller-owned (set after async work ends).
enum PrimaryButtonState: Equatable {
    case idle, loading, success, failure
}

/// Shared primary button component (Issue #1 item 5). Every primary action
/// in the app uses this component so size, states and feedback stay uniform.
struct HealthPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var state: PrimaryButtonState = .idle
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if state == .loading {
                    ProgressView().tint(.white)
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
        .buttonStyle(HealthPrimaryButtonStyle(state: state))
        .disabled(disabled || state == .loading)
        .accessibilityLabel(title)
    }
}

struct HealthSourceBadge: View {
    let source: String
    let date: Date
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.shield.fill")
            Text(source).lineLimit(1)
            Text("·")
            Text(date, style: .relative)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(HealthTheme.muted)
        .accessibilityLabel("数据来自\(source)，记录于\(ChineseDateTime.full(date))")
    }
}

// MARK: - V3 dual-theme tokens (GitHub Issue #2)
//
// Light mode: glacier white / mist blue. Dark mode: deep sea blue.
// Semantic base hexes are the same in both modes; TEXT in light mode uses
// the darkened variants (see DesignTokens.V3Semantic) so contrast stays
// >= 4.5:1. Muted text passes on card/canvas in light mode (4.97/4.71:1)
// but is 4.45:1 on the secondary background, so never put muted text on
// v3SurfaceSecondary.
extension HealthTheme {
    static let v3Canvas = color(HealthDesignTokens.v3Canvas)
    static let v3SurfaceSecondary = color(HealthDesignTokens.v3SurfaceSecondary)
    static let v3Card = color(HealthDesignTokens.v3Card)
    static let v3Ink = color(HealthDesignTokens.v3Ink)
    static let v3Muted = color(HealthDesignTokens.v3Muted)
    static let v3Line = color(HealthDesignTokens.v3Line)

    private static func v3Base(_ semantic: HealthDesignTokens.V3Semantic) -> Color {
        Color(red: semantic.base.red, green: semantic.base.green, blue: semantic.base.blue)
    }

    private static func v3Text(_ semantic: HealthDesignTokens.V3Semantic) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? semantic.textDark : semantic.textLight
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }

    // Semantic base colors: rings, fills, icons (same hex both modes).
    static let v3Brand = v3Base(HealthDesignTokens.v3Brand)
    static let v3Sleep = v3Base(HealthDesignTokens.v3Sleep)
    static let v3Recovery = v3Base(HealthDesignTokens.v3Recovery)
    static let v3Stress = v3Base(HealthDesignTokens.v3Stress)
    static let v3Energy = v3Base(HealthDesignTokens.v3Energy)
    static let v3Load = v3Base(HealthDesignTokens.v3Load)
    static let v3Risk = v3Base(HealthDesignTokens.v3Risk)

    // Semantic text colors: darkened in light mode, base in dark mode.
    static let v3BrandText = v3Text(HealthDesignTokens.v3Brand)
    static let v3SleepText = v3Text(HealthDesignTokens.v3Sleep)
    static let v3RecoveryText = v3Text(HealthDesignTokens.v3Recovery)
    static let v3StressText = v3Text(HealthDesignTokens.v3Stress)
    static let v3EnergyText = v3Text(HealthDesignTokens.v3Energy)
    static let v3LoadText = v3Text(HealthDesignTokens.v3Load)
    static let v3RiskText = v3Text(HealthDesignTokens.v3Risk)

    // MARK: V3 layout (8pt grid)
    static let v3CardRadius: CGFloat = 20
    static let v3HeroRadius: CGFloat = 28
    static let v3ButtonRadius: CGFloat = 16
    static let v3Margin: CGFloat = 20
    static let v3Grid: CGFloat = 8
    static let v3ButtonHeight: CGFloat = 48
    static let v3MinTap: CGFloat = 44

    // MARK: V3 type (system sizes; Dynamic Type scales them)
    static let v3TitleFont: Font = .system(size: 28, weight: .bold, design: .rounded)
    static let v3HeadlineFont: Font = .system(size: 22, weight: .bold, design: .rounded)
    static let v3SectionFont: Font = .system(size: 18, weight: .semibold, design: .rounded)
    static let v3BodyFont: Font = .system(size: 16, weight: .regular)
    static let v3AuxFont: Font = .system(size: 13, weight: .regular)
}
