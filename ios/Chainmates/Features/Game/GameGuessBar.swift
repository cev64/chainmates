import SwiftUI

/// The guess bar at the bottom of the chain (it goes in `.safeAreaBar(edge: .bottom)`): a glass
/// field with a round submit button, and the matching players on a solid card right above it,
/// so they rise with the keyboard. Once the game is over it holds "See results".
struct GuessBar: View {
    /// The tallest the suggestions may grow (what's left of the screen above the bar).
    let listMax: CGFloat
    @Environment(GameController.self) private var c
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if c.isPlaying {
                if c.listOpen {
                    SuggestionList(maxHeight: listMax)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
                }
                field
            } else if c.view != nil {
                Button { app.sheet = .results } label: {
                    Text("See results")
                        .font(Theme.body(15.5, .bold, relativeTo: .body))
                        .foregroundStyle(Theme.paper)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.ink)
                .controlSize(.large)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: Theme.columnMax + 2 * Theme.gutter)
        .frame(maxWidth: .infinity)
        .task(id: c.query) {
            guard c.isPlaying else { return }
            if c.query.trimmingCharacters(in: .whitespaces).isEmpty { c.closeList(); return }
            try? await Task.sleep(for: AppConfig.searchDebounce)
            guard !Task.isCancelled else { return }
            await c.runSearch()
        }
        .onChange(of: focused) { _, now in
            c.fieldFocused = now
            if now, !c.listOpen, !c.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Task { await c.runSearch() }
            }
        }
        .onChange(of: c.blurTick) { focused = false }
        .onChange(of: c.focusTick) { if sizeClass == .regular { focused = true } }
        #if DEBUG
        .onAppear { if GameDebug.focusField { focused = true } }
        #endif
    }

    // MARK: Field

    private var field: some View {
        @Bindable var c = c
        let empty = c.query.trimmingCharacters(in: .whitespaces).isEmpty
        let still = reduceMotion
        return GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(focused ? Theme.accentInk : Theme.ink3)
                        .accessibilityHidden(true)
                    TextField(text: $c.query, prompt: Text("Add a teammate\u{2026}").foregroundStyle(Theme.ink3)) {
                        Text("Add a teammate")
                    }
                    .font(Theme.body(16, .medium, relativeTo: .body))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.accent)
                    .focused($focused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        focused = true
                        Task { await c.submit() }
                    }
                    .onKeyPress(.downArrow) { c.moveHighlight(1); return .handled }
                    .onKeyPress(.upArrow) { c.moveHighlight(-1); return .handled }
                    .onKeyPress(.escape) {
                        if c.listOpen { c.closeList() } else if !c.query.isEmpty { c.clearGuess() }
                        return .handled
                    }
                    .onKeyPress(.tab) { c.closeList(); return .ignored }
                    .accessibilityHint("Type a name, then pick a player from the list")
                    if !c.query.isEmpty {
                        Button { c.clearGuess(); focused = true } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.ink2)
                                .frame(width: 32, height: 32)
                                .contentShape(.rect.inset(by: -6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .frame(minHeight: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(c.missFlash ? Theme.bad : focused ? Theme.accent : .clear, lineWidth: 1.5)
                        .animation(Ease.out(0.18), value: focused)
                }
                .overlay {
                    if c.missFlash {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Theme.bad.opacity(0.07))
                            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.bad, lineWidth: 2) }
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .keyframeAnimator(initialValue: CGFloat(0), trigger: c.missTick) { v, x in
                    v.offset(x: still ? 0 : x)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(-7, duration: 0.065)
                        CubicKeyframe(6, duration: 0.072)
                        CubicKeyframe(-4, duration: 0.072)
                        CubicKeyframe(2, duration: 0.072)
                        CubicKeyframe(0, duration: 0.079)
                    }
                }
                .onTapGesture { focused = true }

                Button {
                    focused = true
                    Task { await c.submit() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.accent)
                .disabled(empty)
                .accessibilityLabel("Link")
                .accessibilityHint("Guesses the highlighted player")
            }
        }
    }
}

// MARK: - Suggestions

/// Up to 8 players, best first, on a solid card (content, not glass): the typed part of the
/// name in bold, a "Finish" tag on the end player, `POS · years`, and in easy mode the career
/// line. One highlight glides between rows.
private struct SuggestionList: View {
    let maxHeight: CGFloat
    @Environment(GameController.self) private var c
    @Environment(\.colorScheme) private var scheme
    @State private var contentHeight: CGFloat = 0
    @Namespace private var ns

    var body: some View {
        let lift = Theme.lift(scheme)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if c.results.isEmpty {
                        Text(c.emptyText ?? "")
                            .font(Theme.body(13.5, relativeTo: .subheadline))
                            .foregroundStyle(Theme.ink2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(c.results.enumerated()), id: \.element.id) { i, p in
                            SuggestionRow(player: p, index: i, active: i == c.active, ns: ns)
                                .id(i)
                        }
                    }
                }
                .padding(4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 1), maxHeight))
            .onChange(of: c.active) { _, i in
                guard i >= 0 else { return }
                proxy.scrollTo(i)
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusS))
        .overlay { RoundedRectangle(cornerRadius: Theme.radiusS).strokeBorder(Theme.rule2, lineWidth: 1) }
        .shadow(color: lift.color, radius: lift.radius, y: lift.y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Matching players")
    }
}

private struct SuggestionRow: View {
    let player: CorePlayer
    let index: Int
    let active: Bool
    let ns: Namespace.ID
    @Environment(GameController.self) private var c
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let isEnd = player.id == c.view?.end
        Button { c.pick(player) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(highlighted)
                        .lineLimit(1)
                    if isEnd {
                        Text("Finish")
                            .font(Theme.body(12, .bold, relativeTo: .caption))
                            .foregroundStyle(Theme.accentInk)
                    }
                }
                Text(Format.meta(player))
                    .font(Theme.body(12.5, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                if c.mode == .easy {
                    CareerLine(playerID: player.id, max: 4).padding(.top, 3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.accent.opacity(0.11))
                        .matchedGeometryEffect(id: "highlight", in: ns)
                }
            }
            .overlay(alignment: .top) {
                if index > 0 { Rule().padding(.horizontal, 10) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { c.hover(index) } }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 6)
        .onAppear {
            if c.listFresh, !reduceMotion {
                withAnimation(Ease.out(0.26).delay(Double(index) * 0.028)) { shown = true }
            } else { shown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([player.name, Format.meta(player), isEnd ? "Finish" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Guesses this player")
    }

    /// The typed text in bold where it literally appears in the name (no bold for accent or
    /// punctuation differences, like the web).
    private var highlighted: AttributedString {
        var s = AttributedString(player.name)
        s.font = Theme.body(15.5, .medium, relativeTo: .body)
        s.foregroundColor = Theme.ink
        let q = c.searchedQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, let r = player.name.range(of: q, options: .caseInsensitive),
           let lo = AttributedString.Index(r.lowerBound, within: s), let hi = AttributedString.Index(r.upperBound, within: s) {
            s[lo..<hi].font = Theme.body(15.5, .bold, relativeTo: .body)
        }
        return s
    }
}
