# Chainmates spec: data files, rules, and core API

This is the contract between `tools/build_data.py`, which produces the data, `core/handoff-core.js`, which holds the logic, and the clients (`web/`, and later `ios/`).

**Multi-sport:** everything is per sport. Data lives in `data/<sport>/players.json` and `data/<sport>/puzzles.json`, and both carry a `"sport"` field (NFL is `nfl`). The core holds no team or sport knowledge; teams, labels and colours all come from `players.json`. Sport-specific words, such as "downs" and "incompletion", live in the client's sport registry (`web/sports.js`).

## Difficulty calendar (as built)

NFL rosters carry 53 or more players, so the teammate graph is very dense:
- Among the ~400 most famous players, every pair is 1–3 links apart.
- A par of 4 essentially never happens. It shows up in 4 pairs out of 1.2M, even with the top 3,000 players.

So difficulty comes from **par and the number of optimal routes**. Par-2 pairs have a median of 15 optimal routes; par-3 pairs have a median of about 500.

| Day | Par | Optimal routes | Endpoint pool | Notes |
|---|---|---|---|---|
| Mon | 2 | ≥ 20 | top 200 | easy |
| Tue | 2 | 8–19 | top 300 | |
| Wed | 3 | any | top 400 | |
| Thu | 2 | 3–7 | top 300 | you need to know one of the few links |
| Fri | 3 | ≤ 300 | top 400 | about 30% of Fridays use a "deep cut" endpoint (fame rank 400–1200) |
| Sat | 3 (falls back to 2) | any | top 400 | themed: "{home team of Sunday Night Football} weekend". Both endpoints played for that franchise, at least 4 seasons apart. |
| Sun | 3 (falls back to 2) | any | top 400 | themed: "Sunday Night: {away} at {home}". One endpoint from each team. |

Within each pool, endpoints are picked with a lean toward fame (a weighted shuffle), and the second endpoint prefers a different position and era.

- Outside the season, weekends rotate franchise themes.
- `tools/puzzle_overrides.json` pins hand-picked pairs to dates, for holidays and big games.
- The endpoint pool is the top 400 by fame, about 65% QB/RB/WR/TE and 35% defenders. Kickers, punters and linemen are never endpoints, though they are valid links.

## Stints (who counts as a teammate)

A player has a stint for a team-season (the 53-man roster rule) if any of these is true:
- they have a stat line for that team in any game, from `stats_player_week`
- they played at least 1 snap, from `snap_counts` (2012 onward). Super Bowl rows are dropped, because their teams are swapped in some seasons.
- they had `ACT` or `INA` status in a week in `roster_weekly`, meaning they were on the 53-man roster

Practice squad (`DEV`), reserve lists (`RES`) and cuts are excluded. A player traded mid-season has a stint with both teams that season.

## Rules (v1)

- A **link** joins two players who were **teammates**: on the same team's 53-man roster in the same season (see "Stints" below). Regular season and playoffs both count.
- A chain is `[start, m1, m2, ..., end]`. Links = `chain.length - 1`.
  - The player adds the middle players one at a time.
  - Each added player must be a teammate of the **current last player** of the chain.
  - The puzzle is **solved** as soon as the last added player is a teammate of `end`; `end` is then appended automatically.
- **Par** = the shortest possible number of links (the graph distance). Puzzles always have par ≥ 2.
- **Downs:** 3. An invalid guess, meaning the guessed player is not a teammate of the last player, is an *incompletion* and costs one down. At 0 downs the result is *turnover on downs* and the puzzle is lost.
- These guesses are rejected with **no** down cost:
  - unknown players
  - players already in the chain
  - the start player
  - the end player, when the last player is not their teammate. A valid guess of the end player is never possible, because the puzzle auto-solves first.
- **Undo** removes the last added middle player, for free. You can't undo after the game is over.
- **Hint** costs a down. It isn't allowed when only 1 down is left, because it would end the game.
  - It reveals the team-season of the **next link on some optimal path from the current last player to `end`**, for example `{team:"DEN", season:2012}`.
  - The hint is chosen deterministically: compute a shortest path from the last player to end, and reveal its first link.
  - Calling hint again at the same chain position returns the same hint at no extra cost.
  - Hints are counted on the result.
- **Score** = links − par.
  - Labels: 0 → "Par", n → "+n".
  - A lost game has no score and is labelled "X".
  - Data refreshes can shorten a path, so a negative score is clamped to 0 in the label.

## Team codes and display

Stints use the **season-accurate** abbreviation:

| Team | Abbreviations |
|---|---|
| Raiders | `OAK` ≤2019, `LV` 2020+ |
| Chargers | `SD` ≤2016, `LAC` 2017+ |
| Rams | `STL` ≤2015, `LA` 2016+ |

