import SwiftUI

/// The game page: draws `app.session` (nothing when there's no puzzle; the shell shows the
/// status view then). Host it in a `NavigationStack`: it adds Undo and Hint to the toolbar.
///
/// Compact width, regular in portrait, or a window too narrow for two panes: one 640-point
/// column (masthead, then the chain) with the guess bar at the bottom. A wide landscape regular
/// window: two panes, the masthead and rules beside the chain and its guess bar, aligned to the
/// Duo's fold on iOS 27.1.
struct GameScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let session = app.session {
            GameBoard(session: session, app: app)
                .id(ObjectIdentifier(session))
        }
    }
}

private struct GameBoard: View {
    let session: GameSession
    @State private var c: GameController
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size: CGSize = .zero
    @State private var visibleHeight: CGFloat = 600

    init(session: GameSession, app: AppModel) {
        self.session = session
        _c = State(initialValue: GameController(session: session, app: app))
    }

    /// Two panes need room for both: a landscape regular window at least 860 points wide (iPad,
    /// the unfolded iPhone Duo with its tabs at the top). Narrower, such as the Duo with the
    /// sidebar open, keeps the site's single column rather than squeezing two.
    private var wide: Bool { sizeClass == .regular && size.width > size.height && size.width >= 860 }
    private var listMax: CGFloat { min(420, max(120, min(visibleHeight * 0.62, visibleHeight - 160))) }

    var body: some View {
        @Bindable var c = c
        Group {
            if c.view != nil {
                if wide { WideGame(listMax: listMax) } else { CompactGame(listMax: listMax) }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height - $0.safeAreaInsets.top - $0.safeAreaInsets.bottom } action: {
            visibleHeight = $0
        }
        .environment(c)
        .environment(\.careerEntrance, c.careerEntrance)
        .environment(\.careerFolding, c.careerFolding)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward") { c.undo() }
                    .disabled(!c.canUndo)
                    .accessibilityHint("Removes the last link. Undo is free.")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(c.hintCached ? "Hint shown" : "Hint", systemImage: c.hintCached ? "lightbulb.fill" : "lightbulb") {
                    c.requestHint()
                }
                .disabled(!c.isPlaying)
                .accessibilityHint(hintHint)
            }
        }
        .alert("Use a hint?", isPresented: $c.confirmHint) {
            Button("Not now", role: .cancel) {}
            Button("Show hint") { c.buyHint() }
        } message: {
            Text(c.hintMessage())
        }
        .alert("Switch to easy?", isPresented: $c.confirmEasy) {
            Button("Stay on hard", role: .cancel) {}
            Button("Switch to easy") { c.applyMode(.easy) }
        } message: {
            Text(c.easyMessage())
        }
        .sensoryFeedback(.impact(weight: .light), trigger: c.linkTick)
        .sensoryFeedback(.success, trigger: c.solveTick)
        .sensoryFeedback(.error, trigger: c.missTick)
        .sensoryFeedback(.selection, trigger: c.undoTick)
        .onAppear {
            c.reduceMotion = reduceMotion
            c.sync()
        }
        .onChange(of: reduceMotion) { _, v in c.reduceMotion = v }
        .onChange(of: session.state) { c.sync() }
        .onChange(of: session.lastEvent) { _, e in if let e { c.handle(e) } }
    }

    private var hintHint: String {
        guard let v = c.view, c.isPlaying else { return "" }
        if c.hintCached { return "The hint for this spot is shown in the chain" }
        if v.downs <= 1 { return "No hints on your last \(app.sport.life)" }
        return "Costs one \(app.sport.life)"
    }
}

// MARK: - Layouts

/// One column: the masthead and the chain scroll; the guess bar stays at the bottom.
private struct CompactGame: View {
    let listMax: CGFloat
    @Environment(GameController.self) private var c

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GameHero()
                    ChainSection()
                }
                .padding(.bottom, 20)
                .contentColumn()
                .contentShape(.rect)
                .onTapGesture { c.closeList() }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom) { GuessBar(listMax: listMax) }
            .modifier(RevealLiveEnd(proxy: proxy))
        }
    }
}

/// Two panes for a wide landscape regular window (iPad, the unfolded Duo): the masthead and the
/// rule on the left, the chain and its guess bar on the right; each scrolls itself.
private struct WideGame: View {
    let listMax: CGFloat

    var body: some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            // The masthead reads first on the left page, the chain on the right page beside
            // the hand that types.
            ArrangementView {
                HeroPane()
            } secondary: {
                ChainPane(listMax: listMax)
            }
            .arrangementViewStyle(.split.axes(.horizontal))
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                HeroPane()
                    .frame(width: min(520, max(340, g.size.width * 0.42)))
                Rectangle().fill(Theme.rule).frame(width: 1).ignoresSafeArea(edges: .bottom)
                ChainPane(listMax: listMax)
            }
        }
    }
}

private struct HeroPane: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GameHero()
                RuleNote().padding(.top, 14)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ChainPane: View {
    let listMax: CGFloat
    @Environment(GameController.self) private var c

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ChainSection(showRuleNote: false)
                    .frame(maxWidth: Theme.columnMax, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .onTapGesture { c.closeList() }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom) { GuessBar(listMax: listMax) }
            .modifier(RevealLiveEnd(proxy: proxy))
        }
    }
}

/// After a link (or a tap on "Hint shown") the chain scrolls so its live end sits just above the
/// guess bar; after the game, so the result does.
private struct RevealLiveEnd: ViewModifier {
    let proxy: ScrollViewProxy
    @Environment(GameController.self) private var c
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onChange(of: c.revealTick) {
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(reduceMotion ? nil : Ease.out(0.36)) {
                    proxy.scrollTo(c.isPlaying ? "liveSlot" : "downsRow", anchor: .bottom)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Game") {
    GameDebugRoot()
}
#endif
