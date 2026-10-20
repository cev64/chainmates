import SwiftUI

/// The archive (web `#archive`): every puzzle so far, newest first, with your result on each.
/// Shown in the main column when `app.route == .archive`. Tapping a row calls `app.open(n)`.
/// It scrolls itself.
struct ArchiveScreen: View {
    @Environment(AppModel.self) private var app
    @State private var entries: [ArchiveEntry] = []
    @State private var loaded = false
    @State private var metrics = Metrics(width: 0, foldGap: 0)

    private static let wideBreakpoint: CGFloat = 900

    struct Metrics: Equatable {
        var width: CGFloat
        /// The width of the fold between two columns, 0 when the screen has none.
        var foldGap: CGFloat
    }

    private struct LoadKey: Equatable {
        let today: Int
        let state: GameState?
    }

    var body: some View {
        let wide = metrics.width >= Self.wideBreakpoint
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatsPageMasthead(title: "Archive",
                                  subtitle: "Every puzzle so far. Replays are practice and don't change your stats.")
                if loaded && entries.isEmpty {
                    Text("No puzzles yet.")
                        .font(Theme.body(14, .regular, relativeTo: .callout))
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 14)
                } else if wide {
                    grid
                } else {
                    list
                }
            }
            .padding(.bottom, 28)
            .contentColumn(wide ? 960 : Theme.columnMax)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paperBackground()
        .onGeometryChange(for: Metrics.self) { proxy in
            Metrics(width: proxy.size.width, foldGap: Self.foldGap(proxy))
        } action: { metrics = $0 }
        .task(id: LoadKey(today: app.todayNumber, state: app.session?.state)) {
            entries = await ArchiveEntry.load(app)
            loaded = true
        }
    }

    /// One hairline-separated column.
    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                if i > 0 { Rule() }
                ArchiveRow(entry: entry, index: i)
            }
        }
    }

    /// Two columns on wide screens, so a fold (the iPhone Duo's) falls between them.
    private var grid: some View {
        let gap = max(40, metrics.foldGap)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: gap, alignment: .top), GridItem(.flexible(), alignment: .top)],
                         alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                VStack(spacing: 0) {
                    if i >= 2 { Rule() }
                    ArchiveRow(entry: entry, index: i)
                }
            }
        }
    }

    /// The fold's width from the system's reserved regions (iOS 27.1); 0 without one.
    private static func foldGap(_ proxy: GeometryProxy) -> CGFloat {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
            if let region = regions.first {
                return region.frame.width + region.margins.leading + region.margins.trailing
            }
        }
        #endif
        return 0
    }
}

// MARK: - Row

private struct ArchiveRow: View {
    let entry: ArchiveEntry
    let index: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 64
    @State private var shown = false

