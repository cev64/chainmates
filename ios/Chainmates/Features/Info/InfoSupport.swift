import SwiftUI

/// Small helpers shared by the sheets, the footer and the status views.
enum InfoText {
    /// Text with `**bold**` runs, set in Libre Franklin (via `Theme.body`) so the bold stays in the
    /// site's face. Bold runs use `boldColor`.
    static func rich(_ markup: String, size: CGFloat, color: Color, boldColor: Color = Theme.ink,
                     weight: Font.Weight = .regular, boldWeight: Font.Weight = .bold,
                     display: Bool = false, style: Font.TextStyle = .body) -> Text {
        var out = AttributedString()
        for (i, piece) in markup.components(separatedBy: "**").enumerated() where !piece.isEmpty {
            var run = AttributedString(piece)
            let bold = i % 2 == 1
            let w = bold ? boldWeight : weight
            run.font = display ? Theme.display(size, w, relativeTo: style) : Theme.body(size, w, relativeTo: style)
            run.foregroundColor = bold ? boldColor : color
            out.append(run)
        }
        return Text(out)
    }
}

/// The site's `rise`: fades in while moving up a few points. With Reduce Motion it is a plain
/// 150 ms fade.
private struct RiseIn: ViewModifier {
    var delay: Double
    var distance: CGFloat
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .onAppear {
                guard !shown else { return }
                let animation: Animation = reduceMotion
                    ? .linear(duration: 0.15)
                    : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26).delay(delay)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    func infoRise(delay: Double = 0, distance: CGFloat = 8) -> some View {
        modifier(RiseIn(delay: delay, distance: distance))
    }
}

/// Flows its children onto centred rows, wrapping at the proposed width (the footer's link row).
struct WrapLayout: Layout {
    var hSpacing: CGFloat = 14
    var vSpacing: CGFloat = 0

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let extra = row.items.isEmpty ? size.width : hSpacing + size.width
            if !row.items.isEmpty, row.width + extra > width {
                rows.append(Row())
                row = rows[rows.count - 1]
            }
            let add = row.items.isEmpty ? size.width : hSpacing + size.width
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width = row.width + add
            rows[rows.count - 1].height = max(row.height, size.height)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = rows(proposal.width ?? .infinity, subviews)
        let height = r.reduce(0) { $0 + $1.height } + vSpacing * CGFloat(max(r.count - 1, 0))
        let width = proposal.width ?? (r.map(\.width).max() ?? 0)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }
}
