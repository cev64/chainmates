import SwiftUI

/// "Your chain" (`.chain-card` in web/app.css): flat on paper, no box. One row per placed
/// player joined by rails, the live "Next" link and any hint while playing, the finish, the
/// result once it's over, and the downs.
struct ChainSection: View {
    var showRuleNote = true
    @Environment(GameController.self) private var c
    @Environment(AppModel.self) private var app

    var body: some View {
        let rows = c.body
        VStack(alignment: .leading, spacing: 0) {
            heading
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element) { i, id in
                    StepRow(index: i, id: id, isLast: i == rows.count - 1, animateIn: c.entering == id)
                }
                if c.isPlaying {
                    LiveSlot()
                        .id("liveSlot")
                }
                TargetBlock(animateIn: c.targetEntering)
                    .id(c.isWon ? "won" : c.isLost ? "lost" : "playing")
            }
            .overlay { LockShimmer() }
            if !c.isPlaying, c.view != nil {
                ResultStrip()
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            DownsRow().id("downsRow")
            if showRuleNote { RuleNote().padding(.top, 12) }
        }
    }

    private var heading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                title
                Spacer(minLength: 0)
                meta
            }
            VStack(alignment: .leading, spacing: 4) { title; meta }
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var title: some View {
        Text("Your chain")
            .font(Theme.display(22, .bold, relativeTo: .title2))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private var meta: some View {
        let links = c.view?.links ?? 0
        return RichText(["*" + plural(links, "link"), " · Par \(c.view?.par ?? 0) · \(c.mode == .hard ? "Hard" : "Easy")"])
    }
}

/// The rule under the chain: what a teammate is while playing; practice is flagged after.
struct RuleNote: View {
    @Environment(GameController.self) private var c
    @Environment(AppModel.self) private var app

