#if DEBUG
import SwiftUI

/// Debug-only: a root view that shows the Results, Statistics and Archive screens over seeded
/// saves, so they can be seen before the shell is wired. The lead can wire it from the app
/// root with `ResultsDebug.debugRoot()`; `CM_DEBUG_SCREEN=stats|archive|results` picks the tab.
enum ResultsDebug {
    @MainActor static func debugRoot() -> some View { ResultsDebugRoot() }

    /// Writes finished games and stats into the saves (UserDefaults) for puzzles 1 through
    /// `todayN - 1`, plus today's puzzle played on hard along its optimal chain (an eagle).
    /// - 1 par, 2 over by one, 3 lost, 4 birdie, 5 over by two, 6 eagle, 7 only a practice replay.
    static func seed(playersJSON: Data, puzzles: [Puzzle], epoch: String, solveToday: Bool) async throws {
        let engine = try CoreEngine(playersJSON: playersJSON)
        let today = try await engine.easternDate()
        let todayN = try await engine.puzzleNumber(puzzlesJSON: "{\"epoch\":\"\(epoch)\"}", date: today)
        Store.resetAll()
        Store.seenHelp = true
        var stats = try await engine.newStats()
        let filler = puzzles.map(\.start)

        // (puzzle, links over par, lost, mode, practice)
        let plan: [(Int, Int, Bool, GameMode, Bool)] = [
            (1, 0, false, .hard, false), (2, 1, false, .hard, false), (3, 0, true, .hard, false),
            (4, -1, false, .hard, false), (5, 2, false, .easy, false), (6, -2, false, .hard, false),
            (7, -1, false, .easy, true),
        ]
        for (n, over, lost, mode, practice) in plan where n < todayN {
            guard let puzzle = puzzles.first(where: { $0.n == n }) else { continue }
            let fresh = try await engine.newGame(puzzle, mode: mode)
            let links = max(1, fresh.view.par + over)
            var chain = [puzzle.start]
            for i in 1..<links { chain.append(filler[(n * 7 + i) % filler.count]) }
            if !lost { chain.append(puzzle.end) }
            let status = lost ? "lost" : "won"
            let inc = lost ? 3 : (n % 3)
            let json = try await engine.evaluate("""
            (function(){var s=JSON.parse(\(CoreEngine.quote(fresh.json)));
            s.chain=\(jsonArray(chain));s.status='\(status)';s.inc=\(inc);s.downs=\(lost ? 0 : 3 - min(inc, 2));
            return JSON.stringify(s)})()
            """)
            let state = try GameState(json: json)
            Store.saveGame(state, practice: practice)
            if !practice { stats = try await engine.recordResult(stats, puzzleNumber: n, state: state) }
        }
        if solveToday, let puzzle = puzzles.first(where: { $0.n == todayN }), let ids = puzzle.chain {
            var state = try await engine.newGame(puzzle, mode: .hard)
            for id in ids.dropFirst() {
                state = try await engine.guess(state, playerID: id).state
            }
            Store.saveGame(state, practice: false)
            stats = try await engine.recordResult(stats, puzzleNumber: todayN, state: state)
        }
        Store.statsJSON = stats.json
    }

    private static func jsonArray(_ ids: [String]) -> String {
        "[" + ids.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }

    /// An app model over the seeded saves, started.
    @MainActor static func seededModel(solveToday: Bool = true) async throws -> AppModel {
        let loaded = try DataStore.load()
        try await seed(playersJSON: loaded.players, puzzles: loaded.puzzlesFile.puzzles,
                       epoch: loaded.puzzlesFile.epoch, solveToday: solveToday)
        let app = AppModel()
        await app.start()
        return app
    }
}

private struct ResultsDebugRoot: View {
    enum Screen: String, CaseIterable { case results = "Results", stats = "Stats", archive = "Archive" }
    @State private var app = AppModel()
    @State private var ready = false
    @State private var screen: Screen = {
        switch ProcessInfo.processInfo.environment["CM_DEBUG_SCREEN"] {
        case "stats": .stats
        case "archive": .archive
        default: .results
        }
    }()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Screen", selection: $screen) {
                ForEach(Screen.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()
            if ready {
                switch screen {
                case .results: ResultsSheet()
                case .stats: StatsScreen()
                case .archive: ArchiveScreen()
                }
            } else {
                Spacer()
            }
        }
        .background(Theme.paper)
        .environment(app)
        .task {
            if let seeded = try? await ResultsDebug.seededModel() { app = seeded }
            ready = true
        }
    }
}
#endif
