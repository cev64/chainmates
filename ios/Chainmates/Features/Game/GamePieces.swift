import SwiftUI

// The small drawn pieces of the game page (web/app.css: `.rail`, `.node-dot`, `.career`, `.stint`).

// MARK: - Flow layout

/// Wraps its children onto lines, like the web's `flex-wrap` rows (career lines, hint words,
/// the "+N more" list). Lines are centred vertically and aligned leading or trailing.
struct FlowLayout: Layout {
    var spacing: CGFloat = 9
    var lineSpacing: CGFloat = 4
    var trailing = false

    struct Line { var items: [(index: Int, size: CGSize)] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func lines(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Line] {
        var out: [Line] = [Line()]
        for (i, sub) in subviews.enumerated() {
            var size = sub.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = sub.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            let extra = out[out.count - 1].items.isEmpty ? 0 : spacing
            if out[out.count - 1].width + extra + size.width > maxWidth, !out[out.count - 1].items.isEmpty {
                out.append(Line())
            }
            let gap = out[out.count - 1].items.isEmpty ? 0 : spacing
            out[out.count - 1].items.append((i, size))
            out[out.count - 1].width += gap + size.width
            out[out.count - 1].height = max(out[out.count - 1].height, size.height)
        }
        return out.filter { !$0.items.isEmpty }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ls = lines(proposal.width ?? .infinity, subviews)
        var w = ls.map(\.width).max() ?? 0
        if let limit = proposal.width, limit.isFinite { w = min(w, limit) }
        let h = ls.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, ls.count - 1))
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(bounds.width, subviews) {
            var x = trailing ? bounds.maxX - line.width : bounds.minX
            for item in line.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}

// MARK: - Rails

/// How a stretch of the chain's vertical rail is drawn.
enum RailStyle: Equatable {
    /// A placed link: 2-point ink.
    case solid
    /// The live link to the next guess: dashed accent.
    case next
    /// The gap still to close before the finish: dashed `rule-2`.
    case pending
    /// The failed guess snapping off.
    case bad

    var color: Color {
        switch self {
        case .solid: Theme.ink
        case .next: Theme.accent
        case .pending: Theme.rule2
        case .bad: Theme.bad
        }
    }

    var dash: [CGFloat] { self == .next || self == .pending ? [3, 4] : [] }
}

struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// One stretch of rail, drawn from the top down to `progress`; `gild` lays brass over it (eagle).
struct RailLine: View {
    var style: RailStyle
    var progress: CGFloat = 1
    var gild: CGFloat = 0

