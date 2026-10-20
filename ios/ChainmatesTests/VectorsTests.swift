import XCTest
@testable import Chainmates

/// Swift port of `core/test/vectors.test.js`: every group of `core/test/vectors.json` runs through
/// the real `CoreEngine` (JavaScriptCore) against the fixture players/puzzles, going through the
/// typed `CoreAPI` wrappers wherever one exists so the Swift bridge and decoders are exercised too.
/// The vectors file is language neutral; its `_doc` explains the move codes and the optional fields.
final class VectorsTests: XCTestCase {
    private final class BundleAnchor {}

    // MARK: - Loading

    private var testBundle: Bundle { Bundle(for: BundleAnchor.self) }

    private func resource(_ name: String) throws -> Data {
        let url = try XCTUnwrap(testBundle.url(forResource: name, withExtension: "json"), "test bundle is missing \(name).json")
        return try Data(contentsOf: url)
    }

    /// The fixture engine: handoff-core.js from the app (host) bundle, the index from fixture-players.json.
    private func makeEngine() throws -> CoreEngine {
        try CoreEngine(bundle: .main, playersJSON: resource("fixture-players"))
    }

    private func vectors() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: resource("vectors")) as? [String: Any])
    }

    private func group(_ name: String) throws -> [[String: Any]] {
        let rows = try XCTUnwrap(vectors()[name] as? [[String: Any]], "vectors.json has no group \(name)")
        XCTAssertFalse(rows.isEmpty, "group \(name) is empty")
        return rows
    }

    private func fixturePuzzles() throws -> [Puzzle] {
        try JSONDecoder().decode(PuzzlesFile.self, from: resource("fixture-puzzles")).puzzles
    }

    // MARK: - JSON helpers

    private func jsonText(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    private func jsonObject(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// A state in the shape the core returns, built from the few fields a vector gives; the rest are filler.
    private func stateJSON(links: Int? = nil, chain: [String]? = nil, par: Int, best: Int?, mode: String?, status: String,
                           inc: Int, hints: Int, n: Int = 0) throws -> GameState {
        var s: [String: Any] = [
            "n": n, "start": "x", "end": "y", "par": par, "chain": chain ?? Array(repeating: "x", count: (links ?? 0) + 1),
            "downs": 3, "inc": inc, "hints": hints, "hintAt": [String: Any](), "status": status, "log": [Any](),
        ]
        if let best { s["best"] = best }
        if let mode { s["mode"] = mode }
        return try GameState(json: jsonText(s))
    }

    private func puzzle(n: Int = 0, best: Int?, par: Int) -> Puzzle {
        Puzzle(n: n, date: "2026-10-12", start: "x", end: "y", best: best, par: par, kind: nil, theme: nil, chain: nil, optimal: nil, game: nil)
    }

    // MARK: - Pure helpers

    func testVectorsFileIsComplete() throws {
        let v = try vectors()
        for key in ["normalize", "parseStints", "parFor", "stintRanges", "sharedTeams", "shortestPath", "search", "score",
                    "shareText", "puzzleNumberForDate", "easternDate", "game", "stats"] {
            XCTAssertNotNil(v[key] as? [Any], key)
        }
    }

    func testNormalize() async throws {
        let engine = try makeEngine()
        for v in try group("normalize") {
            let input = v["in"] as! String
            let got = try await engine.evaluate("H.normalize(\(CoreEngine.quote(input)))")
            XCTAssertEqual(got, v["out"] as? String, "normalize(\(input.debugDescription))")
        }
    }

    func testParseStints() async throws {
        let engine = try makeEngine()
        for v in try group("parseStints") {
            let input = v["in"] as! String
            let got = try await engine.call([TeamSeason].self, "parseStints", [.value(input)])
            let want = (v["out"] as! [[Any]]).map { TeamSeason(team: $0[0] as! String, season: ($0[1] as! NSNumber).intValue) }
            XCTAssertEqual(got, want, input)
        }
    }

    func testParFor() async throws {
        let engine = try makeEngine()
        for v in try group("parFor") {
            let p = v["puzzle"] as! [String: Any]
            let want = (v["out"] as! NSNumber).intValue
            let label = try jsonText(v)
            let got: Int
            if let mode = (v["mode"] as? String).flatMap(GameMode.init(rawValue:)) {
                got = try await engine.parFor(puzzle(best: (p["best"] as? NSNumber)?.intValue, par: (p["par"] as! NSNumber).intValue), mode: mode)
            } else {
                // No mode at all, or one the app can't even express ("nightmare"): straight to the core.
                var args: [CoreArg] = [.json(try jsonText(p))]
                if let mode = v["mode"] as? String { args.append(.value(mode)) }
                got = try await engine.call(Int.self, "parFor", args)
            }
            XCTAssertEqual(got, want, label)
        }
    }

    // MARK: - Players, teams, paths

    func testStintRanges() async throws {
        let engine = try makeEngine()
        for v in try group("stintRanges") {
            let id = v["id"] as! String
            let want = (v["out"] as! [[Any]]).map {
                StintRange(team: $0[0] as! String, from: ($0[1] as! NSNumber).intValue, to: ($0[2] as! NSNumber).intValue)
            }
            let got = try await engine.stintRanges(id)
            XCTAssertEqual(got, want, id)
        }
    }

    func testSharedTeams() async throws {
        let engine = try makeEngine()
        for v in try group("sharedTeams") {
            let a = v["a"] as! String, b = v["b"] as! String
            let want = (v["out"] as! [[Any]]).map { TeamSeason(team: $0[0] as! String, season: ($0[1] as! NSNumber).intValue) }
            let got = try await engine.sharedTeams(a, b)
            XCTAssertEqual(got, want, "\(a)/\(b)")
        }
    }

    func testShortestPath() async throws {
        let engine = try makeEngine()
        for v in try group("shortestPath") {
            let a = v["a"] as! String, b = v["b"] as! String
            let r = try await engine.shortestPath(a, b)
            if v["dist"] is NSNull {
                XCTAssertNil(r, "\(a)->\(b)")
                continue
            }
            let got = try XCTUnwrap(r, "\(a)->\(b)")
            XCTAssertEqual(got.dist, (v["dist"] as! NSNumber).intValue, "\(a)->\(b)")
            XCTAssertEqual(got.count, (v["count"] as! NSNumber).intValue, "\(a)->\(b)")
            XCTAssertEqual(got.path, v["path"] as! [String], "\(a)->\(b)")
            XCTAssertEqual(got.links.count, got.dist, "\(a)->\(b) links")
        }
    }

    func testSearch() async throws {
        let engine = try makeEngine()
        for v in try group("search") {
            let query = v["query"] as! String
            let exclude = v["exclude"] as? [String] ?? []
            let got: [CorePlayer]
            if let limit = (v["limit"] as? NSNumber)?.intValue {
                got = try await engine.search(query, limit: limit, exclude: exclude)
            } else {
                got = try await engine.search(query, exclude: exclude)  // wrapper default limit (8) = core default
            }
            XCTAssertEqual(got.map(\.name), v["out"] as! [String], query)
            for p in got { XCTAssertFalse(exclude.contains(p.id), "\(query): excluded \(p.id) came back") }
        }
    }

    func testPlayerAndTeamNames() async throws {
        // Not in the vectors, but the decoders behind search/player/teamLabel are what the UI renders.
        let engine = try makeEngine()
        let p = try await engine.player("T001")
        let player = try XCTUnwrap(p)
        XCTAssertEqual(player.id, "T001")
        XCTAssertFalse(player.name.isEmpty)
        XCTAssertFalse(player.stints.isEmpty)
        let missing = try await engine.player("nope")
        XCTAssertNil(missing)
        let label = try await engine.teamLabel("DEN", 2015)
        XCTAssertEqual(label, "2015 Broncos")
        let full = try await engine.teamFullName("DEN", 2015)
        XCTAssertEqual(full, "Denver Broncos")
    }

    // MARK: - Score and share

    func testScore() async throws {
        let engine = try makeEngine()
        for v in try group("score") {
            let state = try stateJSON(links: (v["links"] as! NSNumber).intValue,
                                      par: (v["par"] as! NSNumber).intValue,
                                      best: (v["best"] as? NSNumber)?.intValue,
                                      mode: v["mode"] as? String,
                                      status: v["status"] as! String, inc: 0, hints: 0)
            let got = try await engine.score(state)
            let want = try decode(Score.self, from: v["out"] as Any)
            let label = try jsonText(v)
            XCTAssertEqual(got, want, label)
        }
    }

    func testShareText() async throws {
        let engine = try makeEngine()
        for v in try group("shareText") {
            let p = v["puzzle"] as! [String: Any]
            let st = v["state"] as! [String: Any]
            let o = v["opts"] as? [String: Any] ?? [:]
            let puz = puzzle(n: (p["n"] as! NSNumber).intValue, best: (p["best"] as? NSNumber)?.intValue, par: (p["par"] as! NSNumber).intValue)
            // Absent options read as empty strings, which the core treats like absent ones (it defaults them).
            let opts = ShareOptions(url: o["url"] as? String ?? "", title: o["title"] as? String ?? "", emoji: o["emoji"] as? String ?? "",
                                    miss: o["miss"] as? String ?? "", lost: o["lost"] as? String ?? "", hardLabel: o["hardLabel"] as? String ?? "")
            let want = v["out"] as! String
            let got: String
            if st["par"] != nil {
                var full = st
                for (k, d) in [("n", puz.n), ("downs", 3)] as [(String, Any)] where full[k] == nil { full[k] = d }
                for (k, d) in [("start", "x"), ("end", "y")] where full[k] == nil { full[k] = d }
                if full["hintAt"] == nil { full["hintAt"] = [String: Any]() }
                got = try await engine.shareText(puz, GameState(json: jsonText(full)), options: opts)
            } else {
                // The state has no par (the core borrows it from the puzzle), which a GameState can't represent.
                got = try await engine.call(String.self, "shareText", [.value(puz), .json(jsonText(st)), .value(opts)])
            }
            XCTAssertEqual(got, want, "#\(puz.n) \(jsonTextOrEmpty(st))")
        }
    }

    private func jsonTextOrEmpty(_ o: Any) -> String { (try? jsonText(o)) ?? "" }

    // MARK: - Dates

    func testPuzzleNumberForDate() async throws {
        let engine = try makeEngine()
        for v in try group("puzzleNumberForDate") {
            let epoch = v["epoch"] as! String, ymd = v["ymd"] as! String
            let got = try await engine.puzzleNumber(puzzlesJSON: jsonText(["epoch": epoch]), date: ymd)
            XCTAssertEqual(got, (v["n"] as! NSNumber).intValue, "\(epoch) -> \(ymd)")
        }
    }

    func testEasternDate() async throws {
        let engine = try makeEngine()
        let iso = ISO8601DateFormatter()
        for v in try group("easternDate") {
            let utc = v["utc"] as! String
            let want = v["out"] as! String
            let date = try XCTUnwrap(iso.date(from: utc), utc)
            let got = try await engine.easternDate(date)
            XCTAssertEqual(got, want, "easternDate \(utc)")
            let ms = Int64(date.timeIntervalSince1970 * 1000)
            let fallback = try await engine.evaluate("H._easternDateFallback(new Date(\(ms)))")
            XCTAssertEqual(fallback, want, "_easternDateFallback \(utc)")
            // The core's own Date parsing agrees with Foundation's.
            let viaString = try await engine.evaluate("H.easternDate(new Date(\(CoreEngine.quote(utc))))")
            XCTAssertEqual(viaString, want, "easternDate(new Date(string)) \(utc)")
        }
    }

    // MARK: - Scripted games

    func testScriptedGames() async throws {
        let engine = try makeEngine()
        let puzzles = try fixturePuzzles()
        for g in try group("game") {
            let name = g["name"] as! String
            var p = puzzles[(g["puzzle"] as! NSNumber).intValue - 1]
            if g["legacy"] as? Bool == true {  // old data: no best, par = best
                p = Puzzle(n: p.n, date: p.date, start: p.start, end: p.end, best: nil, par: p.best ?? p.par,
                           kind: p.kind, theme: p.theme, chain: p.chain, optimal: p.optimal, game: p.game)
            }
            let noMode = g["noMode"] as? Bool == true
            let startMode = noMode ? GameMode.easy : (GameMode(rawValue: g["mode"] as? String ?? "") ?? .hard)
            var s = try await engine.newGame(p, mode: startMode)
            if noMode {  // saved before modes existed: the easy state with its mode field removed
                var obj = try jsonObject(s.json)
                obj["mode"] = nil
                s = try GameState(json: jsonText(obj))
                XCTAssertNil(s.view.mode, name)
            }

            var got: [String] = []
            for m in g["moves"] as! [[Any]] {
                switch m[0] as! String {
                case "g":
                    let r = try await engine.guess(s, playerID: m[1] as! String)
                    s = r.state
                    switch r.outcome {
                    case .link(let links): XCTAssertFalse(links.isEmpty, name); got.append("link")
                    case .solved(let links, let final): XCTAssertFalse(links.isEmpty || final.isEmpty, name); got.append("solved")
                    case .incompletion(let left): XCTAssertEqual(left, s.view.downs, name); got.append("incompletion")
                    case .lost: got.append("lost")
                    case .rejected(let reason): got.append("rejected:" + reason.rawValue)
                    }
                case "u":
                    s = try await engine.undo(s)
                    got.append("undo")
                case "m":
                    let r = try await engine.setMode(s, to: GameMode(rawValue: m[1] as! String)!)
                    s = r.state
                    got.append(r.refused.map { "mode:" + $0 } ?? "mode:ok")
                default:
                    let r = try await engine.hint(s)
                    s = r.state
                    if let e = r.error {
                        got.append("error:" + e)
                    } else {
                        let h = try XCTUnwrap(r.hint, "\(name): hint did not decode")
                        got.append("hint:\(h.team):\(h.season):\(h.pos ?? "nil")")
                    }
                }
            }
            XCTAssertEqual(got, g["results"] as! [String], name)

            // The state's own JSON (what's saved and fed back to the core) matches the vector, log included.
            let e = g["expect"] as! [String: Any]
            let obj = try jsonObject(s.json)
            let keys = ["chain", "downs", "inc", "hints", "status", "log"]
            XCTAssertEqual(obj.filter { keys.contains($0.key) } as NSDictionary, e.filter { keys.contains($0.key) } as NSDictionary, name)
            // ... and so does the decoded view.
            XCTAssertEqual(s.view.chain, e["chain"] as! [String], name)
            XCTAssertEqual(s.view.downs, (e["downs"] as! NSNumber).intValue, name)
            XCTAssertEqual(s.view.inc, (e["inc"] as! NSNumber).intValue, name)
            XCTAssertEqual(s.view.hints, (e["hints"] as! NSNumber).intValue, name)
            XCTAssertEqual(s.view.status.rawValue, e["status"] as? String, name)
            if e.keys.contains("mode") {
                XCTAssertEqual(s.view.mode?.rawValue, e["mode"] as? String, name + ": mode")  // null = no mode field
            }
            if let par = e["par"] as? NSNumber { XCTAssertEqual(s.view.par, par.intValue, name + ": par") }
            if let want = e["score"] {
                let sc = try await engine.score(s)
                let wantScore = try decode(Score.self, from: want)
                XCTAssertEqual(sc, wantScore, name)
            } else {
                XCTAssertEqual(s.view.status, .playing, name + ": finished games need a score")
            }
        }
    }

    // MARK: - Stats

    func testStats() async throws {
        let engine = try makeEngine()
        for sv in try group("stats") {
            let name = sv["name"] as! String
            var st = try await engine.newStats()
            for r in sv["records"] as! [[String: Any]] {
                let state = try stateJSON(links: (r["links"] as! NSNumber).intValue,
                                          par: (r["par"] as! NSNumber).intValue,
                                          best: (r["best"] as? NSNumber)?.intValue,
                                          mode: r["mode"] as? String,
                                          status: (r["won"] as! Bool) ? "won" : "lost",
                                          inc: (r["inc"] as! NSNumber).intValue,
                                          hints: (r["hints"] as! NSNumber).intValue)
                st = try await engine.recordResult(st, puzzleNumber: (r["n"] as! NSNumber).intValue, state: state)
            }
            let final = sv["final"] as! [String: Any]
            var got = try jsonObject(st.json)
            got["results"] = nil
            var want = final
            want["v"] = 1
            XCTAssertEqual(got as NSDictionary, want as NSDictionary, name)

            // The decoded view matches too.
            let v = st.view
            XCTAssertEqual([v.played, v.won, v.cur, v.max, v.parCur, v.parMax, v.last, v.lastWon],
                           ["played", "won", "cur", "max", "parCur", "parMax", "last", "lastWon"].map { (final[$0] as! NSNumber).intValue }, name)
            let wantHist = try decode([String: Int].self, from: final["hist"] as Any)
            XCTAssertEqual(v.hist, wantHist, name)

            for (n, mode) in sv["modes"] as? [String: String] ?? [:] {
                XCTAssertEqual(v.results[n]?.mode?.rawValue, mode, "\(name) result \(n)")
            }
            for d in sv["display"] as! [[String: Any]] {
                let today = (d["today"] as! NSNumber).intValue
                let streaks = try await engine.displayStreaks(st, todayNumber: today)
                let wantStreaks = try decode(Streaks.self, from: d["out"] as Any)
                XCTAssertEqual(streaks, wantStreaks, "\(name) @\(today)")
            }
        }
    }

    // MARK: - The real bundled data

    /// Builds the engine from the app's real players.json, times `buildIndex`, and checks today's
    /// puzzle number lands on a puzzle in the bundled puzzles.json (so the shipped data is current).
    func testRealBundledDataHasTodaysPuzzle() async throws {
        let playersURL = try XCTUnwrap(Bundle.main.url(forResource: "players", withExtension: "json"), "app bundle has no players.json")
        let puzzlesURL = try XCTUnwrap(Bundle.main.url(forResource: "puzzles", withExtension: "json"), "app bundle has no puzzles.json")
        let playersJSON = try Data(contentsOf: playersURL)

        let clock = ContinuousClock()
        var engine: CoreEngine!
        let elapsed = try clock.measure { engine = try CoreEngine(bundle: .main, playersJSON: playersJSON) }
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        print(String(format: "BUILD_INDEX_TIMING: CoreEngine init (load core + buildIndex of %d KB players.json) took %.0f ms", playersJSON.count / 1024, ms))
        XCTAssertLessThan(ms, 30_000, "buildIndex is absurdly slow")

        let puzzlesText = try String(contentsOf: puzzlesURL, encoding: .utf8)
        let file = try JSONDecoder().decode(PuzzlesFile.self, from: Data(puzzlesText.utf8))
        XCTAssertFalse(file.puzzles.isEmpty)

        let today = try await engine.easternDate()
        let n = try await engine.puzzleNumber(puzzlesJSON: puzzlesText, date: today)
        print("TODAY: \(today) = puzzle #\(n) (bundled puzzles: \(file.puzzles.count), last #\(file.puzzles.last?.n ?? 0))")
        let todays = try XCTUnwrap(file.puzzles.first { $0.n == n }, "today (\(today)) is puzzle #\(n), which puzzles.json does not contain")
        XCTAssertEqual(todays.date, today, "puzzle #\(n) is dated \(todays.date), not \(today)")

        // The puzzle's players exist and a game on it starts.
        let start = try await engine.player(todays.start)
        let end = try await engine.player(todays.end)
        XCTAssertNotNil(start, "start player \(todays.start) is not in players.json")
        XCTAssertNotNil(end, "end player \(todays.end) is not in players.json")
        let path = try await engine.shortestPath(todays.start, todays.end)
        let route = try XCTUnwrap(path, "no path between today's players")
        if let best = todays.best { XCTAssertEqual(route.dist, best, "puzzle best vs shortestPath") }
        let game = try await engine.newGame(todays, mode: .hard)
        XCTAssertEqual(game.view.chain, [todays.start])
        XCTAssertEqual(game.view.par, todays.par + 1)  // hard = easy par + 1... see parFor
    }
}
