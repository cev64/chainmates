import SwiftUI

/// The results sheet for the game on screen (`app.session`): win, loss or practice replay.
/// The lead presents it as a `.sheet` when `app.sheet == .results`.
struct ResultsSheet: View {
    @Environment(AppModel.self) private var app
    /// Opens at full height, where the system sheet is opaque and the big score reads cleanly;
    /// it can be dragged down to look back at the chain.
    @State private var detent: PresentationDetent = .large

    var body: some View {
        NavigationStack {
            if let session = app.session {
                ResultsContent(session: session)
            } else {
                Theme.paper.ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
    }
}

// MARK: - Content

private struct ResultsContent: View {
    let session: GameSession
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: Loaded?
    @State private var appeared = false
    @State private var copiedAt = 0
    @State private var showCopied = false

    /// What the sheet asks the core for before it can draw.
    private struct Loaded {
        let share: String
        let optimal: Int
        let optimalLabel: String
        let optimalSteps: [ResultsMiniChain.Step]
    }

    var body: some View {
        let state = session.state?.view
        let score = session.score
        ScrollView {
            if let state, let score, let loaded {
                VStack(spacing: 0) {
                    hero(state: state, score: score, loaded: loaded)
                    VStack(spacing: 0) {
                        section(0, "Share", detail: "No spoilers") { shareSection(loaded.share) }
                        if session.isPractice {
                            Text("Practice replay of puzzle #\(session.puzzle.n). It doesn't count toward your stats or streaks.")
                                .font(Theme.body(14, .regular, relativeTo: .callout))
                                .foregroundStyle(Theme.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 16)
                                .overlay(alignment: .bottom) { Rule() }
                                .statsRise(appeared, delay: 0.25)
                        } else if let stats = app.stats?.view, let streaks = app.streaks {
                            section(1, "Your stats") { StatTiles(stats: stats, streaks: streaks, countDelay: 0.42) }
                        }
                        section(2, "Your chain", detail: score.links > 0 ? plural(score.links, "link") : "No links") {
                            ResultsMiniChain(steps: mySteps(state),
                                             brassFinish: ResultsTier(score).isUnderPar,
                                             lostFinishID: state.status == .lost ? state.end : nil,
                                             lostText: app.sport.lost)
                        }
                        section(3, "One optimal chain", detail: plural(loaded.optimal, "link")) {
                            VStack(alignment: .leading, spacing: 0) {
                                ResultsMiniChain(steps: loaded.optimalSteps, brassFinish: loaded.optimal < state.par)
                                Text(optimalNote(loaded, state: state))
                                    .font(Theme.body(13, .regular, relativeTo: .footnote))
                                    .foregroundStyle(Theme.ink2)
                                    .padding(.top, 10)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ResultsCountdown(session: session, dismiss: { dismiss() })
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                            .statsRise(appeared, delay: 0.2 + 0.05 * 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) { dismiss() }
            }
            if let share = loaded?.share {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: share) { Label("Share", systemImage: "square.and.arrow.up") }
                        .accessibilityLabel("Share result")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { toastBanner }
        .sensoryFeedback(.success, trigger: copiedAt)
        .task { await load() }
    }

    // MARK: Hero

    private func hero(state: GameState.View, score: Score, loaded: Loaded) -> some View {
        let tier = ResultsTier(score)
        let won = state.status == .won
        return VStack(spacing: 0) {
            Text(kicker(score))
                .font(Theme.body(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .statsRise(appeared, delay: 0.1)
            if tier == .eagle { ResultsEagleMark(snapped: appeared).padding(.top, 8) }
            ResultsScoreWord(label: score.label, tier: tier, shown: appeared)
            Text(headline(score: score, state: state, loaded: loaded))
                .font(Theme.display(21, .semibold, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .statsRise(appeared, delay: 0.16)
            Text(subline(score: score, state: state, won: won))
                .font(Theme.body(13.5, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
                .statsRise(appeared, delay: 0.2)
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .combine)
    }

    private func kicker(_ score: Score) -> AttributedString {
        var lead = AttributedString("\(app.sport.title) ")
        lead.foregroundColor = Theme.ink2
        var number = AttributedString("No. \(session.puzzle.n)")
        number.foregroundColor = Theme.ink
        number.font = Theme.body(13, .bold, relativeTo: .footnote)
        var rest = AttributedString(" \u{00B7} \(Format.date(session.puzzle.date)) \u{00B7} \(score.mode == .hard ? "Hard" : "Easy")"
                                    + (session.isPractice ? " \u{00B7} Practice" : ""))
        rest.foregroundColor = Theme.ink2
        return lead + number + rest
    }

    private func headline(score: Score, state: GameState.View, loaded: Loaded) -> String {
        guard score.won else { return app.sport.lost }
        let best = score.best
        let optimalLabel = loaded.optimalLabel.lowercased()
        let optimalUnder = loaded.optimal < state.par
        if score.links <= best {
            return Self.capitalised(Format.underText(score.over)) + ". "
                + (score.mode == .hard ? "The shortest chain there is, with no teams to go on." : "The shortest chain there is.")
        }
        if score.over < 0 {
            return Self.capitalised(Format.underText(score.over)) + ", one link off \(Self.article(optimalLabel))."
        }
        if score.over == 0 {
            if optimalUnder {
                let off = score.links - best
                return "Solved at par, \(Self.spareWord(off)) link\(off == 1 ? "" : "s") off \(Self.article(optimalLabel))."
            }
            return "Right on par, the shortest chain there is."
        }
        return "Solved, \(score.over) over par"
    }

    private func subline(score: Score, state: GameState.View, won: Bool) -> String {
        let miss = state.inc > 0 || !won ? plural(state.inc, app.sport.miss) : ""
        let hints = state.hints > 0 ? plural(state.hints, "hint") : ""
        if won {
            return [plural(score.links, "link") + " \u{00B7} Par \(state.par)",
                    score.links > score.best ? "shortest \(score.best)" : "",
                    state.inc > 0 ? miss : "", hints].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }
        return [miss, hints, "Par \(state.par)"].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private func optimalNote(_ loaded: Loaded, state: GameState.View) -> String {
        let count = session.puzzle.optimal ?? 1
        let head = count == 1 ? "Only 1 optimal chain exists" : "\(count.formatted(.number.locale(Locale(identifier: "en_US")))) optimal chains exist"
        guard loaded.optimal < state.par else { return head + "." }
        let mode = state.effectiveMode.rawValue
        let name = loaded.optimalLabel.lowercased()
        return count == 1 ? head + ". It's the only \(name) on \(mode)."
                          : head + ", and each one is \(Self.article(name)) on \(mode)."
    }

    // MARK: Sections

    private func section<Content: View>(_ index: Int, _ title: String, detail: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(Theme.display(18, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .font(Theme.body(13, .regular, relativeTo: .footnote))
                        .foregroundStyle(Theme.ink3)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rule() }
        .statsRise(appeared, delay: 0.2 + 0.05 * Double(index))
    }

    private func shareSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(Theme.body(14.5, .regular, relativeTo: .callout))
                .lineSpacing(4)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Theme.card, in: .rect(cornerRadius: Theme.radiusS))
                .overlay { RoundedRectangle(cornerRadius: Theme.radiusS).strokeBorder(Theme.rule, lineWidth: 1) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.chain(.primary, large: true, wide: true))
                Button { copy(text) } label: {
                    Label(showCopied ? "Copied!" : "Copy result", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.chain(.outline, large: true, wide: true))
            }
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copiedAt += 1
        app.showToast("Copied to clipboard", detail: "Paste it anywhere.")
        withAnimation(.easeOut(duration: 0.18)) { showCopied = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1800))
            withAnimation(.easeOut(duration: 0.18)) { showCopied = false }
        }
    }

    /// The app-level toast sits behind a sheet, so the sheet shows its own (the web does too).
    @ViewBuilder private var toastBanner: some View {
        if let toast = app.toast {
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.text).font(Theme.body(14, .medium, relativeTo: .subheadline))
                if let detail = toast.detail {
                    Text(detail).font(Theme.body(12.5, .regular, relativeTo: .caption)).opacity(0.72)
                }
            }
            .foregroundStyle(Theme.paper)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(maxWidth: 440, alignment: .leading)
            .background(Theme.ink, in: .rect(cornerRadius: Theme.radiusS))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            .id(toast.id)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Data

    private func mySteps(_ state: GameState.View) -> [ResultsMiniChain.Step] {
        state.chain.enumerated().map { i, id in
            ResultsMiniChain.Step(id: i, playerID: id, link: i > 0 && i - 1 < session.links.count ? session.links[i - 1].first : nil)
        }
    }

    private func load() async {
        guard loaded == nil, let engine = app.engine, let state = session.state?.view else { return }
        let puzzle = session.puzzle
        let ids = puzzle.chain ?? [puzzle.start, puzzle.end]
        await app.loadPlayers(ids + state.chain + [state.end])
        var links: [TeamSeason?] = []
        if let stored = puzzle.links, stored.count == ids.count - 1 {
            links = stored.map { $0.teamSeason }
        } else {
            for i in 0..<max(0, ids.count - 1) {
                links.append(((try? await engine.sharedTeams(ids[i], ids[i + 1])) ?? []).first)
            }
        }
        await app.loadLabels(links.compactMap { $0 })
        let steps = ids.enumerated().map { i, id in
            ResultsMiniChain.Step(id: i, playerID: id, link: i > 0 ? links[i - 1] : nil)
        }
        let optimal = ids.count - 1
        let label = await session.label(atLinks: optimal) ?? "Birdie"
        let share = await session.shareText() ?? ""
        loaded = Loaded(share: share, optimal: optimal, optimalLabel: label, optimalSteps: steps)
        // Let the first frame land, then bring the sections in.
        try? await Task.sleep(for: .milliseconds(30))
        appeared = true
    }

    // MARK: Helpers

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    private static func capitalised(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static func article(_ word: String) -> String {
        (word.first.map { "aeiou".contains($0.lowercased()) } ?? false ? "an " : "a ") + word
    }

    private static func spareWord(_ n: Int) -> String {
        let words = ["none", "one", "two", "three"]
        return n >= 0 && n < words.count ? words[n] : String(n)
    }
}

// MARK: - Score word

/// The big score: Zilla Slab 76 (88 for an eagle), springing in. A birdie draws a brass bar
/// under it, an eagle a double brass rule.
private struct ResultsScoreWord: View {
    let label: String
    let tier: ResultsTier
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(Theme.display(tier == .eagle ? 88 : 76, .bold, relativeTo: .largeTitle))
                .foregroundStyle(tier.scoreColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .scaleEffect(shown || reduceMotion ? 1 : 0.82)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? .linear(duration: 0.15)
                                        : .spring(response: 0.42, dampingFraction: 0.62).delay(tier == .eagle ? 0.22 : 0.1), value: shown)
            switch tier {
            case .birdie:
                RoundedRectangle(cornerRadius: 2).fill(Theme.brass)
                    .frame(width: 72, height: 4)
                    .padding(.top, 8).padding(.bottom, 4)
                    .scaleEffect(x: shown || reduceMotion ? 1 : 0)
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? .linear(duration: 0.15) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42).delay(0.38), value: shown)
                    .accessibilityHidden(true)
            case .eagle:
                VStack(spacing: 2) {
                    Rectangle().fill(Theme.brassDeep).frame(height: 2.5)
                    Rectangle().fill(Theme.brassDeep).frame(height: 2.5)
                }
                .frame(width: 112)
                .padding(.top, 16).padding(.bottom, 6)
                .scaleEffect(x: shown || reduceMotion ? 1 : 0)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? .linear(duration: 0.15) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42).delay(0.48), value: shown)
                .accessibilityHidden(true)
            default:
                EmptyView()
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

/// Two brass links that snap together above an eagle.
private struct ResultsEagleMark: View {
    let snapped: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let s: CGFloat = 58 / 80
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12 * s)
                .strokeBorder(Theme.brass, lineWidth: 4.5 * s)
                .frame(width: 38 * s, height: 24 * s)
                .offset(x: 6 * s + (snapped || reduceMotion ? 0 : -12), y: 8 * s)
            RoundedRectangle(cornerRadius: 12 * s)
                .strokeBorder(Theme.brassInk, lineWidth: 4.5 * s)
                .frame(width: 38 * s, height: 24 * s)
                .offset(x: 36 * s + (snapped || reduceMotion ? 0 : 12), y: 8 * s)
        }
        .frame(width: 58, height: 29, alignment: .topLeading)
        .opacity(snapped ? 1 : 0)
        .animation(reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.65).delay(0.08), value: snapped)
        .accessibilityHidden(true)
    }
}

// MARK: - Countdown

/// "Next puzzle in 05:12:44", ticking each second to the next Eastern midnight. At zero (or when
/// the game is an older daily whose day has passed) it becomes "A new puzzle is out" with "Play now".
private struct ResultsCountdown: View {
    let session: GameSession
    let dismiss: () -> Void
    @Environment(AppModel.self) private var app
    /// Captured once so the count doesn't jump back when the app moves its own rollover on.
    @State private var target: Date?

    var body: some View {
        let stale = session.isDaily && session.puzzle.n < app.todayNumber
        Group {
            if stale {
                newPuzzle
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = (target ?? app.nextRollover).timeIntervalSince(context.date)
                    if left <= 0 { newPuzzle } else { ticking(left) }
                }
            }
        }
        .onAppear { if target == nil { target = app.nextRollover } }
    }

    private func ticking(_ left: TimeInterval) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Next puzzle in")
                .font(Theme.body(14, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.ink2)
            Spacer(minLength: 0)
            Text(Format.countdown(left))
                .font(Theme.display(28, .semibold, relativeTo: .title))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.identity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next puzzle in \(Format.countdown(left))")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var newPuzzle: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("A new puzzle is out")
                .font(Theme.body(14, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.ink2)
            Spacer(minLength: 0)
            Button("Play now") {
                app.openToday()
                dismiss()
            }
            .buttonStyle(.chain(.primary))
        }
    }
}

#if DEBUG
#Preview("Results") {
    ResultsSheet().environment(AppModel())
}
#endif
