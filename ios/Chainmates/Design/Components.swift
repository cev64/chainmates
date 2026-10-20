import SwiftUI

// Shared pieces of the Chainmates look (web/app.css). Screens build on these rather than restyling.

// MARK: - ClubChip

/// A team as its abbreviation on the team's primary colour, with a thin secondary-colour stripe
/// along the bottom. No logos. Text is white or near-black, whichever reads better on the colour.
struct ClubChip: View {
    let team: String
    var season: Int?
    var height: CGFloat = 18
    var minWidth: CGFloat = 32
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .caption2) private var fontSize: CGFloat = 9.5

    var body: some View {
        let info = app.team(team)
        let c1 = info?.c1 ?? "#8A94A1"
        let fill = Color(cssHex: c1) ?? Theme.clubFallback
        let stripe = Color(cssHex: info?.c2 ?? c1) ?? fill
        Text(team)
            .font(Theme.body(fontSize, .heavy, relativeTo: .caption2))
            .tracking(0.4)
            .foregroundStyle(Format.chipInkIsLight(c1) ? Color.white : Color(hex: 0x0B1726))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(minWidth: minWidth, minHeight: height)
            .background(fill, in: .rect(cornerRadius: 3))
            .overlay(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                    .fill(stripe)
                    .frame(height: 2)
            }
            .overlay {
                if scheme == .dark {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName(info))
    }

    private func accessibilityName(_ info: TeamInfo?) -> String {
        if let season { return "\(app.teamFullName(TeamSeason(team: team, season: season))), \(season)" }
        guard let info else { return team }
        return [info.city, info.name].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Brand mark

/// Two interlocked chain links (web/icon.svg): link A in ink passes over link B in the accent
/// at the top overlap.
struct BrandMark: View {
    var size: CGFloat = 34
    var first: Color = Theme.ink
    var second: Color = Theme.accent

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 40
            ctx.translateBy(x: 20 * s, y: 20 * s)
            ctx.rotate(by: .degrees(-32))
            ctx.translateBy(x: -20 * s, y: -20 * s)
            let style = StrokeStyle(lineWidth: 4.2 * s)
            let a = Path(roundedRect: CGRect(x: 4 * s, y: 12 * s, width: 20 * s, height: 16 * s), cornerRadius: 8 * s)
            let b = Path(roundedRect: CGRect(x: 16 * s, y: 12 * s, width: 20 * s, height: 16 * s), cornerRadius: 8 * s)
            ctx.stroke(a, with: .color(first), style: style)
            ctx.stroke(b, with: .color(second), style: style)
            var top = ctx
            top.clip(to: Path(CGRect(x: 12 * s, y: 6 * s, width: 16 * s, height: 14 * s)))
            top.stroke(a, with: .color(first), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The small two-link glyph on chain knots and the hero's gap (24-point box, stroke 2.6).
struct LinkGlyph: View {
    var size: CGFloat = 14
    var color: Color = Theme.ink

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 24
            ctx.translateBy(x: 12 * s, y: 12 * s)
            ctx.rotate(by: .degrees(-35))
            ctx.translateBy(x: -12 * s, y: -12 * s)
            let style = StrokeStyle(lineWidth: 2.6 * s)
            ctx.stroke(Path(roundedRect: CGRect(x: 2.5 * s, y: 8 * s, width: 11 * s, height: 8 * s), cornerRadius: 4 * s), with: .color(color), style: style)
            ctx.stroke(Path(roundedRect: CGRect(x: 10.5 * s, y: 8 * s, width: 11 * s, height: 8 * s), cornerRadius: 4 * s), with: .color(color), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The wide two-link art on status cards (80 x 40 box), brass on an eagle.
struct StatusArt: View {
    var first: Color = Theme.ink
    var second: Color = Theme.accent

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 80
            let style = StrokeStyle(lineWidth: 4.5 * s)
            ctx.stroke(Path(roundedRect: CGRect(x: 6 * s, y: 8 * s, width: 38 * s, height: 24 * s), cornerRadius: 12 * s), with: .color(first), style: style)
            ctx.stroke(Path(roundedRect: CGRect(x: 36 * s, y: 8 * s, width: 38 * s, height: 24 * s), cornerRadius: 12 * s), with: .color(second), style: style)
        }
        .frame(width: 64, height: 32)
        .accessibilityHidden(true)
    }
}

// MARK: - Rules

/// A 1-point hairline (`--rule`), or the 2-point ink masthead rule.
struct Rule: View {
    var weight: CGFloat = Theme.hairline
    var color: Color = Theme.rule

    var body: some View {
        Rectangle().fill(color).frame(height: weight).accessibilityHidden(true)
    }

    static var masthead: Rule { Rule(weight: Theme.mastheadRule, color: Theme.ink) }
}

// MARK: - Buttons

/// The site's buttons: 1.5-point ink outline, radius 6, 44 points tall, label 14.5/700.
/// Content buttons use these; bars and floating controls use the system Liquid Glass styles.
struct ChainButtonStyle: ButtonStyle {
    enum Kind { case outline, quiet, primary, ink }
    var kind: Kind = .outline
    var large = false
    var wide = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(large ? 15.5 : 14.5, .bold, relativeTo: .body))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(minHeight: large ? 50 : 44)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(background, in: .rect(cornerRadius: Theme.radiusS))
            .overlay {
                if kind != .quiet {
                    RoundedRectangle(cornerRadius: Theme.radiusS).strokeBorder(border, lineWidth: 1.5)
                }
            }
            .contentShape(.rect(cornerRadius: Theme.radiusS))
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .outline: Theme.ink
        case .quiet: Theme.ink2
        case .primary: Theme.onAccent
        case .ink: Theme.paper
        }
    }

    private var background: Color {
        switch kind {
        case .outline, .quiet: .clear
        case .primary: Theme.accent
        case .ink: Theme.ink
        }
    }

    private var border: Color {
        switch kind {
        case .outline, .quiet, .ink: Theme.ink
        case .primary: Theme.accent
        }
    }
}

extension ButtonStyle where Self == ChainButtonStyle {
    static func chain(_ kind: ChainButtonStyle.Kind = .outline, large: Bool = false, wide: Bool = false) -> ChainButtonStyle {
        ChainButtonStyle(kind: kind, large: large, wide: wide)
    }
}

// MARK: - Layout

extension View {
    /// The site's content column: centred, at most 640 points, 16-point gutters.
    func contentColumn(_ max: CGFloat = Theme.columnMax) -> some View {
        frame(maxWidth: max)
            .padding(.horizontal, Theme.gutter)
            .frame(maxWidth: .infinity)
    }

    /// Paper behind everything, edge to edge.
    func paperBackground() -> some View {
        background(Theme.paper.ignoresSafeArea())
    }
}

// MARK: - Motion

extension Animation {
    /// Links springing into the chain.
    static let chainSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Sheets, undo and small state changes.
    static let chainSnappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
}

/// `withAnimation`, or no animation when Reduce Motion is on (then state changes cross-fade).
@MainActor
func animate(_ reduceMotion: Bool, _ animation: Animation = .chainSpring, _ body: () -> Void) {
    if reduceMotion { withAnimation(.easeInOut(duration: 0.2), body) } else { withAnimation(animation, body) }
}
