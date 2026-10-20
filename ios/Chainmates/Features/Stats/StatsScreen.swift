import SwiftUI

/// Statistics (web `#stats`): the summary tiles and the strokes-versus-par histogram, from the
/// stats the core keeps. Shown in the main column when `app.route == .stats`. It scrolls itself.
struct StatsScreen: View {
    @Environment(AppModel.self) private var app
    /// The bucket to highlight: today's result when today's daily is done, else the most common.
    @State private var todaysBucket: String?
    @State private var width: CGFloat = 0

    private static let wideBreakpoint: CGFloat = 900

    var body: some View {
        let wide = width >= Self.wideBreakpoint
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatsPageMasthead(title: "Statistics", subtitle: "Daily puzzles only, kept on this device.")
                if let stats = app.stats?.view, let streaks = app.streaks {
                    if wide {
                        HStack(alignment: .top, spacing: 40) {
                            summary(stats, streaks).frame(maxWidth: .infinity, alignment: .topLeading)
                            strokes(stats).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        summary(stats, streaks)
                        Rule().padding(.top, 2)
                        strokes(stats).padding(.top, 16)
                    }
                }
                backRow
            }
            .padding(.bottom, 28)
            .contentColumn(wide ? 1000 : Theme.columnMax)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paperBackground()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: app.stats) { await loadTodaysBucket() }
    }

    // MARK: Sections

    private func summary(_ stats: Stats.View, _ streaks: Streaks) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Summary")
            StatTiles(stats: stats, streaks: streaks, countDelay: 0.08)
        }
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    private func strokes(_ stats: Stats.View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Strokes vs par", detail: plural(stats.played, "daily game"))
            if let eagles = stats.hist["-2"], eagles > 0 {
                Text("\(Text(plural(eagles, "eagle")).fontWeight(.bold).foregroundStyle(Theme.brassInk)): the shortest chain, found on hard.")
                    .foregroundStyle(Theme.ink2)
                    .font(Theme.body(13.5, .regular, relativeTo: .footnote))
                    .padding(.top, -4)
                    .padding(.bottom, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if stats.played > 0 {
                StrokesHistogram(hist: stats.hist, highlight: todaysBucket)
            } else {
                Text("Finish a daily puzzle to start your record.")
                    .font(Theme.body(14, .regular, relativeTo: .callout))
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    private func sectionTitle(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(Theme.display(21, .bold, relativeTo: .title2))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(Theme.body(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(.bottom, 12)
    }

    private var backRow: some View {
        Button("Back to today's puzzle") { app.openToday() }
            .buttonStyle(.chain(.ink))
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
    }

    // MARK: Data

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    /// Today's finished daily marks its row; the web falls back to the most common bucket.
    private func loadTodaysBucket() async {
        todaysBucket = nil
        guard let engine = app.engine, let stats = app.stats?.view,
              stats.results[String(app.todayNumber)] != nil,
              let json = Store.gameJSON(app.todayNumber, practice: false),
              let state = try? GameState(json: json), state.view.isOver,
              let score = try? await engine.score(state) else { return }
        todaysBucket = score.won ? String(max(-2, min(3, score.over))) : "X"
    }
}

// MARK: - Histogram

/// Strokes versus par, one bar per result: grown from the left, counted inside the bar.
struct StrokesHistogram: View {
    let hist: [String: Int]
    /// The bucket key to fill with ink; `nil` highlights the most common one(s).
    let highlight: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var trackHeight: CGFloat = 26
    @State private var grown = false

    private struct Bucket: Identifiable {
        let key: String
        let name: String
        let spoken: String
        var id: String { key }
    }

    private let buckets = [
        Bucket(key: "-2", name: "Eagle", spoken: "Eagle or better"),
        Bucket(key: "-1", name: "Birdie", spoken: "Birdie"),
        Bucket(key: "0", name: "Par", spoken: "Par"),
        Bucket(key: "1", name: "+1", spoken: "Plus one"),
        Bucket(key: "2", name: "+2", spoken: "Plus two"),
        Bucket(key: "3", name: "+3", spoken: "Plus three or more"),
        Bucket(key: "X", name: "X", spoken: "X, turnover on downs"),
    ]

    var body: some View {
        let counts = buckets.map { hist[$0.key] ?? 0 }
        let maxCount = max(1, counts.max() ?? 1)
        VStack(spacing: 6) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { i, bucket in
                let count = counts[i]
                let on = highlight.map { $0 == bucket.key } ?? (count > 0 && count == maxCount)
                HStack(spacing: 10) {
                    Text(bucket.name)
                        .font(Theme.display(bucket.key == "-2" ? 17 : 16, .bold, relativeTo: .body))
                        .foregroundStyle(labelColor(bucket.key))
                        .frame(width: labelWidth, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Track(count: count, fraction: Double(count) / Double(maxCount), key: bucket.key, on: on,
                          index: i, grown: grown, reduceMotion: reduceMotion)
                        .frame(height: trackHeight)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(bucket.spoken): \(count) \(count == 1 ? "game" : "games")")
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear { grown = true }
    }

    private func labelColor(_ key: String) -> Color {
        switch key {
        case "-2", "-1": Theme.brassInk
        case "0": Theme.ink
        default: Theme.ink2
        }
    }

    private struct Track: View {
        let count: Int
        let fraction: Double
        let key: String
        let on: Bool
        let index: Int
        let grown: Bool
        let reduceMotion: Bool

        var body: some View {
            // Sized from the width the row offers, never from the bar itself: measuring the track
            // with the bar inside held it at its old width when the window narrowed (folding the
            // iPhone Duo), and the page overflowed.
            GeometryReader { g in
                track(barWidth: max(26, g.size.width * fraction))
            }
        }

        private func track(barWidth: CGFloat) -> some View {
            ZStack(alignment: .leading) {
                bar
                    .frame(width: barWidth)
                    .scaleEffect(x: grown || reduceMotion ? 1 : 0, anchor: .leading)
                    .opacity(grown || !reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? .linear(duration: 0.15)
                                            : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42).delay(Double(index) * 0.05 + 0.1), value: grown)
                Text(String(count))
                    .font(Theme.body(13, .bold, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .padding(.horizontal, 8)
                    .frame(width: barWidth, alignment: .trailing)
                    .opacity(grown ? 1 : 0)
                    .animation(reduceMotion ? .linear(duration: 0.15)
                                            : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26).delay(Double(index) * 0.05 + 0.36), value: grown)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }

        @ViewBuilder private var bar: some View {
            let shape = RoundedRectangle(cornerRadius: 3)
            switch key {
            case "-2":
                shape.fill(Theme.brassDeep)
                    .overlay { if on { shape.strokeBorder(Theme.ink, lineWidth: 2) } }
            case "-1":
                if on { shape.fill(Theme.brass) }
                else { shape.fill(Theme.brassSoft).overlay { shape.strokeBorder(Theme.brass, lineWidth: 1) } }
            default:
                if on { shape.fill(Theme.ink) }
                else { shape.fill(Theme.paper2).overlay { shape.strokeBorder(Theme.rule, lineWidth: 1) } }
            }
        }

        private var numberColor: Color {
            switch key {
            case "-2": Theme.onBrass
            case "-1": on ? Theme.onBrass : Theme.brassInk
            default: on ? Theme.paper : Theme.ink2
            }
        }
    }
}

#if DEBUG
#Preview("Statistics") {
    StatsScreen().environment(AppModel())
}
#endif
