import Foundation
import Observation

/// One puzzle being played, daily or practice. Every move goes through the core; the session
/// keeps the state it returns, saves it, and remembers what the last move did so the screen can
/// animate it.
@MainActor
@Observable
final class GameSession {
    let puzzle: Puzzle
    /// Practice replays never touch stats.
    let isPractice: Bool
    var isDaily: Bool { !isPractice }

    private(set) var state: GameState?
    private(set) var score: Score?
    /// `links[i]` are the team-seasons joining `chain[i]` and `chain[i + 1]` (first = the reason shown).
    private(set) var links: [[TeamSeason]] = []
    /// The hint bought at the current last player, if any.
    private(set) var hint: Hint?
    /// The most recent move's outcome, for animation, haptics and VoiceOver.
    private(set) var lastEvent: Event?
    private(set) var error: String?
    /// The guess being typed. It lives here, not in a view, so folding or unfolding the Duo (a
    /// size-class change that rebuilds the game screen's layout) keeps it.
    var draft = ""

    struct Event: Equatable, Identifiable {
        let id = UUID()
        let kind: Kind
        enum Kind: Equatable {
            case linked(String)
            case solved
            case incompletion(guessed: String, downsLeft: Int)
            case lost(guessed: String)
            case rejected(GuessOutcome.RejectReason)
            case undone
            case hinted
            case hintRefused(String)
            case modeChanged(GameMode)
            case modeRefused(String)
        }
    }

    private unowned let app: AppModel

    init(app: AppModel, puzzle: Puzzle, practice: Bool) {
        self.app = app
        self.puzzle = puzzle
        self.isPractice = practice
        Task { await self.restore() }
    }

    var mode: GameMode { state?.view.effectiveMode ?? Store.preferredMode }
    /// Anything has happened: a guess, an incompletion, a hint, an undo or a mode switch (the
    /// web's `hasMoved`). Before that, either mode can be picked and becomes the default.
    var hasStarted: Bool {
        guard let v = state?.view else { return false }
        return v.chain.count > 1 || !(v.log ?? []).isEmpty
    }

    // MARK: Restore

    private func restore() async {
        guard let engine = app.engine else { return }
        await app.loadPlayers([puzzle.start, puzzle.end])
        if let json = Store.gameJSON(puzzle.n, practice: isPractice), let saved = try? GameState(json: json),
           await isValid(saved, engine: engine) {
            await adopt(saved)
        } else {
            do { await adopt(try await engine.newGame(puzzle, mode: Store.preferredMode)) }
            catch { self.error = error.localizedDescription }
        }
        // A finished daily is recorded again on load; the core makes that a no-op.
        if isDaily, let s = state, s.view.isOver { await app.record(s) }
    }

    /// The web's `validState`: a saved state that doesn't fit this puzzle (or the current data) is
    /// dropped and the game starts fresh.
    private func isValid(_ s: GameState, engine: CoreEngine) async -> Bool {
        let v = s.view
        guard v.n == puzzle.n, v.start == puzzle.start, v.end == puzzle.end, v.downs >= 0,
              v.chain.first == puzzle.start else { return false }
        guard let par = try? await engine.parFor(puzzle, mode: v.effectiveMode), par == v.par else { return false }
        if let best = v.best, best != (puzzle.best ?? puzzle.par) { return false }
        for id in v.chain {
            guard (try? await engine.player(id)) ?? nil != nil else { return false }
        }
        return true
    }

    private func adopt(_ s: GameState) async {
        guard let engine = app.engine else { return }
        await app.loadPlayers(s.view.chain)
        var newLinks: [[TeamSeason]] = []
        let chain = s.view.chain
        if chain.count > 1 {
            for i in 0..<(chain.count - 1) {
                // Reuse what's known; only new links ask the core.
                if i < links.count, i + 1 < (state?.view.chain.count ?? 0), state?.view.chain[i + 1] == chain[i + 1] {
                    newLinks.append(links[i])
                } else {
                    newLinks.append((try? await engine.sharedTeams(chain[i], chain[i + 1])) ?? [])
                }
            }
        }
        links = newLinks
        hint = s.view.hintAt[s.view.last]
        await app.loadLabels(newLinks.flatMap { $0 } + (hint.map { [TeamSeason(team: $0.team, season: $0.season)] } ?? []))
        state = s
        score = try? await engine.score(s)
        Store.saveGame(s, practice: isPractice)
    }

    // MARK: Moves

