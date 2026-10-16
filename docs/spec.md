# Chainmates spec: data files, rules, and core API

This is the contract between `tools/build_data.py`, which produces the data, `core/handoff-core.js`, which holds the logic, and the clients (`web/`, and later `ios/`).

**Multi-sport:** everything is per sport. Data lives in `data/<sport>/players.json` and `data/<sport>/puzzles.json`, and both carry a `"sport"` field (NFL is `nfl`). The core holds no team or sport knowledge; teams, labels and colours all come from `players.json`. Sport-specific words, such as "downs" and "incompletion", live in the client's sport registry (`web/sports.js`).

## Difficulty calendar (as built)

NFL rosters carry 53 or more players, so the teammate graph is very dense:
- Among the ~400 most famous players, every pair is 1–3 links apart.
- A best of 4 essentially never happens. It shows up in 4 pairs out of 1.2M, even with the top 3,000 players.

So difficulty comes from **`best` (the fewest links possible) and the number of optimal routes**. Pairs with a best of 2 have a median of 15 optimal routes; pairs with a best of 3 have a median of about 500. The displayed par is always `best + 1` (see "Rules"), so none of the numbers below are par.

| Day | Best (fewest links) | Optimal routes | Endpoint pool | Notes |
|---|---|---|---|---|
| Mon | 2 | ≥ 20 | top 120 stars | easy |
| Tue | 2 | 8–19 | top 200 stars | |
| Wed | 3 | any | top 300 stars | |
| Thu | 2 | 3–7 | top 200 stars | you need to know one of the few links |
| Fri | 3 | ≤ 300 | top 300 stars | about 20% of Fridays use a "deep cut" endpoint: a one-time Pro Bowler or a long, productive career |
| Sat | 3 (falls back to 2) | any | all stars | themed: "{home team of Sunday Night Football} weekend". Both endpoints played for that franchise, at least 4 seasons apart. |
| Sun | 3 (falls back to 2) | any | all stars | themed: "Sunday Night: {away} at {home}". One endpoint from each team. |

Within each pool, endpoints are picked with a lean toward fame (a weighted shuffle), and the second endpoint prefers a different position and era.

**What counts as a star** (endpoints are stars only, so players should be recognisable):
- 2 or more Pro Bowls, an All-Pro selection, the Hall of Fame, or 1 Pro Bowl for players who debuted in 2020 or later. Undrafted players qualify on production instead.
- At least 48 games since 2002, and real offensive or defensive production. Kick returners and pre-2002 careers are out.
- Honors come from nflverse `draft_picks`. Fame adds Pro Bowls, All-Pros and the Hall of Fame on top of the stats volume.

- Outside the season, weekends rotate franchise themes.
- `tools/puzzle_overrides.json` pins hand-picked pairs to dates, for holidays and big games.
- Kickers, punters and linemen are never endpoints, though they are valid links.

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
- **Best** = the shortest possible number of links (the graph distance). Puzzles always have best ≥ 2.
- **Par** = `best + 1`. Finding an optimal chain therefore beats par, so the game has a **Birdie** (−1). One extra link is **Par**.
- **Downs:** 3. An invalid guess, meaning the guessed player is not a teammate of the last player, is an *incompletion* and costs one down. At 0 downs the result is *turnover on downs* and the puzzle is lost.
- These guesses are rejected with **no** down cost:
  - unknown players
  - players already in the chain
  - the start player
  - the end player, when the last player is not their teammate. A valid guess of the end player is never possible, because the puzzle auto-solves first.
- **Undo** removes the last added middle player, for free. You can't undo after the game is over.
- **Hint** costs a down. It isn't allowed when only 1 down is left, because it would end the game.
  - It reveals the team-season of the **next link on some optimal path from the current last player to `end`**, plus the **position of the player you would pick there**, for example `{team:"DEN", season:2012, pos:"WR"}`. It never reveals a name.
  - The hint is chosen deterministically: compute a shortest path from the last player to end (`shortestPath` prefers the most famous candidate at each step), and reveal its first link and the position of the next player on it.
  - Calling hint again at the same chain position returns the same hint at no extra cost.
  - Hints are counted on the result.
- **Score** = `over` = `max(best, links) − par`, golf style. It can be negative, but never below `best − par` (−1 in real data).
  - Labels: −1 → "Birdie", −2 → "Eagle", −3 → "Albatross", 0 → "Par", n → "+n". Any other negative number is shown as is.
  - A lost game has no score and is labelled "X".
  - Data refreshes can shorten a path, so fewer links than `best` count as `best`: it is still a Birdie, never better.
  - Older puzzle data has no `best`. It then falls back to `best = par`, so those puzzles can't be beaten.

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
      "best": 3,
      "par": 4,
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
- `best` is the fewest links possible (the graph distance from `start` to `end`), always ≥ 2. `par` is `best + 1`.
- `chain` holds an optimal chain of `best + 1` player ids. `links[i]` is the team-season joining `chain[i]` and `chain[i+1]`, so `links` has `best` entries.
- `optimal` is the number of distinct shortest **player sequences** from start to end.

