import Foundation

// Swift mirrors of the JSON the core reads and returns (docs/spec.md). They're for display:
// game states go back into the core as the JSON it produced (`GameState.json`), never re-encoded
// from these structs.

struct TeamSeason: Codable, Hashable, Sendable {
    let team: String
    let season: Int
}

/// `{team, from, to}` from `stintRanges`.
struct StintRange: Codable, Hashable, Sendable {
    let team: String
    let from: Int
    let to: Int
}

/// `H.player(index, id)` and the rows of `H.search`.
struct CorePlayer: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let pos: String
    let fame: Int
    let stints: [TeamSeason]
    let first: Int?
    let last: Int?
}

/// A team from players.json's `teams` table.
struct TeamInfo: Codable, Hashable, Sendable {
    let name: String
    let city: String?
    let franchise: String?
    let c1: String
    let c2: String
    /// `[[from, to, name], ...]`: the nickname by season range (Washington).
    let names: [[NameRangePart]]?

    enum NameRangePart: Codable, Hashable, Sendable {
        case year(Int)
        case text(String)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Int.self) { self = .year(n) } else { self = .text(try c.decode(String.self)) }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .year(let n): try c.encode(n)
            case .text(let s): try c.encode(s)
            }
        }
    }
}

/// The featured prime-time game of a themed puzzle.
struct PuzzleGame: Codable, Hashable, Sendable {
    let slot: String
    let away: String
    let home: String
}

/// One entry of puzzles.json.
struct Puzzle: Codable, Hashable, Identifiable, Sendable {
    let n: Int
    let date: String
    let start: String
    let end: String
    let best: Int?
    let par: Int
    let kind: String?
    let theme: String?
    let chain: [String]?
    let optimal: Int?
    let game: PuzzleGame?
    /// The stored optimal chain's links: `links[i]` joins `chain[i]` and `chain[i + 1]`.
    var links: [PuzzleLink]? = nil

    var id: Int { n }
}

/// One `[team, season]` pair of a puzzle's stored `links`.
struct PuzzleLink: Codable, Hashable, Sendable {
    let team: String
    let season: Int

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        team = try c.decode(String.self)
        season = try c.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(team)
        try c.encode(season)
    }

    var teamSeason: TeamSeason { TeamSeason(team: team, season: season) }
}

struct PuzzlesFile: Codable, Sendable {
    let v: Int
    let epoch: String
    let tz: String?
    let puzzles: [Puzzle]
}

enum GameMode: String, Codable, CaseIterable, Sendable {
    case hard, easy
}

enum GameStatus: String, Codable, Sendable {
    case playing, won, lost
    var isWin: Bool { self == .won }
}

/// A game state as the core returns it. `json` is the source of truth and is what's saved and
/// passed back to the core; `view` is decoded from it for drawing.
struct GameState: Hashable, Sendable {
    let json: String
    let view: View

    struct View: Codable, Hashable, Sendable {
        let n: Int
        let start: String
        let end: String
        /// Missing in states saved before modes existed; those read as easy (spec, "Modes").
        let mode: GameMode?
        let par: Int
        let best: Int?
        let chain: [String]
        let downs: Int
        let inc: Int
        let hints: Int
        let hintAt: [String: Hint]
        let status: GameStatus
        /// The move list; only its length matters to the app (the web's `hasMoved`).
        let log: [LogEntry]?

        struct LogEntry: Codable, Hashable, Sendable {
            let t: String
        }

        var effectiveMode: GameMode { mode ?? .easy }
        var isOver: Bool { status != .playing }
        /// Links so far (`chain.length - 1`).
        var links: Int { chain.count - 1 }
        /// The player new guesses must connect to.
        var last: String { chain.last ?? start }
    }

    init(json: String) throws {
        self.json = json
        self.view = try JSONDecoder().decode(View.self, from: Data(json.utf8))
    }
}

/// `{team, season, pos}`: a hint names a team-season and a position, never a player.
struct Hint: Codable, Hashable, Sendable {
    let team: String
    let season: Int
    /// Missing on hints cached by an older version.
    let pos: String?
}

/// What a guess did (`result` of `H.guess`).
enum GuessOutcome: Hashable, Sendable {
    /// A new link; `links` are the team-seasons the two players shared.
    case link(links: [TeamSeason])
    /// The guess connected to the end player too. `final` is what links it to the end.
    case solved(links: [TeamSeason], final: [TeamSeason])
    case incompletion(downsLeft: Int)
    case lost
    case rejected(reason: RejectReason)

    enum RejectReason: String, Codable, Sendable {
        case unknown, inChain = "in-chain", start, end, over
    }
}

struct Score: Codable, Hashable, Sendable {
    let links: Int
    let par: Int
    let best: Int
    let over: Int
    /// "Eagle", "Birdie", "Par", "+1", "X", ...
    let label: String
    let won: Bool
    let mode: GameMode
}

/// Local stats (spec, "Stats"); kept as the core's JSON, like game states.
struct Stats: Hashable, Sendable {
    let json: String
    let view: View

    struct View: Codable, Hashable, Sendable {
        let played: Int
        let won: Int
        let cur: Int
        let max: Int
        let parCur: Int
        let parMax: Int
        let last: Int
        let lastWon: Int
        /// Keys "-2", "-1", "0", "1", "2", "3", "X".
        let hist: [String: Int]
        let results: [String: Result]

        struct Result: Codable, Hashable, Sendable {
            let links: Int
            let par: Int
            let inc: Int
            let hints: Int
            let won: Bool
            let mode: GameMode?
        }
    }

    init(json: String) throws {
        self.json = json
        self.view = try JSONDecoder().decode(View.self, from: Data(json.utf8))
    }
}

struct Streaks: Codable, Hashable, Sendable {
    let cur: Int
    let max: Int
    let parCur: Int
    let parMax: Int
}

/// The sport-specific words passed to `shareText` (web/sports.js).
struct ShareOptions: Codable, Hashable, Sendable {
    var url: String
    var title: String
    var emoji: String
    var miss: String
    var lost: String
    var hardLabel: String
}