    var body: some View {
        ZStack {
            VerticalLine()
                .trim(from: 0, to: progress)
                .stroke(style.color, style: StrokeStyle(lineWidth: 2, dash: style.dash))
            if gild > 0 {
                VerticalLine()
                    .trim(from: 0, to: gild)
                    .stroke(Theme.brassDeep, style: StrokeStyle(lineWidth: 2))
            }
        }
        .frame(width: 2)
        .accessibilityHidden(true)
    }
}

/// The 22-point knot on a rail: paper disc, 1.5-point ring, the two-link glyph (or an X).
struct RailKnot: View {
    var color: Color = Theme.ink
    var glyphColor: Color? = nil
    var cross = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.paper)
            Circle().strokeBorder(color, lineWidth: 1.5)
            if cross {
                CrossGlyph(size: 10, color: color)
            } else {
                LinkGlyph(size: 14, color: glyphColor ?? color)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// The web's X_SVG: two round-capped strokes.
struct CrossGlyph: View {
    var size: CGFloat = 12
    var color: Color = Theme.bad
    var weight: CGFloat = 3

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 24
            var p = Path()
            p.move(to: CGPoint(x: 6 * s, y: 6 * s)); p.addLine(to: CGPoint(x: 18 * s, y: 18 * s))
            p.move(to: CGPoint(x: 18 * s, y: 6 * s)); p.addLine(to: CGPoint(x: 6 * s, y: 18 * s))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: weight * s, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Node dot

/// The 36-point marker beside a player: hollow with the position, ink for the start, a check for
/// the finish (brass under par), a dashed flag while it's still the goal, a red X when lost.
struct NodeDot: View {
    enum Kind { case start, mid, target, ghost, lost }
    var kind: Kind
    var pos: String = ""
    var birdie = false
    var eagle = false
    /// The eagle's brass ring (0 to 1, it pops in at the lock-up).
    var ring: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().fill(fill)
            switch kind {
            case .ghost:
                Circle().strokeBorder(Theme.rule2, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                Image(systemName: "flag")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            case .lost:
                Circle().strokeBorder(Theme.bad, lineWidth: 1.5)
                CrossGlyph(size: 13, color: Theme.bad)
            case .target:
                Circle().strokeBorder(border, lineWidth: 1.5)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(birdie || eagle ? Theme.onBrass : Theme.paper)
            case .start, .mid:
                Circle().strokeBorder(Theme.ink, lineWidth: 1.5)
                Text(pos.isEmpty ? "\u{2022}" : String(pos.prefix(3)))
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(kind == .start ? Theme.paper : Theme.ink)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 36, height: 36)
        .overlay {
            if ring > 0 {
                Circle().strokeBorder(Theme.brass, lineWidth: 2)
                    .padding(-5)
                    .scaleEffect(0.55 + 0.45 * ring)
                    .opacity(ring)
            }
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch kind {
        case .start: Theme.ink
        case .target: eagle ? Theme.brassDeep : birdie ? Theme.brass : Theme.ink
        default: Theme.paper
        }
    }

    private var border: Color { eagle ? Theme.brassDeep : birdie ? Theme.brass : Theme.ink }
}

// MARK: - Career line

private struct CareerEntranceKey: EnvironmentKey { static let defaultValue = false }
private struct CareerFoldingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Career lines slide in, staggered, right after a switch to easy.
    var careerEntrance: Bool {
        get { self[CareerEntranceKey.self] }
        set { self[CareerEntranceKey.self] = newValue }
    }
    /// Career lines fade up and away before a switch to hard.
    var careerFolding: Bool {
        get { self[CareerFoldingKey.self] }
        set { self[CareerFoldingKey.self] = newValue }
    }
}

/// Easy mode's career line (`careerHTML`): each stint is a ClubChip joined to its years,
/// chronological, strung on a hairline. `max` keeps search rows to one line: the longest stints
/// stay, in career order, and the rest fold into "+N more".
struct CareerLine: View {
    let playerID: String
    var max: Int? = nil
    var trailing = false
    @Environment(GameController.self) private var c
    @Environment(AppModel.self) private var app
    @Environment(\.careerFolding) private var folding

    var body: some View {
        let all = c.careers[playerID] ?? []
        let (shown, more) = trimmed(all)
        Group {
            if max != nil {
                // One line that never widens its row: drawn in an overlay, clipped at the edge.
                HStack(spacing: 9) { items(shown, more) }
                    .fixedSize()
                    .hidden()
                    .frame(maxWidth: 1, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) { HStack(spacing: 9) { items(shown, more) }.fixedSize() }
                    .clipped()
            } else {
                FlowLayout(spacing: 9, lineSpacing: 4, trailing: trailing) { items(shown, more) }
                    .clipped()
            }
        }
        .opacity(folding ? 0 : 1)
        .offset(y: folding ? -4 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(shown, more))
        .task(id: playerID) { if c.careers[playerID] == nil { await c.loadCareers([playerID]) } }
    }

    @ViewBuilder private func items(_ shown: [StintRange], _ more: Int) -> some View {
        ForEach(Array(shown.enumerated()), id: \.offset) { i, r in
            StintChip(range: r, index: i, joinLeading: !trailing && i > 0, joinTrailing: trailing && i < shown.count - 1)
        }
        if more > 0 {
            Text("+\(more) more")
                .font(Theme.body(11.5, .semibold, relativeTo: .caption))
                .foregroundStyle(Theme.ink3)
                .fixedSize()
        }
    }

    private func trimmed(_ rs: [StintRange]) -> ([StintRange], Int) {
        guard let max, rs.count > max else { return (rs, 0) }
        let keep = Set(rs.enumerated()
            .sorted { a, b in
                let da = a.element.to - a.element.from, db = b.element.to - b.element.from
                return da != db ? da > db : a.element.to > b.element.to
            }
            .prefix(max).map(\.offset))
        return (rs.enumerated().filter { keep.contains($0.offset) }.map(\.element), rs.count - max)
    }

    private func label(_ shown: [StintRange], _ more: Int) -> String {
        shown.map { r in
            app.teamFullName(TeamSeason(team: r.team, season: r.to)) + " " + (r.from == r.to ? "\(r.from)" : "\(r.from) to \(r.to)")
        }.joined(separator: ", ") + (more > 0 ? ", and \(more) more" : "")
    }
}

/// One stint: a ClubChip with its years, in a hairline box; the hairline links it to the next.
struct StintChip: View {
    let range: StintRange
    let index: Int
    var joinLeading = false
    var joinTrailing = false
    @Environment(\.careerEntrance) private var entrance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = true
    @ScaledMetric(relativeTo: .caption2) private var scaled: CGFloat = 18
    private var height: CGFloat { min(scaled, 30) }

    var body: some View {
        HStack(spacing: 0) {
            ClubChip(team: range.team, season: range.to, height: height, minWidth: 30)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3))
            Text(Format.stintYears(range))
                .font(Theme.body(11, .semibold, relativeTo: .caption2))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
                .padding(.leading, 4)
                .padding(.trailing, 5)
                .fixedSize()
        }
        .frame(minHeight: height)
        .background(Theme.card, in: .rect(cornerRadius: 3))
        .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.rule2, lineWidth: 1) }
        .overlay(alignment: .leading) {
            if joinLeading { Rectangle().fill(Theme.rule2).frame(width: 6, height: 1).offset(x: -8) }
        }
        .overlay(alignment: .trailing) {
            if joinTrailing { Rectangle().fill(Theme.rule2).frame(width: 6, height: 1).offset(x: 8) }
        }
        .opacity(shown ? 1 : 0)
        .offset(x: shown ? 0 : -8)
        .onAppear {
            guard entrance, !reduceMotion else { return }
            shown = false
            withAnimation(Ease.out(0.26).delay(Double(Swift.min(index, 8)) * 0.03)) { shown = true }
        }
    }
}

