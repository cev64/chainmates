import SwiftUI

/// "How to play" (web `helpHTML`). Present with `app.sheet == .help`; the lead attaches
/// `.presentationDetents([.large])`, which this view also declares itself.
struct HelpSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rungs: [Rung] = []

    private struct Rung: Hashable { let links: Int; let label: String }

    private var sport: Sport { app.sport }
    private var view: GameState.View? { app.session?.state?.view }

    var body: some View {
        let _ = dynamicTypeSize  // re-run when Dynamic Type changes (Theme fonts scale at call time)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("How to play")
                        .font(Theme.display(28, .bold, relativeTo: .title))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 12)
                    Rule()
                    VStack(alignment: .leading, spacing: 0) {
                        if let v = view { todayBlock(v).infoRise(delay: 0.04) }
                        InfoText.rich("A new puzzle every day at midnight Eastern.", size: 16, color: Theme.ink)
                            .lineSpacing(3)
                            .padding(.bottom, 14)
                        rules
                        Text("Seasons \(seasonsRange), regular season and playoffs. Your progress and stats stay on this device.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.ink3)
                            .padding(.bottom, 16)
                        Button("Start playing") { dismiss() }
                            .buttonStyle(.chain(.ink, large: true, wide: true))
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
        }
        .tint(Theme.accentInk)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .onDisappear { Store.seenHelp = true }
        .task(id: app.session?.state?.json) { await loadLadder() }
    }

    // MARK: Today's puzzle

    private var seasonsRange: String {
        guard let first = app.seasons.min(), let last = app.seasons.max() else { return "2002\u{2013}2026" }
        return first == last ? String(first) : "\(first)\u{2013}\(last)"
    }

    private func spare(_ n: Int) -> String { ["none", "one", "two", "three"].indices.contains(n) ? ["none", "one", "two", "three"][n] : String(n) }

    private func links(_ n: Int) -> String { n == 1 ? "1 link" : "\(n) links" }

    @ViewBuilder
    private func todayBlock(_ v: GameState.View) -> some View {
        let best = v.best ?? v.par
        let mode = v.effectiveMode == .hard ? "Hard" : "Easy"
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(v.n == app.todayNumber ? "Today's puzzle" : "Puzzle No. \(v.n)")
                    .font(Theme.body(13, .semibold)).foregroundStyle(Theme.ink3)
                Spacer(minLength: 8)
                Text("\(mode) mode")
                    .font(Theme.body(13, .bold)).foregroundStyle(Theme.accentInk)
            }
            .accessibilityElement(children: .combine)
            ladderText(par: v.par).lineSpacing(2)
            InfoText.rich("\(sport.tagline) The shortest chain takes **\(links(best))**. Par gives you \(spare(v.par - best)) to spare\(v.effectiveMode == .hard ? " on hard mode" : "").",
                          size: 15, color: Theme.ink2)
                .lineSpacing(5)
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rule.masthead }
        .padding(.bottom, 14)
    }

    private func ladderText(par: Int) -> Text {
        var s = "**Par \(par)**"
        for r in rungs { s += " \u{00B7} \(r.label) in \(r.links)" }
        return InfoText.rich(s + ".", size: 22, color: Theme.ink, weight: .semibold, boldWeight: .bold, display: true, style: .title2)
    }

    /// "birdie in 4 · eagle in 3", asked from the core through the session.
    private func loadLadder() async {
        guard let session = app.session, let v = session.state?.view else { rungs = []; return }
        let best = v.best ?? v.par
        var out: [Rung] = []
        var l = v.par - 1
        while l >= best && l > 0 {
            if let label = await session.label(atLinks: l) { out.append(Rung(links: l, label: label.lowercased())) }
            l -= 1
        }
        rungs = out
    }

    // MARK: Rules

    private var rules: some View {
        let items: [(head: String, body: String)] = [
            ("The chain.", "You get a Start and a Finish player. Add players one at a time; each must have been a **teammate** of the one before (\(sport.rule)). Reach a teammate of the Finish player and you've solved it."),
            ("Par.", "The fewest links possible, plus some to spare. One link under par is a **birdie**, two under is an **eagle**, and every link over par is +1. Par or better keeps your bogey-free streak alive."),
            ("Modes.", "**Hard**, the default, shows no teams: just names, positions and years. Par is the shortest chain plus two, so eagles are only possible on hard. **Easy** shows every team a player was on, with years, and par is the shortest plus one. You can drop to easy mid-game; hard starts fresh."),
            (sport.lives.prefix(1).uppercased() + sport.lives.dropFirst() + ".", "You have 3. A guess that wasn't a teammate is an \(sport.miss) and costs one. Lose them all and it's a \(sport.lost.lowercased())."),
            ("Help.", "Undo is free. A hint reveals a team and a position for your next link, and costs a \(sport.life)."),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 0) {
                    Rule()
                    ruleText(item.head, item.body)
                        .lineSpacing(5)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if i == items.count - 1 { Rule() }
                }
                .infoRise(delay: Double(i) * 0.04 + 0.08, distance: 6)
            }
        }
        .padding(.bottom, 16)
    }

    private func ruleText(_ head: String, _ body: String) -> Text {
        var out = AttributedString()
        var h = AttributedString(head + " ")
        h.font = Theme.display(17, .bold, relativeTo: .headline)
        h.foregroundColor = Theme.ink
        out.append(h)
        for (i, piece) in body.components(separatedBy: "**").enumerated() where !piece.isEmpty {
            var run = AttributedString(piece)
            run.font = Theme.body(15, i % 2 == 1 ? .bold : .regular)
            run.foregroundColor = i % 2 == 1 ? Theme.ink : Theme.ink2
            out.append(run)
        }
        return Text(out)
    }
}

#Preview("How to play") {
    HelpSheet().environment(AppModel())
}
