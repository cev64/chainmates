import SwiftUI
import Observation

/// The game screen's view state for one `GameSession`: what the board shows (a snapshot of the
/// session, so a change can be animated as it lands), the autocomplete, and the animation
/// triggers. Every rule goes through the session and so through the core; this only decides
/// how a change looks, like the render half of `web/app.js`.
///
/// It lives above the screen's size-class branch, so folding or unfolding the Duo keeps the
/// suggestions and the highlight; the draft text itself is `GameSession.draft`.
@MainActor
@Observable
final class GameController {
    let session: GameSession
    @ObservationIgnored unowned let app: AppModel
    var reduceMotion = false

    // MARK: Board snapshot

    /// The state the board draws. It trails `session.state` by one update so new rows know
    /// they are new.
    private(set) var view: GameState.View?
    private(set) var links: [[TeamSeason]] = []
    private(set) var hint: Hint?
    private(set) var totalDowns = 3

    /// The body row springing in (its id), and whether the finish block is landing too.
    private(set) var entering: String?
    private(set) var targetEntering = false
    /// The last row while undo pulls it back out.
    private(set) var retracting: String?
    /// The board still reads "playing" for 720 ms after the last down, while the miss plays.
    private(set) var lostHold = false
    /// The hint pill plays its reveal (bulb lights, words slide in) for this spot.
    private(set) var hintRevealKey: String?
    /// Career lines slide in after a switch to easy, and fold away before a switch to hard.
    private(set) var careerEntrance = false
    private(set) var careerFolding = false
    private(set) var busy = false

    // MARK: Lock-up and miss

    private(set) var lockTick = 0
    private(set) var shimmerTick = 0
    private(set) var shimmerDelay: Double = 0
    private(set) var shimmerDuration: Double = 0.9
    /// Eagle: how many rails (and dot rings) have turned brass so far; `gildAll` for a game that
    /// was already won when it opened.
    private(set) var gildCount = 0
    private(set) var ringCount = 0
    private(set) var gildAll = false

    private(set) var missTick = 0
    private(set) var missFlash = false
    private(set) var failName: String?
    private(set) var failID = 0
    private(set) var nextHidden = false
    private(set) var nopeTick = 0

    // MARK: Haptics

    private(set) var linkTick = 0
    private(set) var solveTick = 0
    private(set) var undoTick = 0
    /// Bumped when the board should show its newest link (scroll to the live end of the chain).
    private(set) var revealTick = 0
    private(set) var blurTick = 0
    private(set) var focusTick = 0

    // MARK: Autocomplete

    var query: String {
        get { session.draft }
        set { session.draft = newValue }
    }
    private(set) var results: [CorePlayer] = []
    private(set) var searchedQuery = ""
    private(set) var listOpen = false
    /// The list just opened (rows stagger in) rather than updated while typing.
    private(set) var listFresh = true
    var active = -1
    /// The player moved the highlight themselves (arrows or pointer), so Enter means that row.
    var chosen = false
    private(set) var emptyText: String?
    var fieldFocused = false

    // MARK: Dialogs

    var confirmHint = false
    var confirmEasy = false

    // MARK: Caches

    private(set) var careers: [String: [StintRange]] = [:]
    private var careerLoading: Set<String> = []

    /// The player whose guess is in flight (for the toasts), and the one undo removed.
    private var guessed: CorePlayer?
    private var lastBeforeGuess: String?
    private var removedName = ""

    init(session: GameSession, app: AppModel) {
        self.session = session
        self.app = app
        Task { [weak self] in
            if let text = try? await app.engine?.evaluate("String(H.DOWNS)"), let n = Int(text) {
                self?.totalDowns = n
            }
        }
    }

    // MARK: Derived

    var mode: GameMode { view?.effectiveMode ?? session.mode }
    var isPlaying: Bool { view?.status == .playing || lostHold }
    var isWon: Bool { view?.status == .won && !lostHold }
    var isLost: Bool { view?.status == .lost && !lostHold }
    /// Chain rows above the slot: everyone placed, without the end player once solved.
    var body: [String] {
        guard let v = view else { return [] }
        return v.status == .won ? Array(v.chain.dropLast()) : v.chain
    }
    var score: Score? { session.score }
    var tierOver: Int? { isWon ? score?.over : nil }
    var isBirdie: Bool { (tierOver ?? 0) < 0 }
    var isEagle: Bool { (tierOver ?? 0) <= -2 }
    var canUndo: Bool { isPlaying && !lostHold && (view?.chain.count ?? 0) > 1 }
    var hintCached: Bool { isPlaying && hint != nil }