// MARK: - Rich text

/// A line in Libre Franklin where parts starting with "*" are bold ink, the rest `color`
/// (the web's `<b>` inside ink-2 text: "Teammates on the **2015 Broncos**").
struct RichText: View {
    let parts: [String]
    var size: CGFloat = 13
    var weight: Font.Weight = .regular
    var boldWeight: Font.Weight = .bold
    var color: Color = Theme.ink2
    var boldColor: Color = Theme.ink
    var relativeTo: Font.TextStyle = .footnote

    init(_ parts: [String], size: CGFloat = 13, weight: Font.Weight = .regular, boldWeight: Font.Weight = .bold,
         color: Color = Theme.ink2, boldColor: Color = Theme.ink, relativeTo: Font.TextStyle = .footnote) {
        self.parts = parts; self.size = size; self.weight = weight; self.boldWeight = boldWeight
        self.color = color; self.boldColor = boldColor; self.relativeTo = relativeTo
    }

    var body: some View {
        Text(attributed).monospacedDigit()
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for part in parts {
            let bold = part.hasPrefix("*")
            var run = AttributedString(bold ? String(part.dropFirst()) : part)
            run.font = Theme.body(size, bold ? boldWeight : weight, relativeTo: relativeTo)
            run.foregroundColor = bold ? boldColor : color
            out += run
        }
        return out
    }
}