All other teams use their current nflverse abbreviation: ARI, ATL, BAL, BUF, CAR, CHI, CIN, CLE, DAL, DEN, DET, GB, HOU, IND, JAX, KC, LA, LAC, LV, MIA, MIN, NE, NO, NYG, NYJ, PHI, PIT, SEA, SF, TB, TEN, WAS.

Display a team-season as `"{season} {nickname}"`, for example "2015 Broncos" or "2018 Raiders".

Washington's nickname by season:

| Seasons | Display |
|---|---|
| 2002–2019 | "Washington" |
| 2020–2021 | "Football Team" |
| 2022+ | "Commanders" |

`players.json` carries a `teams` table so clients never hard-code these labels.

## `data/<sport>/players.json`

```json
{
  "v": 1,
  "sport": "nfl",
  "built": "2026-10-16",
  "seasons": [2002, 2026],
  "source": "nflverse (CC-BY 4.0)",
  "teams": {
    "DEN": { "name": "Broncos", "city": "Denver", "franchise": "DEN", "c1": "#FB4F14", "c2": "#002244" },
    "OAK": { "name": "Raiders", "city": "Oakland", "franchise": "LV", "c1": "#000000", "c2": "#A5ACAF" },
    "WAS": { "name": "Commanders", "city": "Washington", "franchise": "WAS", "c1": "...", "c2": "...",
             "names": [[2002, 2019, "Washington"], [2020, 2021, "Football Team"], [2022, 9999, "Commanders"]] }
  },
  "players": [
    ["00-0010346", "Peyton Manning", "QB", 987, "IND:1998-2010;DEN:2012-2015"]
  ]
}
```

- `players` holds **arrays**, to keep the file compact: `[id, name, pos, fame, stints]`.
  - They are sorted by fame, descending.
  - `fame` is an integer from 0 to 999. A higher number means more famous. It ranks autocomplete and picks puzzle endpoints.
- `stints` is a list of `TEAM:startSeason-endSeason`, or `TEAM:season` for a single season, separated by `;`.
  - Each range covers *consecutive* seasons with that same abbreviation.
  - A player traded mid-season appears on both teams for that season: `"NYJ:2010;MIN:2010;NE:2010"`.
  - The order is chronological by start season, with ties in any order.
- A team's optional `names` list overrides `name` by season range: `[from, to, name]`.
- `c1` is the primary colour and `c2` the secondary or text colour, used for club chips.
- Only seasons from 2002 onward exist in the data.

## `data/<sport>/puzzles.json`

```json
{
  "v": 1,
  "epoch": "2026-10-12",
  "tz": "America/New_York",
  "puzzles": [
    {
      "n": 1,
      "date": "2026-10-12",
      "start": "00-0010346",
      "end": "00-0036900",
      "par": 3,
      "kind": "mon",
      "theme": null,
      "chain": ["00-0010346", "00-00xxxxx", "00-00yyyyy", "00-0036900"],
      "links": [["DEN", 2012], ["CIN", 2020], ["CIN", 2021]],
      "optimal": 14
    }
  ]
}
```

- Puzzle `n` falls on date `epoch + (n-1)` days, so `puzzles[i].n === i + 1`.
- `kind` is the weekday code: `mon`, `tue`, `wed`, `thu`, `fri`, `sat` or `sun`.
- `theme` is a short string on themed days, for example `"Packers weekend"`, and `null` otherwise.
- `chain` holds `par + 1` player ids. `links[i]` is the team-season joining `chain[i]` and `chain[i+1]`.
- `optimal` is the number of distinct shortest **player sequences** from start to end.

## Puzzle numbering and time zone

- The puzzle for a moment `t` is the one whose `date` equals the calendar date of `t` in **America/New_York**. It rolls over at midnight Eastern.
- `puzzleNumberForDate("YYYY-MM-DD")` = days since epoch + 1, computed from UTC date arithmetic on the Y-M-D strings so DST can't shift it.

## Share text

```
Chainmates #42 🏈
🟩🟩🟩 3 links · Par 3 ⛳
🟥 1 incompletion
cev64.github.io/handoff/#42
```

- **Link squares:** one square per link. The first `par` squares are 🟩 and any extra links are 🟨.
- **The second line's ending:**
  - At par it ends with ` · Par 3 ⛳`.
  - Over par it reads `🟩🟩🟩🟨 4 links · Par 3 (+1)`.
- **Incompletions:** one line `🟥 N incompletion(s)`, omitted when N = 0.
- **Hints:** `💡 N hint(s)`, omitted when 0.
- **Lost:** the second line is `🏳️ Turnover on downs · Par 3`, followed by the incompletion and hint lines.
- **URL:** the last line is `{url}#{n}`. The base URL is a config option, defaulting to `cev64.github.io/handoff/`.
- **Never** include player or team names in the share text.