    func player(_ id: String) -> CorePlayer? { app.cachedPlayer(id) }
    func name(_ id: String?) -> String { id.flatMap { app.cachedPlayer($0)?.name } ?? "" }

    var seasonsRange: String { app.seasons.map(String.init).joined(separator: "\u{2013}") }

    /// The web's `hasMoved`: any placed link or anything in the log (a guess, miss, hint, undo
    /// or earlier switch).
    var hasMoved: Bool {
        guard let s = session.state else { return false }
        if s.view.chain.count > 1 { return true }
        let object = try? JSONSerialization.jsonObject(with: Data(s.json.utf8)) as? [String: Any]
        return ((object?["log"] as? [Any])?.count ?? 0) > 0
    }

    /// `links[i]`, the team-seasons joining body row `i` and `i + 1`.
    func shared(_ i: Int) -> [TeamSeason] { i >= 0 && i < links.count ? links[i] : [] }

    // MARK: Sync

    /// Takes the session's new state onto the board and decides how it lands.
    func sync() {
        guard let s = session.state else { return }
        let new = s.view, old = view
        var enter: String?
        var target = false
        if let old, old.n == new.n {
            let grew = Array(new.chain.prefix(old.chain.count)) == old.chain
            if grew, new.chain.count == old.chain.count + 1 {
                if new.status == .won { target = true } else { enter = new.chain.last }
            } else if grew, new.status == .won, new.chain.count == old.chain.count + 2 {
                enter = new.chain[new.chain.count - 2]
                target = true
            }
            if new.status == .lost, old.status == .playing, !reduceMotion {
                lostHold = true
                busy = true
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(720))
                    guard let self else { return }
                    animate(self.reduceMotion, .chainSnappy) { self.lostHold = false }
                    self.busy = false
                }
            }
            if new.hints > old.hints, new.hintAt[new.last] != nil, old.hintAt[new.last] == nil {
                hintRevealKey = "\(new.n):\(new.last)"
            }
            if old.effectiveMode == .hard, new.effectiveMode == .easy {
                careerEntrance = !reduceMotion
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(900))
                    self?.careerEntrance = false
                }
            }
        }
        if new.status == .won, old == nil || old?.status == .won { gildAll = true }
        let apply = {
            self.entering = enter
            self.targetEntering = target
            self.view = new
            self.links = self.session.links
            self.hint = self.session.hint
            self.retracting = nil
            self.careerFolding = false
        }
        if old == nil { apply() } else { animate(reduceMotion, .chainSnappy, apply) }
        if new.effectiveMode == .easy { Task { await loadCareers(body + [new.end]) } }
        if enter != nil || target {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1200))
                if self?.entering == enter { self?.entering = nil }
                self?.targetEntering = false
            }
        }
        if !new.isOver, listOpen, !query.trimmingCharacters(in: .whitespaces).isEmpty, old?.effectiveMode != new.effectiveMode {
            Task { await runSearch() }
        }
    }

    // MARK: Events

    func handle(_ event: GameSession.Event) {
        switch event.kind {
        case .linked(let id):
            linkTick += 1
            revealTick += 1
            let label = links.last?.first.map { app.teamLabel($0) } ?? ""
            let n = (view?.chain.count ?? 1) - 1
            announce("\(name(id)) added. Teammates on the \(label). \(plural(n, "link")) so far.")
        case .solved:
            solveTick += 1
            blurTick += 1
            revealTick += 1
            let final = links.last?.first.map { app.teamLabel($0) } ?? ""
            announce("\(guessed?.name ?? "") added, and played with \(name(view?.end)) on the \(final). Solved!")
            startLockUp()
        case .incompletion(let id, let left):
            let who = guessed?.name ?? name(id)
            miss(who)
            app.showToast("\(cap(app.sport.miss)) \u{2014} \(who) and \(name(lastBeforeGuess ?? view?.last)) were never teammates",
                          detail: downsLeftText(left))
        case .lost(let id):
            let who = guessed?.name ?? name(id)
            miss(who)
            app.showToast("\(app.sport.lost) \u{2014} \(who) and \(name(lastBeforeGuess ?? view?.last)) were never teammates",
                          detail: "Game over.")
        case .rejected(let reason):
            let last = name(view?.last)
            let who = guessed?.name ?? "That player"
            switch reason {
            case .inChain: app.showToast("Already in your chain", detail: "\(who) is already linked.")
            case .start: app.showToast("That's your starting player", detail: "Pick a teammate of \(last).")
            case .end: app.showToast("Not yet", detail: "\(who) never played with \(last). Find a link first. No \(app.sport.life) lost.")
            case .unknown: app.showToast("Pick a player from the list")
            case .over: app.showToast("This game is over")
            }
            focusTick += 1
        case .undone:
            announce("Removed \(removedName). Undo is free.")
        case .hinted:
            guard let v = view, let h = hint else { return }
            app.showToast("Hint revealed", detail: downsLeftText(v.downs))
            announce("Hint. " + hintPlain(h, v))
        case .hintRefused(let error):
            app.showToast(error == "last-down" ? "No hints on your last \(app.sport.life)"
                          : error == "none" ? "No hint available here" : "This game is over")
        case .modeChanged(let m):
            let par = view?.par ?? 0
            announce("\(m == .easy ? "Easy" : "Hard") mode. \(m == .easy ? "Every team is shown." : "No teams are shown.") Par \(par).")
            if m == .easy { Task { await loadCareers(body + [view?.end ?? ""]) } }
        case .modeRefused(let reason):
            if reason == "started" {
                Store.preferredMode = .hard
                nopeTick += 1
                app.showToast("Hard mode starts fresh", detail: "Next puzzle, or replay from the archive.")
            }
        }
    }

    // MARK: Moves

    func pick(_ p: CorePlayer) {
        guard view?.status == .playing, !busy else { return }
        guessed = p
        lastBeforeGuess = view?.last
        clearGuess()
        Task { await session.guess(p) }
    }

    func undo() {
        guard canUndo, !busy, let last = view?.last else { return }
        removedName = name(last)
        undoTick += 1
        if reduceMotion {
            Task { await session.undo() }
            return
        }
        busy = true
        retracting = last
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(360))
            await self?.session.undo()
            self?.busy = false
            if self?.retracting == last { self?.retracting = nil }
        }
    }

    /// The Hint button: the cached hint is free (scroll to it); the last down refuses; otherwise
    /// confirm, because it costs a down.
    func requestHint() {
        guard let v = view, isPlaying, !busy else { return }
        if hint != nil { revealTick += 1; return }
        if v.downs <= 1 { app.showToast("No hints on your last \(app.sport.life)"); return }
        confirmHint = true
    }

    func buyHint() {
        Task { await session.buyHint() }
    }

    func hintMessage() -> String {
        guard let v = view else { return "" }
        return "A hint reveals a team and a position: who to look for next on a shortest route from \(name(v.last)). " +
            "It costs one \(app.sport.life): you'll have \(plural(v.downs - 1, app.sport.life, app.sport.lives)) left."
    }

    // MARK: Mode

    func requestMode(_ want: GameMode) {
        guard view?.status == .playing, !busy, want != mode else { return }
        if want == .easy, hasMoved {
            Task { [weak self] in
                guard let self else { return }
                self.easyPar = try? await self.app.engine?.parFor(self.session.puzzle, mode: .easy)
                self.confirmEasy = true
            }
            return
        }
        applyMode(want)
    }

    func applyMode(_ want: GameMode) {
        if want == .hard, mode == .easy, !hasMoved, !reduceMotion {
            busy = true
            withAnimation(.timingCurve(0.5, 0, 0.75, 0, duration: 0.26)) { careerFolding = true }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(260))
                await self?.session.setMode(want)
                self?.busy = false
            }
            return
        }
        Task { await session.setMode(want) }
    }

    func easyMessage() -> String {
        guard let v = view else { return "" }
        return "You'll see every player's teams and years. Par drops from \(v.par) to \(easyPar ?? v.par - 1). " +
            "This puzzle only: your next one starts on \(Store.preferredMode.rawValue)."
    }

    private(set) var easyPar: Int?

    // MARK: Autocomplete

    func clearGuess() {
        query = ""
        closeList()
    }

    func closeList() {
        results = []
        active = -1
        chosen = false
        emptyText = nil
        if listOpen { withAnimation(.timingCurve(0.5, 0, 0.75, 0, duration: 0.12)) { listOpen = false } }
    }

    /// The web's `runSearch`: up to 8 matches that aren't already in the chain, highlight on the top.
    func runSearch() async {
        let q = query
        guard view?.status == .playing, !q.trimmingCharacters(in: .whitespaces).isEmpty else { closeList(); return }
        let list = await session.search(q)
        guard q == query else { return }
        searchedQuery = q
        var why: String?
        if list.isEmpty {
            let held = (try? await app.engine?.search(q, limit: 1))?.first
            if let held, held.id == view?.start { why = "\(held.name) is your starting player." }
            else if let held, view?.chain.contains(held.id) == true { why = "\(held.name) is already in your chain." }
            else { why = "No player by that name played \(seasonsRange)." }
        }
        if mode == .easy { await loadCareers(list.map(\.id)) }
        guard q == query else { return }
        let wasOpen = listOpen
        listFresh = !wasOpen
        results = list
        emptyText = why
        active = list.isEmpty ? -1 : 0
        chosen = false
        if wasOpen { listOpen = true } else {
            animate(reduceMotion, .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { listOpen = true }
        }
    }

    /// Enter doesn't guess the top row blindly (a wrong guess costs a down): only a row the player
    /// highlighted, the only match, or an exact name.
    func submit() async {
        if query != searchedQuery || !listOpen { await runSearch() }
        guard active >= 0, active < results.count else {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty { app.showToast("Pick a player from the list") }
            return
        }
        let top = results[active]
        var sure = chosen || results.count == 1
        if !sure, let engine = app.engine {
            let a = try? await engine.normalize(top.name)
            let b = try? await engine.normalize(query)
            sure = a != nil && a == b
        }
        if sure { pick(top) } else { app.showToast("Tap a name to guess") }
    }

    func moveHighlight(_ step: Int) {
        guard !results.isEmpty else { return }
        let n = results.count
        withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)) {
            active = ((active + step) % n + n) % n
        }
        chosen = true
    }

    func hover(_ i: Int) {
        guard i != active else { return }
        withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)) { active = i }
        chosen = true
    }

    // MARK: Careers

    func loadCareers(_ ids: [String]) async {
        let todo = ids.filter { !$0.isEmpty && careers[$0] == nil && !careerLoading.contains($0) }
        guard !todo.isEmpty else { return }
        careerLoading.formUnion(todo)
        var labels: [TeamSeason] = []
        for id in todo {
            let r = await session.stintRanges(id)
            careers[id] = r
            labels += r.map { TeamSeason(team: $0.team, season: $0.to) }
        }
        await app.loadLabels(labels)
    }

    // MARK: Animation

    private func miss(_ who: String) {
        missTick += 1
        guard !reduceMotion else { return }
        missFlash = true
        failName = who
        failID += 1
        let id = failID
        withAnimation(.easeOut(duration: 0.18)) { nextHidden = true }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.easeOut(duration: 0.2)) { self?.missFlash = false }
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, self.failID == id else { return }
            self.failName = nil
            withAnimation(.easeOut(duration: 0.18)) { self.nextHidden = false }
        }
    }

    /// The solve: let the final link land, pulse the chain from start to finish (knots turn),
    /// then a brass sweep under par; an eagle re-draws every rail in brass, link by link.
    private func startLockUp() {
        guard !reduceMotion, let v = view else { gildAll = true; return }
        busy = true
        let nodes = v.chain.count
        let over = score?.over ?? 0
        let birdie = over < 0, eagle = over <= -2
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.lockTick += 1
            if birdie {
                self.shimmerDelay = 0.08 * Double(nodes - 1) * 0.6
                self.shimmerDuration = eagle ? 1.1 : 0.9
                self.shimmerTick += 1
            }
            if eagle {
                for k in 0..<nodes {
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.36)) { self.gildCount = k + 1 }
                    Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.6)) { self.ringCount = k + 1 }
                    }
                    try? await Task.sleep(for: .milliseconds(128))
                }
            }
            try? await Task.sleep(for: .milliseconds(80 * nodes + 360))
            self.busy = false
        }
    }

    // MARK: Copy

    func downsLeftText(_ n: Int) -> String { plural(n, app.sport.life, app.sport.lives) + " left" }

    func hintPlain(_ h: Hint, _ v: GameState.View) -> String {
        let c = app.sport.hintCopy(h, puzzle: v.n, chainLength: v.chain.count)
        return c.before + app.teamLabel(TeamSeason(team: h.team, season: h.season)) + c.after
    }

    private func announce(_ text: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(30))
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

// MARK: - Small helpers

/// "1 link", "2 links" (`plural` in web/app.js).
func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
    "\(n) " + (n == 1 ? one : many ?? one + "s")
}

func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

extension CoreEngine {
    /// `H.normalize`: lowercase, accents and punctuation stripped (for the Enter exact-name test).
    func normalize(_ text: String) throws -> String {
        try call(String.self, "normalize", [.value(text)])
    }
}

/// The web's motion curves (app.css `--ease-*`).
enum Ease {
    static func out(_ d: Double) -> Animation { .timingCurve(0.2, 0.8, 0.2, 1, duration: d) }
    static func `in`(_ d: Double) -> Animation { .timingCurve(0.5, 0, 0.75, 0, duration: d) }
    static func inOut(_ d: Double) -> Animation { .timingCurve(0.65, 0, 0.35, 1, duration: d) }
    /// `--ease-spring` at `--dur-l`: one small overshoot, one settle.
    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.68)
}