    var body: some View {
        let text = c.isPlaying
            ? "Teammates = \(app.sport.rule) (\(c.seasonsRange))."
            : c.session.isPractice ? "Practice replay: not counted in your stats." : ""
        if !text.isEmpty {
            Text(text)
                .font(Theme.body(12.5, relativeTo: .caption))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Steps

/// One placed player and the connector above it. A new one draws its rail down, pops its knot,
/// springs the player in, then slides the reason in; undo plays that backwards.
private struct StepRow: View {
    let index: Int
    let id: String
    let isLast: Bool
    let animateIn: Bool
    @Environment(GameController.self) private var c
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rail: CGFloat
    @State private var knot: CGFloat
    @State private var node: CGFloat
    @State private var reason: CGFloat

    init(index: Int, id: String, isLast: Bool, animateIn: Bool) {
        self.index = index
        self.id = id
        self.isLast = isLast
        self.animateIn = animateIn
        let v: CGFloat = animateIn ? 0 : 1
        _rail = State(initialValue: v)
        _knot = State(initialValue: v)
        _node = State(initialValue: v)
        _reason = State(initialValue: v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if index > 0 {
                ConnectorRow(shared: c.shared(index - 1), k: index, rail: rail, knot: knot, reason: reason)
            }
            NodeRow(id: id, kind: index == 0 ? .start : .mid, tag: index == 0 ? "Start" : nil, k: index,
                    above: index > 0 ? .solid : nil, below: belowStyle)
                .opacity(node)
                .offset(y: (1 - node) * -10)
                .scaleEffect(0.96 + 0.04 * node, anchor: .leading)
        }
        .onAppear {
            guard animateIn, node < 1 else { return }
            if reduceMotion {
                withAnimation(.linear(duration: 0.15)) { rail = 1; knot = 1; node = 1; reason = 1 }
                return
            }
            withAnimation(Ease.out(0.26)) { rail = 1 }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.6).delay(0.12)) { knot = 1 }
            withAnimation(Ease.spring.delay(0.1)) { node = 1 }
            withAnimation(Ease.out(0.26).delay(0.22)) { reason = 1 }
        }
        .onChange(of: c.retracting == id) { _, out in
            guard out else { return }
            withAnimation(Ease.in(0.18)) { node = 0 }
            withAnimation(Ease.in(0.12)) { reason = 0; knot = 0 }
            withAnimation(Ease.inOut(0.26).delay(0.08)) { rail = 0 }
        }
    }

    private var belowStyle: RailStyle? {
        guard isLast else { return .solid }
        if c.isPlaying { return .next }
        return c.isWon ? .solid : .pending
    }
}

/// A connector: the rail with its knot, and "Teammates on the 2015 Broncos" with the chip;
/// "+N more" opens the other team-seasons they shared.
struct ConnectorRow: View {
    let shared: [TeamSeason]
    let k: Int
    var rail: CGFloat = 1
    var knot: CGFloat = 1
    var reason: CGFloat = 1
    @Environment(GameController.self) private var c
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    var body: some View {
        let gild: CGFloat = c.isEagle && (c.gildAll || c.gildCount >= k) ? 1 : 0
        VStack(alignment: .leading, spacing: 6) {
            if let first = shared.first {
                FlowLayout(spacing: 10, lineSpacing: 4) {
                    HStack(spacing: 8) {
                        ClubChip(team: first.team, season: first.season)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        RichText(["Teammates on the ", "*" + app.teamLabel(first)], size: 13.5, boldWeight: .semibold,
                                 relativeTo: .subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Teammates on the \(app.teamLabel(first))")
                    if shared.count > 1 { moreButton }
                }
                if open {
                    FlowLayout(spacing: 12, lineSpacing: 4) {
                        ForEach(Array(shared.dropFirst().enumerated()), id: \.offset) { i, t in
                            MoreItem(team: t, index: i)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .opacity(reason)
        .offset(x: (1 - reason) * -6)
        .padding(.leading, 50)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(alignment: .leading) {
            ZStack {
                RailLine(style: .solid, progress: rail, gild: gild)
                    .frame(maxHeight: .infinity)
                RailKnot(color: gild > 0 ? Theme.brassDeep : Theme.ink, glyphColor: gild > 0 ? Theme.brassInk : Theme.ink)
                    .scaleEffect(0.6 + 0.4 * knot)
                    .opacity(knot)
                    .modifier(KnotTurn(k: k))
            }
            .frame(width: 36)
        }
    }

    private var moreButton: some View {
        Button {
            withAnimation(reduceMotion ? .linear(duration: 0.15) : Ease.out(0.26)) { open.toggle() }
        } label: {
            Text("+\(shared.count - 1) more")
                .font(Theme.body(12, .semibold, relativeTo: .caption))
                .foregroundStyle(open ? Theme.ink : Theme.ink2)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .background(open ? Theme.paper2 : .clear, in: .rect(cornerRadius: Theme.radiusS))
                .overlay { RoundedRectangle(cornerRadius: Theme.radiusS).strokeBorder(Theme.rule2, lineWidth: 1) }
                .contentShape(.rect.inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(shared.count - 1) more shared teams")
        .accessibilityValue(open ? "Expanded" : "Collapsed")
    }
}

private struct MoreItem: View {
    let team: TeamSeason
    let index: Int
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        HStack(spacing: 6) {
            ClubChip(team: team.team, season: team.season)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Text(app.teamLabel(team))
                .font(Theme.body(12.5, relativeTo: .caption))
                .foregroundStyle(Theme.ink2)
        }
        .opacity(shown ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.teamLabel(team))
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.15) : Ease.out(0.26).delay(Double(index) * 0.028)) { shown = true }
        }
    }
}

/// The knot's half-turn as the lock-up runs down the chain.
private struct KnotTurn: ViewModifier {
    let k: Int
    @Environment(GameController.self) private var c

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: c.lockTick) { v, angle in
            v.rotationEffect(.degrees(angle))
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0, duration: max(0.001, Double(k) * 0.08 - 0.04))
                CubicKeyframe(180, duration: 0.36)
            }
        }
    }
}

/// The lock-up's pulse: each node nudges right in turn, start to finish.
private struct LockPulse: ViewModifier {
    let k: Int
    @Environment(GameController.self) private var c

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: c.lockTick) { v, x in
            v.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0, duration: max(0.001, Double(k) * 0.08))
                SpringKeyframe(4, duration: 0.16, spring: .snappy)
                SpringKeyframe(0, duration: 0.2, spring: .smooth)
            }
        }
    }
}

