import Foundation

/// Semantic color tokens (DESIGN_SYSTEM_V2), as light/dark RGB triples.
/// Pure data on purpose: no SwiftUI or UIKit here, so HealthCore stays a
/// logic-only package that still compiles on macOS for unit tests. Each app
/// target resolves these through its own tiny helper (HealthTheme on iOS,
/// WatchTheme on watchOS). The hex values are the single source of truth;
/// no view may hard-code a brand color.
public enum HealthDesignTokens {
    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
        /// Exact sRGB hex, e.g. RGB(hex: 0x125E63).
        public init(hex: Int) {
            self.red = Double((hex >> 16) & 0xFF) / 255
            self.green = Double((hex >> 8) & 0xFF) / 255
            self.blue = Double(hex & 0xFF) / 255
        }
    }

    public struct Token: Equatable, Sendable {
        public let light: RGB
        public let dark: RGB
        public init(light: RGB, dark: RGB) {
            self.light = light
            self.dark = dark
        }
        public init(hexLight: Int, hexDark: Int) {
            self.light = RGB(hex: hexLight)
            self.dark = RGB(hex: hexDark)
        }
    }

    public static let jade = Token(hexLight: 0x125E63, hexDark: 0x1A777B)
    public static let teal = Token(hexLight: 0x14A38E, hexDark: 0x23CCB0)
    public static let heart = Token(hexLight: 0xE04A54, hexDark: 0xFF7A85)
    public static let sleep = Token(hexLight: 0x5C64C7, hexDark: 0x959CFF)
    public static let amber = Token(hexLight: 0xCA7A30, hexDark: 0xF0AD60)
    /// Sky has no dark value in the spec; the dark value is a brightened sky
    /// chosen for dark backgrounds, documented here rather than guessed inline.
    public static let sky = Token(hexLight: 0x5CA6DE, hexDark: 0x8CC3EE)
    public static let ink = Token(hexLight: 0x142932, hexDark: 0xF0F7F7)
    public static let muted = Token(hexLight: 0x667A83, hexDark: 0xA7BABC)
    public static let canvas = Token(hexLight: 0xF6F9F7, hexDark: 0x0E161A)
    public static let surface = Token(hexLight: 0xFFFFFF, hexDark: 0x1B282B)

    /// Sleep stage colors, shared by iPhone and Watch so the five stages
    /// always mean the same thing on both devices. Labels always accompany
    /// the colors; no state is ever carried by color alone.
    public static func stageToken(for stage: SleepStage) -> Token {
        switch stage {
        case .deep: return sleep
        case .core: return sky
        case .rem: return teal
        case .unspecified: return muted
        case .awake: return amber
        }
    }

    // MARK: - V4 iOS presentation palette
    public static let v4Canvas = Token(hexLight: 0xF6F5FB, hexDark: 0x151321)
    public static let v4Card = Token(hexLight: 0xFFFFFF, hexDark: 0x211D31)
    public static let v4Ink = Token(hexLight: 0x1B1830, hexDark: 0xFAF5FF)
    public static let v4Muted = Token(hexLight: 0x625B75, hexDark: 0xC2B8D2)
    public static let v4Line = Token(hexLight: 0xE6E0F1, hexDark: 0x3D3452)
    public static let v4Accent = Token(hexLight: 0x5038A4, hexDark: 0xCFBAFF)

    // MARK: - V3 dual-theme tokens (GitHub Issue #2, 2026-11-17)
    //
    // Light mode: glacier white / mist blue. Dark mode: deep sea blue.
    // Exact hex from the V3 spec; do not change without a new spec.
    // Muted light (#60718A) passes 4.5:1 on card (#FFFFFF, 4.97:1) and
    // canvas (#F6F9FF, 4.71:1) but is 4.45:1 on the secondary background
    // (#EDF3FB), so never put muted text on v3SurfaceSecondary.
    public static let v3Canvas = Token(hexLight: 0xF6F9FF, hexDark: 0x07111F)
    public static let v3SurfaceSecondary = Token(hexLight: 0xEDF3FB, hexDark: 0x172B45)
    public static let v3Card = Token(hexLight: 0xFFFFFF, hexDark: 0x101F33)
    public static let v3Ink = Token(hexLight: 0x14243A, hexDark: 0xF5F8FF)
    public static let v3Muted = Token(hexLight: 0x60718A, hexDark: 0x9AABC3)
    public static let v3Line = Token(hexLight: 0xDDE6F2, hexDark: 0x29415E)

    /// A V3 semantic color. `base` is the spec hex, used for rings, fills
    /// and icons in both modes. `textLight` is a darkened variant used for
    /// TEXT on light backgrounds only: every base hex fails WCAG 4.5:1 as
    /// light-mode text (brand 3.33, sleep 3.13, recovery 1.83, stress 1.71,
    /// energy 1.76, load 3.40, risk 2.84 on white), so light-mode text must
    /// use the darkened variant. `textDark` equals `base`: every base hex
    /// passes 4.5:1 as text on the dark card (#101F33: brand 4.99, sleep
    /// 5.29, recovery 9.08, stress 9.73, energy 9.44, load 4.87, risk 5.83).
    /// textLight values are GPT's design-spec correction (Issue #2,
    /// comment 6935424900, 2026-11-17): the original bright bases fail as
    /// small light-mode text (1.71-3.40:1). GPT's text colors, verified
    /// by computation against white, #F6F9FF and #EDF3FB (all >= 4.5:1):
    /// brand #1763B1 (6.08/5.76/5.44), sleep #6043B8 (7.02/6.65/6.29),
    /// recovery #087B58 (5.27/5.00/4.72), stress #006B85 (6.10/5.79/5.47),
    /// energy #8A5200 (6.39/6.06/5.72), load #713DB3 (6.95/6.59/6.23),
    /// risk #B32340 (6.50/6.16/5.82).
    public struct V3Semantic: Equatable, Sendable {
        public let base: RGB
        public let textLight: RGB
        public var textDark: RGB { base }
        public init(base: Int, textLight: Int) {
            self.base = RGB(hex: base)
            self.textLight = RGB(hex: textLight)
        }
    }

    public static let v3Brand = V3Semantic(base: 0x398BFF, textLight: 0x1763B1)
    public static let v3Sleep = V3Semantic(base: 0x9A7CFF, textLight: 0x6043B8)
    public static let v3Recovery = V3Semantic(base: 0x20D9A0, textLight: 0x087B58)
    public static let v3Stress = V3Semantic(base: 0x39D8F5, textLight: 0x006B85)
    public static let v3Energy = V3Semantic(base: 0xFFB547, textLight: 0x8A5200)
    public static let v3Load = V3Semantic(base: 0xA46CFF, textLight: 0x713DB3)
    public static let v3Risk = V3Semantic(base: 0xFF6578, textLight: 0xB32340)
}