    var body: some View {
        Button { app.open(entry.puzzle.n) } label: {
            Group {
                if typeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 12) {
                        number
                        VStack(alignment: .leading, spacing: 8) {
                            who
                            ArchiveBadgeView(badge: entry.badge, note: entry.note, trailing: false)
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        number
                        who.frame(maxWidth: .infinity, alignment: .leading)
                        ArchiveBadgeView(badge: entry.badge, note: entry.note, trailing: true)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(entry.isToday ? Theme.paper2 : .clear, in: .rect(cornerRadius: Theme.radiusS))
            .contentShape(.rect(cornerRadius: Theme.radiusS))
        }
        .buttonStyle(ArchivePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
        .accessibilityHint("Opens the puzzle")
        .archiveRise(shown: shown, index: index)
        .onAppear { shown = true }
    }

    private var number: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No.")
                .font(Theme.body(11.5, .medium, relativeTo: .caption2))
                .foregroundStyle(Theme.ink3)
            Text(String(entry.puzzle.n))
                .font(Theme.display(22, .bold, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.leading, 4)
        .frame(width: numberWidth, alignment: .leading)
    }

    private var who: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Text(Format.date(entry.puzzle.date)).font(Theme.body(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink))\(entry.isToday ? Text(" \u{00B7} Today").font(Theme.body(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.accentInk) : Text(""))")
            Text("Par \(entry.par)" + (entry.puzzle.theme.map { " \u{00B7} \($0)" } ?? ""))
                .font(Theme.body(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Theme.ink2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    /// The web's `rise`: each row lifts in, staggered 24 ms for the first 14.
    func archiveRise(shown: Bool, index: Int) -> some View {
        modifier(ArchiveRise(shown: shown, delay: Double(min(index, 14)) * 0.024))
    }
}

private struct ArchiveRise: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .animation(reduceMotion ? .linear(duration: 0.15)
                                    : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26).delay(delay), value: shown)
    }
}

private struct ArchivePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.paper2 : .clear, in: .rect(cornerRadius: Theme.radiusS))
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Badge

private struct ArchiveBadgeView: View {
    let badge: ArchiveEntry.Badge
    let note: String
    /// Right-aligned beside the title, or left-aligned below it.
    let trailing: Bool

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            badgeView
            if !note.isEmpty {
                Text(note)
                    .font(Theme.body(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Theme.ink3)
                    .multilineTextAlignment(trailing ? .trailing : .leading)
            }
        }
    }

    @ViewBuilder private var badgeView: some View {
        switch badge {
        case .play:
            Text("Play \u{2192}")
                .font(Theme.body(14, .bold, relativeTo: .subheadline))
                .foregroundStyle(Theme.accentInk)
        case .progress:
            Text("In progress")
                .font(Theme.body(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.ink2)
        case .result(let tier, let label):
            let shape = RoundedRectangle(cornerRadius: 4)
            Text(label)
                .font(Theme.display(17, .bold, relativeTo: .headline))
                .foregroundStyle(foreground(tier))
                .lineLimit(1)
                .padding(.top, 5).padding(.bottom, 4).padding(.horizontal, 8)
                .frame(minWidth: 46)
                .background(fill(tier), in: shape)
                .overlay { if let ring = ring(tier) { shape.strokeBorder(ring, lineWidth: 1.5) } }
        }
    }

    private func foreground(_ tier: ResultsTier) -> Color {
        switch tier {
        case .eagle: Theme.onBrass
        case .birdie: Theme.brassInk
        case .par: Theme.paper
        case .over: Theme.ink
        case .x: Theme.bad
        }
    }

    private func fill(_ tier: ResultsTier) -> Color {
        switch tier {
        case .eagle: Theme.brassDeep
        case .birdie: Theme.brassSoft
        case .par: Theme.ink
        case .over, .x: .clear
        }
    }

    private func ring(_ tier: ResultsTier) -> Color? {
        switch tier {
        case .birdie: Theme.brass
        case .over: Theme.ink
        case .x: Theme.bad
        case .eagle, .par: nil
        }
    }
}

// MARK: - Data

/// One archive row, worked out the way the web's `renderArchive` does.
struct ArchiveEntry: Identifiable {
    enum Badge: Equatable {
        case result(ResultsTier, String)
        case progress
        case play
    }

    let puzzle: Puzzle
    let isToday: Bool
    let par: Int
    let badge: Badge
    /// "Daily · Hard", "Practice · Easy", the mode of today's game, or empty.
    let note: String

    var id: Int { puzzle.n }

    var badgeText: String {
        switch badge {
        case .result(_, let label): label
        case .progress: "In progress"
        case .play: "Play \u{2192}"
        }
    }

    var accessibilityLabel: String {
        "Puzzle \(puzzle.n), \(Format.date(puzzle.date, long: true)), par \(par)"
            + (puzzle.theme.map { ", \($0)" } ?? "") + ". \(badgeText)" + (note.isEmpty ? "" : " (\(note))")
    }

    /// Builds the rows for every playable puzzle, newest first.
    @MainActor static func load(_ app: AppModel) async -> [ArchiveEntry] {
        guard let engine = app.engine else { return [] }
        var out: [ArchiveEntry] = []
        for p in app.archive {
            let isToday = p.n == app.todayNumber
            let daily = await valid(Store.gameJSON(p.n, practice: false), for: p, engine: engine)
            let practice = await valid(Store.gameJSON(p.n, practice: true), for: p, engine: engine)
            let dailyDone = daily?.view.isOver ?? false
            var badge: Badge? = isToday || dailyDone ? await badgeFor(daily, engine) : nil
            var note = ""
            var shown: GameState?
            if let daily, dailyDone {
                note = noteFor("Daily", daily)
                shown = daily
            } else if !isToday, let practice, let practiceBadge = await badgeFor(practice, engine) {
                badge = practiceBadge
                note = noteFor("Practice", practice)
                shown = practice
            } else if isToday, badge != nil, let daily {
                note = daily.view.effectiveMode == .hard ? "Hard" : "Easy"
                shown = daily
            }
            let par: Int
            if let shown { par = shown.view.par }
            else { par = (try? await engine.parFor(p, mode: Store.preferredMode)) ?? p.par }
            out.append(ArchiveEntry(puzzle: p, isToday: isToday, par: par, badge: badge ?? .play, note: note))
        }
        return out
    }

    private static func noteFor(_ kind: String, _ state: GameState) -> String {
        "\(kind) \u{00B7} \(state.view.effectiveMode == .hard ? "Hard" : "Easy")"
    }

    /// The web's `badgeFor`: in progress once any move, miss or hint exists; else the score label.
    private static func badgeFor(_ state: GameState?, _ engine: CoreEngine) async -> Badge? {
        guard let state else { return nil }
        let v = state.view
        if !v.isOver { return v.chain.count > 1 || v.inc > 0 || v.hints > 0 ? .progress : nil }
        guard let score = try? await engine.score(state) else { return nil }
        return .result(ResultsTier(score), score.label)
    }

    /// The web's `validState`, for a saved game of this puzzle: same puzzle, same par.
    private static func valid(_ json: String?, for p: Puzzle, engine: CoreEngine) async -> GameState? {
        guard let json, let state = try? GameState(json: json) else { return nil }
        let v = state.view
        guard v.n == p.n, v.start == p.start, v.end == p.end, v.downs >= 0, v.chain.first == p.start,
              let par = try? await engine.parFor(p, mode: v.effectiveMode), par == v.par else { return nil }
        return state
    }
}

#if DEBUG
#Preview("Archive") {
    ArchiveScreen().environment(AppModel())
}
#endif