// MARK: - Node

/// A player row: the 36-point dot on the rail, the name, `POS · years` (with a "Start" or
/// "Finish" tag), and the career line in easy mode.
struct NodeRow: View {
    let id: String
    let kind: NodeDot.Kind
    let tag: String?
    let k: Int
    var above: RailStyle?
    var below: RailStyle?
    @Environment(GameController.self) private var c

    var body: some View {
        let p = c.player(id)
        let ring: CGFloat = c.isEagle && (c.gildAll || c.ringCount > k) ? 1 : 0
        HStack(alignment: .center, spacing: 12) {
            NodeDot(kind: kind, pos: p?.pos ?? "", birdie: c.isBirdie, eagle: c.isEagle, ring: ring)
            VStack(alignment: .leading, spacing: 1) {
                Text(p?.name ?? "")
                    .font(Theme.body(16, .semibold, relativeTo: .body))
                    .foregroundStyle(kind == .ghost || kind == .lost ? Theme.ink2 : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let tag {
                        Text(tag).font(Theme.body(12.5, .semibold, relativeTo: .caption)).foregroundStyle(Theme.ink3)
                    }
                    if let p {
                        Text(Format.meta(p))
                            .font(Theme.body(12.5, relativeTo: .caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink2)
                    }
                }
                if c.mode == .easy {
                    CareerLine(playerID: id).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .background(alignment: .leading) {
            VStack(spacing: 0) {
                stub(above, gild: k)
                stub(below, gild: k + 1)
            }
            .frame(width: 36)
        }
        .modifier(LockPulse(k: k))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(kind == .target ? .isStaticText : [])
    }

    @ViewBuilder private func stub(_ style: RailStyle?, gild k: Int) -> some View {
        if let style {
            RailLine(style: style, gild: style == .solid && c.isEagle && (c.gildAll || c.gildCount >= k) ? 1 : 0)
                .frame(maxHeight: .infinity)
        } else {
            Color.clear.frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Live slot

/// While playing: the dashed accent "Next: a teammate of …" link, the red stub of a failed
/// guess snapping off it, and the hint for this spot.
private struct LiveSlot: View {
    @Environment(GameController.self) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RichText(["Next: a teammate of ", "*" + c.name(c.view?.last)], size: 13.5, boldWeight: .semibold,
                     relativeTo: .subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 50)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(alignment: .leading) {
                    ZStack {
                        RailLine(style: .next).frame(maxHeight: .infinity)
                        RailKnot(color: Theme.accent)
                    }
                    .frame(width: 36)
                }
                .opacity(c.nextHidden ? 0 : 1)
                .overlay {
                    if let name = c.failName { FailStub(name: name).id(c.failID) }
                }
            if let h = c.hint, let v = c.view {
                let key = "\(v.n):\(v.last)"
                HintPill(hint: h, reveal: c.hintRevealKey == key)
                    .id(key)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .padding(.leading, 50)
                    .background(alignment: .leading) {
                        RailLine(style: .pending).frame(width: 36).frame(maxHeight: .infinity)
                    }
                    .transition(.opacity)
            }
        }
    }
}

/// The failed connection: a red rail and knot with the struck-through name, snapping off and
/// falling away.
private struct FailStub: View {
    let name: String
    @State private var line: CGFloat = 0
    @State private var fall = false
    @State private var nameIn = false
    @State private var nameOut = false

    var body: some View {
        ZStack(alignment: .leading) {
            ZStack {
                RailLine(style: .bad, progress: line)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(x: 1, y: fall ? 0.4 : 1, anchor: .top)
                    .offset(y: fall ? 10 : 0)
                RailKnot(color: Theme.bad, cross: true)
                    .scaleEffect(line > 0 ? 1 : 0.6)
                    .rotationEffect(.degrees(fall ? -50 : 0))
                    .offset(y: fall ? 14 : 0)
            }
            .frame(width: 36)
            .opacity(fall ? 0 : 1)
            HStack(spacing: 6) {
                CrossGlyph(size: 12, color: Theme.bad)
                Text(name)
                    .font(Theme.body(13.5, .semibold, relativeTo: .subheadline))
                    .strikethrough(true, color: Theme.bad)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.bad)
            .padding(.leading, 50)
            .opacity(nameIn && !nameOut ? 1 : 0)
            .offset(x: nameIn ? 0 : -6, y: nameOut ? 8 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(Ease.out(0.2)) { line = 1 }
            withAnimation(Ease.out(0.18)) { nameIn = true }
            withAnimation(Ease.out(0.36).delay(0.44)) { fall = true }
            withAnimation(Ease.out(0.25).delay(0.75)) { nameOut = true }
        }
    }
}

// MARK: - Hint

/// The hint: a short line with the team as a ClubChip. On reveal the bulb lights and the words
/// slide in one after another; revisiting the spot just shows it.
struct HintPill: View {
    let hint: Hint
    let reveal: Bool
    @Environment(GameController.self) private var c
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bulb: CGFloat
    @State private var shown = false

    init(hint: Hint, reveal: Bool) {
        self.hint = hint
        self.reveal = reveal
        _bulb = State(initialValue: reveal ? 0 : 1)
    }

    var body: some View {
        let v = c.view
        let copy = app.sport.hintCopy(hint, puzzle: v?.n ?? 0, chainLength: v?.chain.count ?? 1)
        let label = app.teamLabel(TeamSeason(team: hint.team, season: hint.season))
        let (lead, tail) = splitLead(copy.after)
        let before = words(copy.before), after = words(tail)
        let animate = reveal && !reduceMotion
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Theme.card)
                Circle().strokeBorder(Theme.rule2, lineWidth: 1)
                Image(systemName: "lightbulb")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .keyframeAnimator(initialValue: BulbFrame(), trigger: shown && animate) { v, f in
                        v.rotationEffect(.degrees(f.angle)).scaleEffect(f.scale)
                    } keyframes: { _ in
                        KeyframeTrack(\.angle) {
                            LinearKeyframe(0, duration: 0.16)
                            CubicKeyframe(-14, duration: 0.245)
                            CubicKeyframe(6, duration: 0.245)
                            CubicKeyframe(0, duration: 0.21)
                        }
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(1, duration: 0.16)
                            CubicKeyframe(1.12, duration: 0.245)
                            CubicKeyframe(1, duration: 0.455)
                        }
                    }
            }
            .frame(width: 30, height: 30)
            .scaleEffect(0.6 + 0.4 * bulb)
            .opacity(bulb)
            FlowLayout(spacing: 4, lineSpacing: 2) {
                Text("Hint.")
                    .font(Theme.display(16, .bold, relativeTo: .callout))
                    .foregroundStyle(Theme.ink)
                    .modifier(WordIn(index: -1, delay: 0.1, on: animate))
                ForEach(Array(before.enumerated()), id: \.offset) { i, w in
                    word(w).modifier(WordIn(index: i, on: animate))
                }
                HStack(spacing: 5) {
                    ClubChip(team: hint.team, season: hint.season)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    Text(label + lead)
                        .font(Theme.body(14.5, .bold, relativeTo: .callout))
                        .foregroundStyle(Theme.ink)
                }
                .fixedSize()
                .modifier(WordIn(index: before.count, on: animate, land: true))
                ForEach(Array(after.enumerated()), id: \.offset) { i, w in
                    word(w).modifier(WordIn(index: before.count + 1 + i, on: animate))
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .background(Theme.paper2, in: .rect(cornerRadius: Theme.radiusS))
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hint. " + copy.before + label + copy.after)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.15) : Ease.out(0.26)) { shown = true }
            if animate { withAnimation(Ease.spring.delay(0.06)) { bulb = 1 } } else { bulb = 1 }
        }
    }

    private func word(_ w: String) -> some View {
        Text(w)
            .font(Theme.body(14.5, relativeTo: .callout))
            .foregroundStyle(Theme.ink)
    }

    private func words(_ s: String) -> [String] { s.split(whereSeparator: \.isWhitespace).map(String.init) }

    /// Punctuation right after the team ("…the {team}.") stays glued to it.
    private func splitLead(_ s: String) -> (String, String) {
        guard let first = s.first, !first.isWhitespace else { return ("", s) }
        let lead = s.prefix { !$0.isWhitespace }
        return (String(lead), String(s.dropFirst(lead.count)))
    }

    struct BulbFrame { var angle: Double = 0; var scale: Double = 1 }
}

/// A hint word sliding up into place (`wordIn`), or the team landing (`chipLand`).
private struct WordIn: ViewModifier {
    let index: Int
    var delay: Double? = nil
    let on: Bool
    var land = false
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(!on || shown ? 1 : 0)
            .offset(y: !on || shown ? 0 : (land ? -6 : 6))
            .scaleEffect(!on || shown || !land ? 1 : 0.9)
            .onAppear {
                guard on else { return }
                let d = delay ?? (0.18 + 0.032 * Double(index))
                withAnimation(land ? Ease.spring.delay(d) : Ease.out(0.26).delay(d)) { shown = true }
            }
    }
}

// MARK: - Target

/// The finish: still the goal (a dashed link to a dashed flag), lost (red), or reached (the
/// final link and a filled check, brass under par).
private struct TargetBlock: View {
    let animateIn: Bool
    @Environment(GameController.self) private var c
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rail: CGFloat
    @State private var knot: CGFloat
    @State private var node: CGFloat
    @State private var reason: CGFloat

    init(animateIn: Bool) {
        self.animateIn = animateIn
        let v: CGFloat = animateIn ? 0 : 1
        _rail = State(initialValue: v)
        _knot = State(initialValue: v)
        _node = State(initialValue: v)
        _reason = State(initialValue: v)
    }

    var body: some View {
        let end = c.view?.end ?? ""
        let k = c.body.count
        VStack(alignment: .leading, spacing: 0) {
            if c.isWon {
                ConnectorRow(shared: c.links.last ?? [], k: k, rail: rail, knot: knot, reason: reason)
                NodeRow(id: end, kind: .target, tag: "Finish", k: k, above: .solid)
                    .opacity(node)
                    .offset(y: (1 - node) * -10)
                    .scaleEffect(0.96 + 0.04 * node, anchor: .leading)
            } else {
                RailLine(style: .pending)
                    .frame(width: 36, height: 26)
                    .accessibilityHidden(true)
                NodeRow(id: end, kind: c.isLost ? .lost : .ghost, tag: "Finish", k: k, above: .pending)
            }
        }
        .padding(.bottom, 8)
        .onAppear {
            guard animateIn, node < 1 else { return }
            if reduceMotion {
                withAnimation(.linear(duration: 0.15)) { rail = 1; knot = 1; node = 1; reason = 1 }
                return
            }
            withAnimation(Ease.out(0.26)) { rail = 1 }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.6).delay(0.12)) { knot = 1 }
            withAnimation(Ease.spring.delay(0.1)) { node = 1 }
            withAnimation(Ease.out(0.26).delay(0.22)) { reason = 1 }
        }
    }
}

// MARK: - Shimmer

/// The one shimmer in the product: a single brass sweep across the chain at an under-par solve.
private struct LockShimmer: View {
    @Environment(GameController.self) private var c

