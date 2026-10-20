import SwiftUI

/// How a finished game is shown: the tier decides colour and decoration (web `tierOf`).
enum ResultsTier {
    case eagle, birdie, par, over, x

    init(_ score: Score) {
        if !score.won { self = .x }
        else if score.over <= -2 { self = .eagle }
        else if score.over < 0 { self = .birdie }
        else if score.over == 0 { self = .par }
        else { self = .over }
    }

    /// The big score word's colour.
    var scoreColor: Color {
        switch self {
        case .eagle, .birdie: Theme.brassInk
        case .par, .over: Theme.ink
        case .x: Theme.bad
        }
    }

    var isUnderPar: Bool { self == .eagle || self == .birdie }
}

/// The compact chain lists of the results sheet ("Your chain", "One optimal chain"): a small
/// dot and name per player, and between players a rail with the team-season that joins them.
struct ResultsMiniChain: View {
    struct Step: Identifiable {
        let id: Int
        let playerID: String
        /// What joins this player to the one before.
        let link: TeamSeason?
    }

    let steps: [Step]
    /// The finish player gets a brass dot on an under-par chain.
    var brassFinish = false
    /// A lost game: after the last player, a red "Turnover on downs" link and the finish player.
    var lostFinishID: String?
    var lostText = ""

    @Environment(AppModel.self) private var app
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                if i > 0, let link = step.link { linkRow(link) }
                else if i > 0 { gapRow }
                playerRow(step.playerID, kind: i == 0 ? .start : (lostFinishID == nil && i == steps.count - 1 ? .finish : .middle))
            }
            if let lostFinishID {
                missRow
                playerRow(lostFinishID, kind: .finishLost)
            }
        }
    }

    private enum Kind { case start, middle, finish, finishLost }

    private func playerRow(_ id: String, kind: Kind) -> some View {
        let player = app.cachedPlayer(id)
        let abbreviation = String((player?.pos ?? "").prefix(3))
        let brass = kind == .finish && brassFinish
        return HStack(spacing: 10) {
            Text(abbreviation.isEmpty ? "\u{2022}" : abbreviation)
                .font(Theme.body(8, .bold, relativeTo: .caption2))
                .foregroundStyle(kind == .middle ? Theme.ink : (brass ? Theme.onBrass : Theme.paper))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: dot, height: dot)
                .background(kind == .middle ? Theme.paper : (brass ? Theme.brass : Theme.ink), in: .circle)
                .overlay { Circle().strokeBorder(kind == .middle ? Theme.ink : (brass ? Theme.brass : Theme.ink), lineWidth: 1.5) }
                .accessibilityHidden(true)
            Text(player?.name ?? "")
                .font(Theme.body(14.5, .semibold, relativeTo: .callout))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player?.name ?? "")\(kind == .start ? ", start" : (kind == .finish || kind == .finishLost ? ", finish" : ""))")
    }

    private func linkRow(_ link: TeamSeason) -> some View {
        HStack(spacing: 8) {
            ClubChip(team: link.team, season: link.season)
            Text("Teammates on the \(app.teamLabel(link))")
                .font(Theme.body(12.5, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, dot + 10)
        .frame(minHeight: 28)
        .overlay(alignment: .leading) { rail(color: Theme.ink, dashed: false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Teammates on the \(app.teamLabel(link))")
    }

    /// A link with no known team (a saved game from older data): just the rail.
    private var gapRow: some View {
        Color.clear.frame(height: 14)
            .overlay(alignment: .leading) { rail(color: Theme.ink, dashed: false) }
            .accessibilityHidden(true)
    }

    private var missRow: some View {
        HStack {
            Text(lostText)
                .font(Theme.body(12.5, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.bad)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, dot + 10)
        .frame(minHeight: 28)
        .overlay(alignment: .leading) { rail(color: Theme.bad, dashed: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lostText)
    }

    /// The 2-point vertical rail through the dot column, reaching 4 points past the row to meet the dots.
    private func rail(color: Color, dashed: Bool) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 2)
            .overlay {
                GeometryReader { proxy in
                    Path { p in
                        p.move(to: CGPoint(x: 1, y: 0))
                        p.addLine(to: CGPoint(x: 1, y: proxy.size.height))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 4] : []))
                }
            }
            .padding(.vertical, -4)
            .padding(.leading, dot / 2 - 1)
    }
}