    func guess(_ player: CorePlayer) async {
        guard let engine = app.engine, let s = state, !s.view.isOver else { return }
        app.remember([player])
        do {
            let (next, outcome) = try await engine.guess(s, playerID: player.id)
            switch outcome {
            case .rejected(let reason):
                lastEvent = Event(kind: .rejected(reason))
                return
            case .link:
                await adopt(next)
                lastEvent = Event(kind: .linked(player.id))
            case .solved:
                await adopt(next)
                lastEvent = Event(kind: .solved)
                await finish(next)
            case .incompletion(let left):
                await adopt(next)
                lastEvent = Event(kind: .incompletion(guessed: player.id, downsLeft: left))
            case .lost:
                await adopt(next)
                lastEvent = Event(kind: .lost(guessed: player.id))
                await finish(next)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func undo() async {
        guard let engine = app.engine, let s = state, !s.view.isOver, s.view.chain.count > 1 else { return }
        guard let next = try? await engine.undo(s), next.view.chain.count < s.view.chain.count else { return }
        await adopt(next)
        lastEvent = Event(kind: .undone)
    }

    /// Buys a hint (costs a down; free again at the same spot). Refused on the last down.
    func buyHint() async {
        guard let engine = app.engine, let s = state else { return }
        guard let (next, h, err) = try? await engine.hint(s) else { return }
        if let h {
            await adopt(next)
            hint = h
            lastEvent = Event(kind: .hinted)
        } else {
            lastEvent = Event(kind: .hintRefused(err ?? "none"))
        }
    }

    /// Whether buying a hint now would cost a down (it's free when already bought here).
    var hintIsFree: Bool { hint != nil }

    /// Changes difficulty. Before the first move either way is allowed and becomes the default for
    /// new games; mid-game only hard to easy, for this puzzle only (docs/decisions.md).
    func setMode(_ mode: GameMode) async {
        guard let engine = app.engine, let s = state, mode != s.view.effectiveMode else { return }
        if !hasStarted {
            Store.preferredMode = mode
            guard let fresh = try? await engine.newGame(puzzle, mode: mode) else { return }
            await adopt(fresh)
            lastEvent = Event(kind: .modeChanged(mode))
            return
        }
        guard let (next, refused) = try? await engine.setMode(s, to: mode) else { return }
        if let refused {
            lastEvent = Event(kind: .modeRefused(refused))
        } else {
            await adopt(next)
            lastEvent = Event(kind: .modeChanged(mode))
        }
    }

    private func finish(_ s: GameState) async {
        if isDaily { await app.record(s) }
        // Let the lock-up play before the results come up, timed like the web: the pulse runs
        // down the chain, then the knot turns, then the brass sweep for an eagle or birdie.
        let nodes = s.view.chain.count
        let over = score?.over ?? 1
        let flourish = !s.view.status.isWin ? 120 : over <= -2 ? 900 : over < 0 ? 380 : 120
        try? await Task.sleep(for: .milliseconds(500 + 80 * nodes + 360 + flourish))
        if state?.json == s.json { app.sheet = .results }
    }

    // MARK: Results

    func shareText() async -> String? {
        guard let engine = app.engine, let s = state else { return nil }
        return try? await engine.shareText(puzzle, s, options: app.sport.shareOptions())
    }

    /// What a finished chain at `links` links would score, for the under-par ladder ("birdie in 4").
    func label(atLinks n: Int) async -> String? {
        guard let engine = app.engine, let s = state else { return nil }
        let chain = Array(repeating: "\"\"", count: n + 1).joined(separator: ",")
        let expr = "JSON.stringify(H.score(Object.assign(JSON.parse(\(CoreEngine.quote(s.json))), {chain:[\(chain)], status:'won'})).label)"
        guard let text = try? await engine.evaluate(expr) else { return nil }
        return try? JSONDecoder().decode(String.self, from: Data(text.utf8))
    }

    /// Search for the next link: excludes everyone already in the chain.
    func search(_ query: String) async -> [CorePlayer] {
        guard let engine = app.engine, let s = state else { return [] }
        let list = (try? await engine.search(query, limit: AppConfig.searchLimit, exclude: s.view.chain)) ?? []
        app.remember(list)
        return list
    }

    func stintRanges(_ id: String) async -> [StintRange] {
        (try? await app.engine?.stintRanges(id)) ?? []
    }

    func teamLabel(_ t: TeamSeason) async -> String {
        (try? await app.engine?.teamLabel(t.team, t.season)) ?? "\(t.season) \(t.team)"
    }

    func teamFullName(_ t: TeamSeason) async -> String {
        (try? await app.engine?.teamFullName(t.team, t.season)) ?? t.team
    }
}