    var body: some View {
        GeometryReader { g in
            let w = g.size.width + 16
            let band = w * 0.14
            LinearGradient(colors: [.clear, Color(red: 226 / 255, green: 179 / 255, blue: 60 / 255, opacity: 0.32), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: band, height: g.size.height * 1.2)
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: tan(-18 * .pi / 180), d: 1, tx: 0, ty: 0))
                .keyframeAnimator(initialValue: Sweep(), trigger: c.shimmerTick) { v, f in
                    v.offset(x: -0.2 * w + f.x * band * 9.5, y: -g.size.height * 0.1).opacity(f.opacity)
                } keyframes: { _ in
                    let d = c.shimmerDuration
                    KeyframeTrack(\.x) {
                        LinearKeyframe(0, duration: max(0.001, c.shimmerDelay))
                        CubicKeyframe(1, duration: d)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: max(0.001, c.shimmerDelay))
                        LinearKeyframe(1, duration: d * 0.15)
                        LinearKeyframe(1, duration: d * 0.7)
                        LinearKeyframe(0, duration: d * 0.15)
                    }
                }
        }
        .padding(.horizontal, -8)
        .clipShape(.rect(cornerRadius: Theme.radiusM))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    struct Sweep { var x: CGFloat = 0; var opacity: Double = 0 }
}

