import Foundation

/// Typed wrappers for the core functions the app calls (docs/spec.md, "Core API").
extension CoreEngine {
    // MARK: Players and teams

    func player(_ id: String) throws -> CorePlayer? {
        try call(CorePlayer?.self, "player", [.index, .value(id)])
    }

    func stintRanges(_ id: String) throws -> [StintRange] {
        try call([StintRange].self, "stintRanges", [.index, .value(id)])
    }

    /// "2015 Broncos"
    func teamLabel(_ team: String, _ season: Int) throws -> String {
        try call(String.self, "teamLabel", [.index, .value(team), .value(season)])
    }

    /// "Denver Broncos"
    func teamFullName(_ team: String, _ season: Int) throws -> String {
        try call(String.self, "teamFullName", [.index, .value(team), .value(season)])
    }

    func sharedTeams(_ a: String, _ b: String) throws -> [TeamSeason] {
        try call([TeamSeason].self, "sharedTeams", [.index, .value(a), .value(b)])
    }

    /// Ranked autocomplete: full-name prefix, then word prefix, then substring, then fame.
    func search(_ query: String, limit: Int = 8, exclude: [String] = []) throws -> [CorePlayer] {
        struct Options: Encodable { let limit: Int; let exclude: [String] }
        return try call([CorePlayer].self, "search", [.index, .value(query), .value(Options(limit: limit, exclude: exclude))])
    }

    struct PathResult: Codable, Hashable, Sendable {
        let dist: Int
        let path: [String]
        let links: [TeamSeason]
        let count: Int
    }

    func shortestPath(_ a: String, _ b: String) throws -> PathResult? {
        try call(PathResult?.self, "shortestPath", [.index, .value(a), .value(b)])
    }

    // MARK: Dates and puzzles

    /// Today's date in America/New_York, "YYYY-MM-DD".
    func easternDate(_ date: Date = .now) throws -> String {
        try evaluate("H.easternDate(new Date(\(Int64(date.timeIntervalSince1970 * 1000))))")
    }

    func puzzleNumber(puzzlesJSON: String, date ymd: String) throws -> Int {
        try call(Int.self, "puzzleNumberForDate", [.json(puzzlesJSON), .value(ymd)])
    }

    func parFor(_ puzzle: Puzzle, mode: GameMode) throws -> Int {
        try call(Int.self, "parFor", [.value(puzzle), .value(mode.rawValue)])
    }

    // MARK: Playing

    func newGame(_ puzzle: Puzzle, mode: GameMode) throws -> GameState {
        struct Options: Encodable { let mode: String }
        return try GameState(json: callJSON("newGame", [.value(puzzle), .value(Options(mode: mode.rawValue))]))
    }

    /// Returns the new state, and `nil` for `reason` when the switch was allowed.
    func setMode(_ state: GameState, to mode: GameMode) throws -> (state: GameState, refused: String?) {
        let text = try evaluate("JSON.stringify(H.setMode(JSON.parse(\(Self.quote(state.json))), \(Self.quote(mode.rawValue))))")
        let (stateJSON, object) = try Self.split(text, key: "state")
        let ok = object["ok"] as? Bool ?? false
        return (try GameState(json: stateJSON), ok ? nil : (object["reason"] as? String ?? "refused"))
    }

    func guess(_ state: GameState, playerID: String) throws -> (state: GameState, outcome: GuessOutcome) {
        let text = try evaluate("JSON.stringify(H.guess(__idx, JSON.parse(\(Self.quote(state.json))), \(Self.quote(playerID))))")
        let (stateJSON, object) = try Self.split(text, key: "state")
        let result = object["result"] as? [String: Any] ?? [:]
        let decode: (Any?) -> [TeamSeason] = { any in
            guard let any, let data = try? JSONSerialization.data(withJSONObject: any) else { return [] }
            return (try? JSONDecoder().decode([TeamSeason].self, from: data)) ?? []
        }
        let outcome: GuessOutcome
        switch result["kind"] as? String {
        case "link": outcome = .link(links: decode(result["links"]))
        case "solved": outcome = .solved(links: decode(result["links"]), final: decode(result["final"]))
        case "incompletion": outcome = .incompletion(downsLeft: result["downsLeft"] as? Int ?? 0)
        case "lost": outcome = .lost
        default:
            outcome = .rejected(reason: GuessOutcome.RejectReason(rawValue: result["reason"] as? String ?? "") ?? .unknown)
        }
        return (try GameState(json: stateJSON), outcome)
    }

    func undo(_ state: GameState) throws -> GameState {
        try GameState(json: callJSON("undo", [.json(state.json)]))
    }

    /// The hint, or the core's refusal ("last-down", "over", "none").
    func hint(_ state: GameState) throws -> (state: GameState, hint: Hint?, error: String?) {
        let text = try evaluate("JSON.stringify(H.hint(__idx, JSON.parse(\(Self.quote(state.json)))))")
        let (stateJSON, object) = try Self.split(text, key: "state")
        var hint: Hint?
        if let h = object["hint"], let data = try? JSONSerialization.data(withJSONObject: h) {
            hint = try? JSONDecoder().decode(Hint.self, from: data)
        }
        return (try GameState(json: stateJSON), hint, object["error"] as? String)
    }

    func score(_ state: GameState) throws -> Score {
        try call(Score.self, "score", [.json(state.json)])
    }

    func shareText(_ puzzle: Puzzle, _ state: GameState, options: ShareOptions) throws -> String {
        try call(String.self, "shareText", [.value(puzzle), .json(state.json), .value(options)])
    }

    // MARK: Stats

    func newStats() throws -> Stats {
        try Stats(json: callJSON("newStats", []))
    }

    /// Records a finished daily game. Archive and practice plays must not be recorded.
    func recordResult(_ stats: Stats, puzzleNumber n: Int, state: GameState) throws -> Stats {
        try Stats(json: callJSON("recordResult", [.json(stats.json), .value(n), .json(state.json)]))
    }

    func displayStreaks(_ stats: Stats, todayNumber: Int) throws -> Streaks {
        try call(Streaks.self, "displayStreaks", [.json(stats.json), .value(todayNumber)])
    }

    // MARK: Helpers

    /// A JavaScript string literal for `text`.
    static func quote(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// Splits `{state: {...}, ...rest}` into the state's own JSON text and the rest as an object.
    private static func split(_ text: String, key: String) throws -> (String, [String: Any]) {
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let inner = object[key] else {
            throw EngineError.undefinedResult(key)
        }
        let innerData = try JSONSerialization.data(withJSONObject: inner, options: [.sortedKeys])
        return (String(decoding: innerData, as: UTF8.self), object)
    }
}
