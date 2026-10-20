import SwiftUI

/// The masthead (`.hero` in web/app.css): the kicker with the puzzle number, date and theme,
/// the Start and Finish players with the gap knot between them, then par and the Hard/Easy
/// switch, closed by the 2-point ink rule.
struct GameHero: View {
    @Environment(GameController.self) private var c
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.careerEntrance) private var careerEntrance
    @State private var width: CGFloat = 0
    @State private var intro = false

    private var roomy: Bool { width >= 560 }

    var body: some View {
        let pz = c.session.puzzle
        VStack(alignment: .leading, spacing: 0) {
            kicker(pz)
            matchup(pz)
                .padding(.top, roomy ? 22 : 16)
                .padding(.bottom, roomy ? 18 : 14)
                .opacity(intro ? 1 : 0)
                .offset(y: intro ? 0 : 8)
            HeroFoot()
                .padding(.top, 12)
                .overlay(alignment: .top) { Rule() }
                .opacity(intro ? 1 : 0)
                .offset(y: intro ? 0 : 8)
        }
        .padding(.top, roomy ? 22 : 16)
        .padding(.bottom, roomy ? 22 : 18)
        .overlay(alignment: .bottom) { Rule.masthead }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear {
            guard !intro else { return }
            if reduceMotion { withAnimation(.linear(duration: 0.15)) { intro = true } }
            else { withAnimation(Ease.out(0.36)) { intro = true } }
        }
    }

    // MARK: Kicker

    private func kicker(_ pz: Puzzle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    numberDate(pz)
                    Spacer(minLength: 0)
                    status
                }
                VStack(alignment: .leading, spacing: 4) {
                    numberDate(pz)
                    status
                }
            }
            if pz.theme != nil || pz.game != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        themeText(pz)
                        Spacer(minLength: 0)
                        if let g = pz.game { matchupChips(g) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        themeText(pz)
                        if let g = pz.game { matchupChips(g) }
                    }
                }
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rule() }
    }

    private func numberDate(_ pz: Puzzle) -> some View {
        var s = AttributedString("No. \(pz.n)")
        s.font = Theme.body(13, .bold, relativeTo: .footnote)
        s.foregroundColor = Theme.ink
        var rest = AttributedString(" · " + Format.dateLong(pz.date))
        rest.font = Theme.body(13, .medium, relativeTo: .footnote)
        rest.foregroundColor = Theme.ink2
        return Text(s + rest).monospacedDigit()
    }

    private var status: some View {
        Text(c.session.isPractice ? "Practice replay" : "Daily puzzle")
            .font(Theme.body(13, .bold, relativeTo: .footnote))
            .foregroundStyle(c.session.isPractice ? Theme.ink2 : Theme.accentInk)
    }

    @ViewBuilder private func themeText(_ pz: Puzzle) -> some View {
        if let t = pz.theme {
            Text(t)
                .font(Theme.body(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func matchupChips(_ g: PuzzleGame) -> some View {
        HStack(spacing: 6) {
            ClubChip(team: g.away, height: 20, minWidth: 34)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            Text("at")
                .font(Theme.body(12.5, .medium, relativeTo: .footnote))
                .italic()
                .foregroundStyle(Theme.ink3)
            ClubChip(team: g.home, height: 20, minWidth: 34)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clubName(g.away)) at \(clubName(g.home))")
    }

    private func clubName(_ code: String) -> String {
        guard let t = app.team(code) else { return code }
        return [t.city, t.name].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: Matchup

    @ViewBuilder private func matchup(_ pz: Puzzle) -> some View {
        let a = app.cachedPlayer(pz.start), b = app.cachedPlayer(pz.end)
        Group {
            // Stacked at accessibility text sizes, or when two cards side by side would be too
            // narrow for a name (under ~145 points each).
            if typeSize.isAccessibilitySize || (width > 0 && width < 330) {
                VStack(alignment: .leading, spacing: 14) {
                    HeroCard(player: a, id: pz.start, label: "Start", trailing: false, nameSize: 27)
                    GapKnot(vertical: false)
                    HeroCard(player: b, id: pz.end, label: "Finish", trailing: false, nameSize: 27)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    HeroCard(player: a, id: pz.start, label: "Start", trailing: false, nameSize: roomy ? 36 : 27)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GapKnot(vertical: true)
                        .frame(width: roomy ? 72 : 40)
                    HeroCard(player: b, id: pz.end, label: "Finish", trailing: true, nameSize: roomy ? 36 : 27)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Puzzle No. \(pz.n): connect \(a?.name ?? "") and \(b?.name ?? "") through teammates.")
        .accessibilityAddTraits(.isHeader)
    }
}

/// One side of the matchup: "Start" or "Finish", the name in Zilla Slab, `POS · years`, and the
/// career line in easy mode.
private struct HeroCard: View {
    let player: CorePlayer?
    let id: String
    let label: String
    let trailing: Bool
    let nameSize: CGFloat
    @Environment(GameController.self) private var c
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var cardWidth: CGFloat = 0

    /// The name's size, shrunk (to 60% at most) so its longest word fits the card: a name wraps
    /// between words, never inside one ("Matthe/w").
    private var fittedSize: CGFloat {
        guard let name = player?.name, cardWidth > 0 else { return nameSize }
        let longest = name.split(separator: " ").map {
            Fonts.width(of: String($0), family: .display, size: nameSize, weight: .bold, relativeTo: .title)
        }.max() ?? 0
        guard longest > cardWidth else { return nameSize }
        return max(nameSize * 0.6, (nameSize * cardWidth / longest * 0.97).rounded(.down))
    }

    var body: some View {
        _ = typeSize // re-measure when the text size changes
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
            Text(label)
                .font(Theme.body(12.5, .semibold, relativeTo: .caption))
                .foregroundStyle(Theme.ink3)
            Text(player?.name ?? " ")
                .font(Theme.display(fittedSize, .bold, relativeTo: .title))
                .tracking(-0.01 * fittedSize)
                .lineSpacing(-2)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(trailing ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let p = player {
                Text(Format.meta(p))
                    .font(Theme.body(13, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
            }
            if c.mode == .easy {
                CareerLine(playerID: id, trailing: trailing)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// The hero's centre: a hairline with a 30-point knot on it (it pops in with the hero).
private struct GapKnot: View {
    let vertical: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            if vertical {
                Rectangle().fill(Theme.rule).frame(width: 1).padding(.vertical, 4)
            } else {
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
            ZStack {
                Circle().fill(Theme.paper)
                Circle().strokeBorder(Theme.rule2, lineWidth: 1)
                LinkGlyph(size: 14, color: Theme.ink)
            }
            .frame(width: 30, height: 30)
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
        }
        .frame(maxHeight: vertical ? .infinity : 30)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.15) : Ease.spring.delay(0.12)) { shown = true }
        }
    }
}

/// Par, then the mode note and the Hard/Easy switch while playing, or "Played on hard".
private struct HeroFoot: View {
    @Environment(GameController.self) private var c

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { content }
            VStack(alignment: .leading, spacing: 10) { content }
        }
    }

    @ViewBuilder private var content: some View {
        ParBadge(par: c.view?.par ?? c.session.puzzle.par)
        if c.isPlaying {
            Text(c.mode == .hard ? "No teams shown" : "Every team shown")
                .font(Theme.body(13, relativeTo: .footnote))
                .foregroundStyle(Theme.ink2)
                .id(c.mode)
                .transition(.asymmetric(insertion: .offset(y: 6).combined(with: .opacity), removal: .identity))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            ModeSwitch()
        } else {
            Spacer(minLength: 0)
            RichText(["Played on ", "*" + c.mode.rawValue], size: 13, relativeTo: .footnote)
        }
    }
}

private struct ParBadge: View {
    let par: Int

    var body: some View {
        HStack(spacing: 0) {
            Text("Par ")
            Text("\(par)")
                .monospacedDigit()
                .id(par)
                .transition(.asymmetric(insertion: .offset(y: -8).combined(with: .scale(scale: 0.8)).combined(with: .opacity),
                                        removal: .identity))
        }
        .font(Theme.display(20, .bold, relativeTo: .title3))
        .foregroundStyle(Theme.ink)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(minWidth: 70, minHeight: 36)
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.ink, lineWidth: 1.5) }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Par \(par) links")
    }
}

/// The web's Hard/Easy control: a hairline frame on `card`, an ink block that slides under the
/// chosen word (and shakes "no" when hard can't start mid-game).
private struct ModeSwitch: View {
    @Environment(GameController.self) private var c
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let on = c.mode
        HStack(spacing: 0) {
            segment(.hard, "Hard", on)
            segment(.easy, "Easy", on)
        }
        .padding(3)
        .background(alignment: .leading) {
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.ink)
                    .frame(width: (g.size.width - 6) / 2, height: g.size.height - 6)
                    .offset(x: 3 + (on == .easy ? (g.size.width - 6) / 2 : 0), y: 3)
                    .animation(reduceMotion ? nil : Ease.spring, value: on)
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: c.nopeTick) { v, x in
                        v.offset(x: x)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(14, duration: 0.126)
                            CubicKeyframe(-4, duration: 0.126)
                            CubicKeyframe(2, duration: 0.084)
                            CubicKeyframe(0, duration: 0.084)
                        }
                    }
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: Theme.radiusS))
        .overlay { RoundedRectangle(cornerRadius: Theme.radiusS).strokeBorder(Theme.rule2, lineWidth: 1) }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Difficulty")
    }

    private func segment(_ m: GameMode, _ title: String, _ on: GameMode) -> some View {
        Button { c.requestMode(m) } label: {
            Text(title)
                .font(Theme.body(13.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(m == on ? Theme.paper : Theme.ink2)
                .padding(.horizontal, 12)
                .frame(minWidth: 56, minHeight: 30)
                .contentShape(.rect)
        }
        .buttonStyle(SegmentPress())
        .padding(.vertical, -4)
        .contentShape(.rect.inset(by: -7))
        .padding(.vertical, 4)
        .accessibilityAddTraits(m == on ? .isSelected : [])
        .accessibilityHint(m == .easy ? "Shows every player's teams and years" : "Shows no teams")
    }
}

private struct SegmentPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(Ease.out(0.18), value: configuration.isPressed)
    }
}