## Puzzle numbering and time zone

- The puzzle for a moment `t` is the one whose `date` equals the calendar date of `t` in **America/New_York**. It rolls over at midnight Eastern.
- `puzzleNumberForDate("YYYY-MM-DD")` = days since epoch + 1, computed from UTC date arithmetic on the Y-M-D strings so DST can't shift it.

## Share text

```
Chainmates #42 🏈
🟩🟩🟩🟩 4 links · Par 4 ⛳
🟥 1 incompletion
cev64.github.io/handoff/#42
```

- **Link squares:** one square per link. The first `par` squares are 🟩 and any extra links are 🟨. A Birdie shows fewer squares than par.
- **The second line's ending** (`link` is singular for exactly one link):
  - At par it ends with ` · Par 4 ⛳`.
  - Over par it reads `🟩🟩🟩🟩🟨 5 links · Par 4 (+1)`.
  - Under par it names the score: `🟩🟩🟩 3 links · Par 4 · Birdie 🐦` (an Eagle reads `· Eagle 🐦`).
- **Incompletions:** one line `🟥 N incompletion(s)`, omitted when N = 0. The word is `opts.miss` (default `"incompletion"`), pluralised with an "s".
- **Hints:** `💡 N hint(s)`, omitted when 0.
- **Lost:** the second line is `🏳️ Turnover on downs · Par 4`, followed by the incompletion and hint lines. The phrase is `opts.lost` (default `"Turnover on downs"`).
- **Sport words:** `miss` and `lost` are the only sport-specific words in the share text. Other sports pass their own, such as `{miss: "turnover", lost: "Out of lives"}`.
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
  "hist": { "-1": 0, "0": 0, "1": 0, "2": 0, "3": 0, "X": 0 },
  "results": {}
}
```

- `hist` counts strokes against par: `"-1"` is a Birdie or better, `"0"` is par, `"1"` is +1, `"2"` is +2, `"3"` is +3 or more, and `"X"` is lost. The bucket is `max(-1, min(3, over))`. Stats saved before the `"-1"` bucket existed gain it on the next result.
- `results` is keyed by puzzle number: `{ "42": { "links": 3, "par": 4, "inc": 1, "hints": 0, "won": true } }`.
- **Win streak (`cur`):** it increments when you win puzzle `n` and the last *won* daily was `n-1`, or when it is your first win. Otherwise it resets to 1 on a win, and to 0 on a loss.
- **Par streak (`parCur`):** consecutive daily puzzles finished at **par or better** (`over <= 0`, so a Birdie keeps it going), under the same consecutive-number rule. A loss, or a win over par, resets it to 0.
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
H.newGame(puzzle, {downs=3})  // state: {n, start, end, par, best, chain:[start], downs, inc, hints, hintAt:{}, status:"playing"|"won"|"lost", log:[]}
H.guess(index, state, id)     // -> {state, result} (state is a NEW object; inputs never mutated)
   // result.kind: "link" {links:[{team,season}]} | "solved" {links, final:[{team,season}]} |
   //              "incompletion" {downsLeft} | "lost" | "rejected" {reason:"unknown"|"in-chain"|"start"|"end"|"over"}
H.undo(state)                 // -> state (no-op if chain has only start or game over)
H.hint(index, state)          // -> {state, hint:{team,season,pos}} | {state, error:"last-down"|"over"|"none"}
H.score(state)                // {links, par, best, over, label:"Birdie"|"Eagle"|"Par"|"+1"|"X"|..., won}
H.shareText(puzzle, state, {url="cev64.github.io/handoff/", title="Chainmates", emoji="🏈", miss="incompletion", lost="Turnover on downs"}) // string per spec
H.newStats() / H.recordResult(stats, puzzleN, state) -> stats / H.displayStreaks(stats, todayN) -> {cur, max, parCur, parMax}
```

- **`newGame`** copies `best` from the puzzle. A puzzle without `best` (older data) gets `best = par`.
- **`hint`** returns `pos`, the position of the next player on the shortest path (the most famous candidate at each step). Hints cached in `state.hintAt` hold the same three fields; one saved by an older version has no `pos`.
- **`guess` with `link`:** `links` lists the team-seasons the two players shared (from `sharedTeams`), so the UI can show "Teammates on the 2015 Broncos" and "+2 more".
- **`guess` when solved:** the final step is the last guessed player to `end`, so `final` is `sharedTeams(last, end)`.
- `state.log` is the move list, for replay or analytics. Entries look like `{t:"g", id, ok}`, `{t:"u"}` or `{t:"h", team, season}`.
- **`state` must be JSON-serializable**, so it can be persisted mid-game in localStorage or UserDefaults.
