import Foundation
import Observation
import SwiftUI

/// The app's state: the loaded data and engine, today's puzzle number, stats, and navigation.
/// Screens read it from the environment (`@Environment(AppModel.self)`).
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading
        case ready
        case failed(String)
    }

    /// Where the main column is (the web's hash routes, `#`, `#archive`, `#stats`).
    enum Route: Hashable {
        case today
        case archive
        case stats
    }

    /// The modal sheets.
    enum Sheet: String, Identifiable {
        case help, about, results
        var id: String { rawValue }
    }

    private(set) var phase: Phase = .loading
    private(set) var engine: CoreEngine?
    private(set) var puzzles: [Puzzle] = []
    private(set) var teams: [String: TeamInfo] = [:]
    private(set) var seasons: [Int] = []
    private var epoch: String = ""
    /// Today's date in America/New_York and its puzzle number (may be < 1 or past the data).
    private(set) var today: String = ""
    private(set) var todayNumber: Int = 0
    private(set) var stats: Stats?
    private(set) var streaks: Streaks?
    /// When the Eastern date next changes.
    private(set) var nextRollover: Date = .distantFuture

    var route: Route = .today
    var sheet: Sheet?
    var theme: ThemePreference = Store.theme {
        didSet { Store.theme = theme }
    }
    /// The game on screen (today's, or a past puzzle from the archive).
    private(set) var session: GameSession?
    /// A short message at the bottom of the screen (the web's toast).
    var toast: Toast?

    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let text: String
        var detail: String?
    }

    let sport = Sport.current
    private var players: [String: CorePlayer] = [:]
    private var rolloverTask: Task<Void, Never>?

    // MARK: Loading

    func start() async {
        phase = .loading
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try DataStore.load() }.value
            let engine = try await Task.detached(priority: .userInitiated) {
                try CoreEngine(playersJSON: loaded.players)
            }.value
            self.engine = engine
            self.puzzles = loaded.puzzlesFile.puzzles
            self.teams = loaded.teams
            self.seasons = loaded.seasons
            self.epoch = loaded.puzzlesFile.epoch
            try await refreshToday()
            try await loadStats()
            phase = .ready
            openToday()
            if !Store.seenHelp { sheet = .help }
            Task.detached(priority: .background) { await DataStore.refresh() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private var puzzlesFileJSON: String {
        // Only `epoch` is read by puzzleNumberForDate.
        "{\"epoch\":\"\(epoch)\"}"
    }

    /// Recomputes today (America/New_York) and schedules the next rollover.
    func refreshToday() async throws {
        guard let engine else { return }
        let ymd = try await engine.easternDate()
        today = ymd
        todayNumber = try await engine.puzzleNumber(puzzlesJSON: puzzlesFileJSON, date: ymd)
        nextRollover = try await findNextRollover(engine)
        if let stats { streaks = try? await engine.displayStreaks(stats, todayNumber: todayNumber) }
        scheduleRollover()
    }

    /// The next moment the Eastern date changes, by binary search over `easternDate` (no time
    /// zone maths in Swift), like the web's `nextRollover`.
    private func findNextRollover(_ engine: CoreEngine) async throws -> Date {
        let now = Date.now
        let d0 = try await engine.easternDate(now)
        var lo = now, hi = now.addingTimeInterval(26 * 3600)
        if try await engine.easternDate(hi) == d0 { return hi }
        while hi.timeIntervalSince(lo) > 0.5 {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            if try await engine.easternDate(mid) == d0 { lo = mid } else { hi = mid }
        }
        return hi
    }

    private func scheduleRollover() {
        rolloverTask?.cancel()
        let wait = max(1, nextRollover.timeIntervalSinceNow + 0.5)
        rolloverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            try? await self?.refreshToday()
        }
    }

    /// Called when the app comes back to the foreground: the date may have changed.
    func becameActive() async {
        guard engine != nil else { return }
        let before = todayNumber
        // Another window (iPad, the unfolded iPhone Duo) may have recorded a result meanwhile.
        try? await loadStats()
        try? await refreshToday()
        if todayNumber != before, session?.isDaily == true, session?.state?.view.isOver == true {
            showToast("A new puzzle is out")
        }
    }

    // MARK: Puzzles

    func puzzle(_ n: Int) -> Puzzle? {
        guard n >= 1, n <= puzzles.count else { return nil }
        let p = puzzles[n - 1]
        return p.n == n ? p : puzzles.first { $0.n == n }
    }

    var todayPuzzle: Puzzle? { puzzle(todayNumber) }

    /// Puzzles playable now, newest first (today down to No. 1).
    var archive: [Puzzle] {
        let top = min(todayNumber, puzzles.count)
        guard top >= 1 else { return [] }
        return (1...top).reversed().compactMap { puzzle($0) }
    }

    /// Today's puzzle as a daily game. With no puzzle for today the session is nil and the
    /// game screen shows "Off day".
    func openToday() {
        route = .today
        guard let p = todayPuzzle else { session = nil; return }
        if session?.puzzle.n == p.n, session?.isDaily == true { return }
        session = GameSession(app: self, puzzle: p, practice: false)
    }

    /// A puzzle from the archive: today's (or a finished daily) is daily, any other is practice.
    func open(_ n: Int) {
        guard let p = puzzle(n), n <= todayNumber else { return }
        let daily = n == todayNumber || (Store.gameJSON(n, practice: false).flatMap { try? GameState(json: $0) }?.view.isOver ?? false)
        route = .today
        if session?.puzzle.n == n, session?.isDaily == daily { return }
        session = GameSession(app: self, puzzle: p, practice: !daily)
    }

    /// Replays a puzzle in practice (from a finished daily's results, "Play again").
    func practice(_ n: Int) {
        guard let p = puzzle(n) else { return }
        Store.removeGame(n, practice: true)
        route = .today
        session = GameSession(app: self, puzzle: p, practice: true)
    }

    // MARK: Players

    /// A player from the cache (filled by `loadPlayers`), for drawing synchronously.
    func cachedPlayer(_ id: String) -> CorePlayer? { players[id] }

    func loadPlayers(_ ids: [String]) async {
        guard let engine else { return }
        for id in ids where players[id] == nil {
            if let p = try? await engine.player(id) { players[id] = p }
        }
    }

    func remember(_ list: [CorePlayer]) {
        for p in list { players[p.id] = p }
    }

    func team(_ code: String) -> TeamInfo? { teams[code] }

    private var labels: [TeamSeason: (short: String, full: String)] = [:]

    /// "2015 Broncos", from the cache (filled by `loadLabels`); falls back to the code.
    func teamLabel(_ t: TeamSeason) -> String { labels[t]?.short ?? "\(t.season) \(t.team)" }
    /// "Denver Broncos", for VoiceOver.
    func teamFullName(_ t: TeamSeason) -> String { labels[t]?.full ?? t.team }

    /// Asks the core for the labels of these team-seasons (Washington's name changes by season).
    func loadLabels(_ list: [TeamSeason]) async {
        guard let engine else { return }
        for t in list where labels[t] == nil {
            let short = (try? await engine.teamLabel(t.team, t.season)) ?? "\(t.season) \(t.team)"
            let full = (try? await engine.teamFullName(t.team, t.season)) ?? t.team
            labels[t] = (short, full)
        }
    }

    // MARK: Stats

    private func loadStats() async throws {
        guard let engine else { return }
        var loaded: Stats?
        if let json = Store.statsJSON, let s = try? Stats(json: json) { loaded = s }
        let s: Stats
        if let loaded { s = loaded } else { s = try await engine.newStats() }
        stats = s
        streaks = try await engine.displayStreaks(s, todayNumber: todayNumber)
    }

    /// Records a finished daily game (archive and practice plays don't count).
    func record(_ state: GameState) async {
        guard let engine, let stats, state.view.isOver else { return }
        guard let next = try? await engine.recordResult(stats, puzzleNumber: state.view.n, state: state) else { return }
        self.stats = next
        Store.statsJSON = next.json
        streaks = try? await engine.displayStreaks(next, todayNumber: todayNumber)
    }

    func resetAllData() async {
        Store.resetAll()
        DataStore.clearCache()
        theme = .automatic
        stats = nil
        session = nil
        try? await loadStats()
        openToday()
        showToast("All Chainmates data on this device was erased")
    }

    // MARK: Toasts

    func showToast(_ text: String, detail: String? = nil) {
        let t = Toast(text: text, detail: detail)
        toast = t
        Task { [weak self] in
            try? await Task.sleep(for: AppConfig.toastDuration)
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }
}