// MARK: - Result strip

/// After the game: the score word (brass under par, red for a turnover) and how it went; a past
/// daily offers a practice replay.
private struct ResultStrip: View {
    @Environment(GameController.self) private var c
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grow: CGFloat = 0

    var body: some View {
        let replay = c.session.isDaily && c.session.puzzle.n != app.todayNumber
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                summary
                Spacer(minLength: 0)
                if replay { replayButton }
            }
            VStack(alignment: .leading, spacing: 12) {
                summary
                if replay { replayButton }
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .overlay(alignment: .top) { Rule() }
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.15) : Ease.out(0.42).delay(0.26)) { grow = 1 }
        }
    }

    private var summary: some View {
        let won = c.isWon
        let sc = c.score
        let over = sc?.over ?? 0
        let word = won ? (sc?.label ?? "") : app.sport.lost
        let color: Color = !won ? Theme.bad : over < 0 ? Theme.brassInk : Theme.ink
        let par = c.view?.par ?? 0
        let parOn = "Par \(par) on \(c.mode.rawValue)"
        let line: String = {
            guard let v = c.view else { return "" }
            if !won { return plural(v.inc, app.sport.miss) + " · " + parOn }
            var s = "Solved in " + plural(sc?.links ?? v.links, "link") + " · " + parOn
            if over < 0 { s += " · " + Format.underText(over) }
            else if let sc, sc.links > sc.best { s += " · shortest is \(sc.best)" }
            return s
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Text(word)
                .font(Theme.display(30, .bold, relativeTo: .title))
                .foregroundStyle(color)
                .fixedSize()
                .overlay(alignment: .bottom) {
                    if won, over <= -2 {
                        Rectangle().fill(.clear)
                            .frame(height: 5)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.brassDeep).frame(height: 2) }
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.brassDeep).frame(height: 2) }
                            .scaleEffect(x: grow, anchor: .leading)
                            .offset(y: 7)
                    } else if won, over < 0 {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.brass)
                            .frame(height: 3)
                            .scaleEffect(x: grow, anchor: .leading)
                            .offset(y: 5)
                    }
                }
                .padding(.bottom, won && over < 0 ? 6 : 0)
            Text(line)
                .font(Theme.body(13, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var replayButton: some View {
        Button("Replay as practice") { app.practice(c.session.puzzle.n) }
            .buttonStyle(.chain())
    }
}

// MARK: - Downs

/// "Downs" and three squares: solid while left, hollow once spent (a red flash drains it), and
/// red when only one is left.
private struct DownsRow: View {
    @Environment(GameController.self) private var c

    var body: some View {
        let downs = c.view?.downs ?? c.totalDowns
        let total = c.totalDowns
        HStack(spacing: 6) {
            Text(cap(c.app.sport.lives))
                .font(Theme.body(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.ink2)
                .padding(.trailing, 4)
            ForEach(0..<total, id: \.self) { i in
                DownSquare(used: i >= downs, danger: c.isPlaying && downs == 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { Rule() }
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plural(downs, c.app.sport.life, c.app.sport.lives)) left of \(total)")
        .accessibilityAddTraits(.isImage)
    }
}

private struct DownSquare: View {
    let used: Bool
    let danger: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(used ? Color.clear : danger ? Theme.bad : Theme.ink)
            .overlay {
                if used { RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.rule2, lineWidth: 1.5) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2).fill(Theme.bad)
                    .scaleEffect(0.3 + 0.95 * flash)
                    .opacity(flash)
            }
            .frame(width: 13, height: 13)
            .animation(Ease.out(0.18), value: danger)
            .onChange(of: used) { was, now in
                guard now, !was, !reduceMotion else { return }
                flash = 1
                withAnimation(Ease.in(0.36)) { flash = 0 }
            }
    }
}
