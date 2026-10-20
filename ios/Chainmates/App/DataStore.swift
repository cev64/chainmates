import Foundation

/// players.json and puzzles.json: the copy shipped in the app, or a newer copy from the site.
///
/// The daily data bot can re-pick *future* puzzles (a flexed prime-time game), so the app checks
/// the site for fresh data after launch and keeps it for the next launch. Today's and earlier
/// puzzles are frozen, so a refresh never changes a game in progress. Only data is downloaded:
/// the game code always comes from the app bundle (App Review 2.5.2).
enum DataStore {
    struct Loaded: Sendable {
        let players: Data
        let puzzles: Data
        let puzzlesFile: PuzzlesFile
        let teams: [String: TeamInfo]
        let seasons: [Int]
        let source: Source
    }

    enum Source: String, Sendable { case bundled, downloaded }

    private struct PlayersHeader: Decodable {
        let v: Int
        let sport: String?
        let built: String?
        let seasons: [Int]?
        let teams: [String: TeamInfo]
    }

    private static let sportFolder = Sport.current.key
    private static let remoteBase = URL(string: "https://cev64.github.io/chainmates/data/\(sportFolder)/")!

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("data/\(sportFolder)", isDirectory: true)
    }

    /// The newest valid copy on the device: the downloaded one when it parses and covers at least
    /// as many puzzles as the bundled one, otherwise the bundled one.
    static func load() throws -> Loaded {
        let bundled = try loadBundled()
        if let cached = try? loadCached(), cached.puzzlesFile.epoch == bundled.puzzlesFile.epoch,
           cached.puzzlesFile.puzzles.count >= bundled.puzzlesFile.puzzles.count {
            return cached
        }
        return bundled
    }

    private static func loadBundled() throws -> Loaded {
        guard let p = Bundle.main.url(forResource: "players", withExtension: "json"),
              let z = Bundle.main.url(forResource: "puzzles", withExtension: "json") else {
            throw CoreEngine.EngineError.missingResource("the puzzle data")
        }
        return try parse(players: Data(contentsOf: p), puzzles: Data(contentsOf: z), source: .bundled)
    }

    private static func loadCached() throws -> Loaded {
        let dir = cacheDirectory
        return try parse(players: Data(contentsOf: dir.appendingPathComponent("players.json")),
                         puzzles: Data(contentsOf: dir.appendingPathComponent("puzzles.json")),
                         source: .downloaded)
    }

    private static func parse(players: Data, puzzles: Data, source: Source) throws -> Loaded {
        let header = try JSONDecoder().decode(PlayersHeader.self, from: players)
        let file = try JSONDecoder().decode(PuzzlesFile.self, from: puzzles)
        guard header.v == 1, file.v == 1, !file.puzzles.isEmpty else {
            throw DataError.unexpectedFormat
        }
        return Loaded(players: players, puzzles: puzzles, puzzlesFile: file, teams: header.teams,
                      seasons: header.seasons ?? [], source: source)
    }

    /// Downloads both files and keeps them for the next launch when they parse. Failures are
    /// silent: the app works fully offline.
    static func refresh() async {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadRevalidatingCacheData
        config.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: config)
        do {
            async let p = session.data(from: remoteBase.appendingPathComponent("players.json"))
            async let z = session.data(from: remoteBase.appendingPathComponent("puzzles.json"))
            let (players, pr) = try await p
            let (puzzles, zr) = try await z
            guard (pr as? HTTPURLResponse)?.statusCode == 200, (zr as? HTTPURLResponse)?.statusCode == 200 else { return }
            _ = try parse(players: players, puzzles: puzzles, source: .downloaded)
            let dir = cacheDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try players.write(to: dir.appendingPathComponent("players.json"), options: .atomic)
            try puzzles.write(to: dir.appendingPathComponent("puzzles.json"), options: .atomic)
        } catch {
            // Offline or the site is down: keep what's on the device.
        }
    }

    /// Removes the downloaded copy (About ▸ Reset).
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    enum DataError: LocalizedError {
        case unexpectedFormat
        var errorDescription: String? { "The data files are not in the expected format." }
    }
}

/// Local saves, under the web's localStorage keys so the two stay recognisably the same
/// (`chainmates.theme`, `chainmates.mode`, `chainmates.nfl.daily.5`, `chainmates.nfl.stats`, ...).
/// Nothing leaves the device.
enum Store {
    private static let defaults = UserDefaults.standard
    private static func key(_ k: String) -> String { "chainmates.\(Sport.current.key).\(k)" }

    static var theme: ThemePreference {
        get { ThemePreference(rawValue: defaults.string(forKey: "chainmates.theme") ?? "") ?? .automatic }
        set {
            if newValue == .automatic { defaults.removeObject(forKey: "chainmates.theme") }
            else { defaults.set(newValue.rawValue, forKey: "chainmates.theme") }
        }
    }

    /// The preferred mode for new games; absent or unknown means hard (`H.DEFAULT_MODE`).
    static var preferredMode: GameMode {
        get { GameMode(rawValue: defaults.string(forKey: "chainmates.mode") ?? "") ?? .hard }
        set { defaults.set(newValue.rawValue, forKey: "chainmates.mode") }
    }

    static var seenHelp: Bool {
        get { defaults.object(forKey: key("seen-help")) != nil }
        set { if newValue { defaults.set("1", forKey: key("seen-help")) } else { defaults.removeObject(forKey: key("seen-help")) } }
    }

    static func gameJSON(_ n: Int, practice: Bool) -> String? {
        defaults.string(forKey: key("\(practice ? "practice" : "daily").\(n)"))
    }

    static func saveGame(_ state: GameState, practice: Bool) {
        defaults.set(state.json, forKey: key("\(practice ? "practice" : "daily").\(state.view.n)"))
    }

    static func removeGame(_ n: Int, practice: Bool) {
        defaults.removeObject(forKey: key("\(practice ? "practice" : "daily").\(n)"))
    }

    static var statsJSON: String? {
        get { defaults.string(forKey: key("stats")) }
        set { defaults.set(newValue, forKey: key("stats")) }
    }

    /// Every Chainmates key: About ▸ Reset all data.
    static func resetAll() {
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix("chainmates.") {
            defaults.removeObject(forKey: k)
        }
    }
}
