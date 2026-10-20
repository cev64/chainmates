import SwiftUI
import UIKit

/// Chainmates' look, taken from the site's `web/app.css` (football mode): newsprint paper,
/// near-black ink, hairline rules, one chalk-line green accent, brass only for under-par results.
/// Colour names match the CSS custom properties (`--paper` is `Theme.paper`).
enum Theme {
    // MARK: Colour

    static let paper = Color(light: 0xF6F3EC, dark: 0x141311)
    static let paper2 = Color(light: 0xEEEADF, dark: 0x1E1C19)
    static let card = Color(light: 0xFBFAF6, dark: 0x1B1A17)
    static let ink = Color(light: 0x1A1917, dark: 0xEDE9E0)
    static let ink2 = Color(light: 0x4A4740, dark: 0xBDB7AB)
    static let ink3 = Color(light: 0x6B665A, dark: 0x8B8579)
    static let rule = Color(light: 0xDCD6C9, dark: 0x33302A)
    static let rule2 = Color(light: 0xBAB3A3, dark: 0x4B473F)
    static let accent = Color(light: 0x0B7A45, dark: 0x46C486)
    static let accentInk = Color(light: 0x0A6A3C, dark: 0x6FD8A2)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x141311)
    static let brass = Color(light: 0xE2B33C, dark: 0xE2B33C)
    static let brassInk = Color(light: 0x855C00, dark: 0xE9C25A)
    static let brassDeep = Color(light: 0xC99412, dark: 0xF2C640)
    static let brassSoft = Color(light: 0xF3E2B4, dark: 0x3A2F14)
    static let bad = Color(light: 0xC42B1C, dark: 0xFF6B5A)
    /// Text on brass fills, in both themes.
    static let onBrass = Color(hex: 0x1A1917)
    /// `.club` fallback when a team has no colour.
    static let clubFallback = Color(hex: 0x8A94A1)
    /// The app icon's second link (the brand's safety orange; the in-app accent is green).
    static let brandOrange = Color(hex: 0xE8590C)

    /// `--lift`: the only shadow, for popovers, sheets and toasts.
    static func lift(_ scheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) {
        scheme == .dark ? (Color.black.opacity(0.6), 17, 12) : (Color(hex: 0x1A1917).opacity(0.28), 15, 10)
    }

    // MARK: Shape

    /// `--r-s`: buttons, field, toast, popover.
    static let radiusS: CGFloat = 6
    /// `--r-m`: sheets and dialogs.
    static let radiusM: CGFloat = 10
    /// The site's content column: `min(640px, 100% - 32px)`.
    static let columnMax: CGFloat = 640
    static let gutter: CGFloat = 16
    static let hairline: CGFloat = 1
    /// Masthead rules (bottom of the hero, page titles, status card).
    static let mastheadRule: CGFloat = 2

    // MARK: Type

    /// Zilla Slab for display: headlines, names and big numerals.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        Fonts.font(family: .display, size: size, weight: weight, relativeTo: style)
    }

    /// Libre Franklin for body and UI.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        Fonts.font(family: .body, size: size, weight: weight, relativeTo: style)
    }
}

/// The two web fonts, used when bundled (both SIL OFL 1.1, in `Chainmates/Fonts/` and listed
/// under `UIAppFonts`), otherwise the closest system faces: New York for Zilla Slab and SF for
/// Libre Franklin. Sizes scale with Dynamic Type relative to `style`.
enum Fonts {
    enum Family { case display, body }

    static func font(family: Family, size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        if let name = postScriptName(family: family, weight: weight), UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: style)
        }
        let scaled = UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size)
        return .system(size: scaled, weight: weight, design: family == .display ? .serif : .default)
    }

    private static func postScriptName(family: Family, weight: Font.Weight) -> String? {
        switch family {
        case .display:
            switch weight {
            case .medium: return "ZillaSlab-Medium"
            case .semibold: return "ZillaSlab-SemiBold"
            default: return "ZillaSlab-Bold"
            }
        case .body:
            switch weight {
            case .medium: return "LibreFranklin-Medium"
            case .semibold: return "LibreFranklin-SemiBold"
            case .bold: return "LibreFranklin-Bold"
            case .heavy, .black: return "LibreFranklin-ExtraBold"
            default: return "LibreFranklin-Regular"
            }
        }
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A colour that follows the light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    /// `#RRGGBB` from players.json's team table; `nil` when it doesn't parse.
    init?(cssHex: String) {
        var s = cssHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

/// The header's three-state theme toggle (`chainmates.theme`: "light", "dark" or absent).
enum ThemePreference: String, CaseIterable {
    case automatic, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var next: ThemePreference {
        switch self {
        case .automatic: .light
        case .light: .dark
        case .dark: .automatic
        }
    }
}