## Stats (local, daily puzzles only; archive and practice plays don't count)

```json
{
  "v": 1,
  "played": 0,
  "won": 0,
  "cur": 0,
  "max": 0,
  "parCur": 0,
  "parMax": 0,
  "last": 0,
  "lastWon": 0,
  "hist": { "0": 0, "1": 0, "2": 0, "3": 0, "X": 0 },
  "results": {}
}
```

- `hist` counts strokes over par: `"0"` is par, `"1"` is +1, `"2"` is +2, `"3"` is +3 or more, and `"X"` is lost.
- `results` is keyed by puzzle number: `{ "42": { "links": 3, "par": 3, "inc": 1, "hints": 0, "won": true } }`.
- **Win streak (`cur`):** it increments when you win puzzle `n` and the last *won* daily was `n-1`, or when it is your first win. Otherwise it resets to 1 on a win, and to 0 on a loss.
- **Par streak (`parCur`):** consecutive daily puzzles finished exactly at par, under the same consecutive-number rule. A loss, or a win over par, resets it to 0.
- Recording the same puzzle twice is a no-op.
- When displaying, `cur` (and `parCur`) shows as 0 if the last win (or last par result) is older than yesterday's puzzle.

## Core API (`core/handoff-core.js`)

The core is pure JavaScript (ES2018). It has:
- no DOM
- no `fetch`
- no timers
- no `Intl` dependency, except in `easternDate`, which falls back to a manual US DST rule.

It exports a UMD module. That makes it `module.exports` in Node, `globalThis.HandoffCore` in browsers, and it works in JavaScriptCore.

```js
const H = HandoffCore;
H.DOWNS                      // 3
H.parseStints("DEN:2012-2015;IND:2010") // [{team:"DEN",season:2012},...,{team:"IND",season:2010}]
H.buildIndex(playersJson)    // -> index (opaque); fast lookups + teammate graph
H.player(index, id)          // -> {id,name,pos,fame,stints:[{team,season}],first,last} | null
H.teamLabel(index, team, season) // "2015 Broncos"
H.teamFullName(index, team, season) // "Denver Broncos"
H.sharedTeams(index, a, b)   // [{team,season}] sorted season desc, then team; [] if never teammates
H.areTeammates(index, a, b)  // boolean
H.shortestPath(index, a, b)  // {dist, path:[ids], links:[{team,season}], count} | null; BFS, count = # shortest player sequences
H.validateChain(index, ids)  // {ok:true, links:[{team,season}]} | {ok:false, at:i, reason}
H.normalize(str)             // lowercase, strip accents/punctuation/suffix dots; "Ja'Marr" -> "jamarr"
H.search(index, query, {limit=8, exclude=[]}) // ranked players: full-name prefix > word prefix > substring, then fame desc
H.easternDate(date = new Date()) // "YYYY-MM-DD" in America/New_York
H.puzzleNumberForDate(puzzlesJson, ymd) // integer (may be <1 or > length)
H.puzzleForDate(puzzlesJson, ymd)       // puzzle | null
H.puzzleByNumber(puzzlesJson, n)        // puzzle | null
H.newGame(puzzle, {downs=3})  // state: {n, start, end, par, chain:[start], downs, inc, hints, hintAt:{}, status:"playing"|"won"|"lost", log:[]}
H.guess(index, state, id)     // -> {state, result} (state is a NEW object; inputs never mutated)
   // result.kind: "link" {links:[{team,season}]} | "solved" {links, final:[{team,season}]} |
   //              "incompletion" {downsLeft} | "lost" | "rejected" {reason:"unknown"|"in-chain"|"start"|"end"|"over"}
H.undo(state)                 // -> state (no-op if chain has only start or game over)
H.hint(index, state)          // -> {state, hint:{team,season}} | {state, error:"last-down"|"over"|"none"}
H.score(state)                // {links, par, over, label:"Par"|"+1"|"X", won}
H.shareText(puzzle, state, {url="cev64.github.io/handoff/", title="Chainmates", emoji="🏈"}) // string per spec
H.newStats() / H.recordResult(stats, puzzleN, state) -> stats / H.displayStreaks(stats, todayN) -> {cur, max, parCur, parMax}
```

- **`guess` with `link`:** `links` lists the team-seasons the two players shared (from `sharedTeams`), so the UI can show "Teammates on the 2015 Broncos" and "+2 more".
- **`guess` when solved:** the final step is the last guessed player to `end`, so `final` is `sharedTeams(last, end)`.
- `state.log` is the move list, for replay or analytics. Entries look like `{t:"g", id, ok}`, `{t:"u"}` or `{t:"h", team, season}`.
- **`state` must be JSON-serializable**, so it can be persisted mid-game in localStorage or UserDefaults.
