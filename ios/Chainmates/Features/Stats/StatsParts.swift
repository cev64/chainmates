import SwiftUI

// Pieces shared by the Statistics screen, the Archive screen and the results sheet.

// MARK: - Page title

/// The two-link glyph in front of a page title (web: viewBox 40x24, stroke 3.5).
struct StatsTitleGlyph: View {
    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 40
            let style = StrokeStyle(lineWidth: 3.5 * s)
            ctx.stroke(Path(roundedRect: CGRect(x: 2 * s, y: 3 * s, width: 22 * s, height: 18 * s), cornerRadius: 9 * s),
                       with: .color(Theme.ink), style: style)
            ctx.stroke(Path(roundedRect: CGRect(x: 16 * s, y: 3 * s, width: 22 * s, height: 18 * s), cornerRadius: 9 * s),
                       with: .color(Theme.accent), style: style)
        }
        .frame(width: 30, height: 18)
        .accessibilityHidden(true)
    }
}

/// The title block of the Archive and Statistics pages: glyph and title, a line of explanation,
/// and the 2-point ink masthead rule below.
struct StatsPageMasthead: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                StatsTitleGlyph()
                Text(title)
                    .font(Theme.display(36, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(subtitle)
                .font(Theme.body(14, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            Rule.masthead
                .padding(.top, 14)
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

// MARK: - Count-up numbers

/// A number that counts up from 0 (ease-out cubic over `600 + min(300, value * 8)` ms, like the
/// web's `animateCounts`). With Reduce Motion, or for 0, it just shows the value.
struct StatsCountingNumber: View {
    let value: Int
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double?

    var body: some View {
        CountText(value: shown ?? (reduceMotion || value <= 0 ? Double(value) : 0))
            .onAppear { start() }
            .onChange(of: value) { _, new in shown = Double(new) }
    }

    private func start() {
        guard !reduceMotion, value > 0, shown == nil else { shown = Double(value); return }
        let duration = Double(600 + min(300, value * 8)) / 1000
        withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: duration).delay(delay)) {
            shown = Double(value)
        }
    }
}

private struct CountText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Int(value.rounded()).formatted(.number.grouping(.never)))
    }
}

// MARK: - Tiles

/// The 3 x 2 ruled grid of numbers: played, win %, streaks. Two columns at accessibility sizes.
struct StatTiles: View {
    let stats: Stats.View
    let streaks: Streaks
    /// When the numbers start counting (the web waits 420 ms in the results sheet, 80 ms on the page).
    var countDelay: Double = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private struct Tile: Identifiable {
        let id: Int
        let value: Int
        let label: String
        var detail: String?
    }

    private var tiles: [Tile] {
        let pct = stats.played > 0 ? Int((Double(stats.won) / Double(stats.played) * 100).rounded()) : 0
        return [
            Tile(id: 0, value: stats.played, label: "Played"),
            Tile(id: 1, value: pct, label: "Win %"),
            Tile(id: 2, value: streaks.cur, label: "Streak"),
            Tile(id: 3, value: streaks.max, label: "Best streak"),
            Tile(id: 4, value: streaks.parCur, label: "Bogey-free streak", detail: "Days in a row at par or better"),
            Tile(id: 5, value: streaks.parMax, label: "Best bogey-free", detail: "Longest run at par or better"),
        ]
    }

    var body: some View {
        let count = typeSize.isAccessibilitySize ? 2 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: count)
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(tiles) { tile in
                VStack(spacing: 4) {
                    StatsCountingNumber(value: tile.value, delay: countDelay + Double(tile.id) * 0.028)
                        .font(Theme.display(34, .bold, relativeTo: .title))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(nonBreaking(tile.label))
                        .font(Theme.body(12.5, .regular, relativeTo: .caption))
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
                .padding(.bottom, 10)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                // Hairlines drawn per tile, so the grid sits on any background (paper or a sheet).
                .overlay(alignment: .trailing) {
                    if tile.id % count != count - 1 { Rectangle().fill(Theme.rule).frame(width: 1) }
                }
                .overlay(alignment: .bottom) { Rule() }
                .overlay(alignment: .top) { if tile.id < count { Rule() } }
                .opacity(shown || reduceMotion ? 1 : 0)
                .animation(reduceMotion ? .linear(duration: 0.15) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.36).delay(Double(tile.id) * 0.028), value: shown)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.label)
                .accessibilityValue(String(tile.value))
                .accessibilityHint(tile.detail ?? "")
            }
        }
        .onAppear { shown = true }
    }

    /// "Bogey-free" never breaks at its hyphen.
    private func nonBreaking(_ label: String) -> String {
        label.replacingOccurrences(of: "Bogey-free", with: "Bogey\u{2060}-\u{2060}free")
    }
}

// MARK: - Rise-in

/// The web's `rise`: opacity 0 to 1 with a short lift, after `delay`. Reduce Motion cross-fades.
struct StatsRiseIn: ViewModifier {
    let shown: Bool
    var delay: Double = 0
    var duration: Double = 0.36
    var distance: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .animation(reduceMotion ? .linear(duration: 0.15)
                                    : .timingCurve(0.2, 0.8, 0.2, 1, duration: duration).delay(delay), value: shown)
    }
}

extension View {
    func statsRise(_ shown: Bool, delay: Double = 0, duration: Double = 0.36, distance: CGFloat = 8) -> some View {
        modifier(StatsRiseIn(shown: shown, delay: delay, duration: duration, distance: distance))
    }
}
