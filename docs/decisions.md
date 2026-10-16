# Decisions

## Multi-sport from day one (Oct 16, 2026)

Charlie doesn't want the game to be NFL-only, so nothing below the client's sport registry knows about the NFL:

- **Data:** each sport has its own folder, `data/<sport>/players.json` and `puzzles.json`, carrying a `sport` field. Teams, labels and colours live in the data.
- **Core:** `handoff-core.js` holds no hard-coded teams. Share text takes `title` and `emoji`.
- **Web:** `web/sports.js` holds the sport-specific words, such as "downs", "incompletion" and "Turnover on downs". There is no sport picker until a second sport exists.
- **Pipeline:** `tools/build_data.py` is the NFL builder. A new sport needs its own builder that writes the same format. Pipeline steps 4 and 5 (graph, BFS, puzzle picking) are generic and can be pulled into a shared module when the second sport lands.

**Name: Chainmates** (Charlie, Oct 16, 2026). It's sport-neutral, and each sport is a mode: "Chainmates · Football". The football vocabulary (downs, incompletion, turnover on downs) belongs to the football mode. The domain chainmates.app looked unregistered on Oct 16; buy it before announcing. The share URL stays `cev64.github.io/chainmates/` until then. Renaming the GitHub repo is optional, but Pages URLs follow the repo name.

**Data sources to check per sport:**

| Sport | Option | Licence status |
|---|---|---|
| MLB | Lahman / Chadwick Bureau | open licences |
| NBA / WNBA | `hoopR` / `wehoop` (sportsdataverse) | check licences |
| NHL | the `fastRhockey` data releases | check licences |

Apply the same rule as for the NFL: use no scraping of sites whose terms forbid it.

## Rules (v1)

- **Teammates = the 53-man roster** (Charlie). Two players are teammates if both were on the same team's 53-man roster (weekly status `ACT` or `INA`) in the same season, or recorded a stat or snap for it.
  - Practice squad, IR/reserve lists and preseason-only players don't count.
  - The rule is season-level, so a player traded mid-season is a teammate of everyone on both teams that season, even players who left before the trade. That keeps the reason simple ("Teammates on the 2015 Broncos"). Requiring overlapping weeks would need week ranges in the data; revisit only if playtesters object.

- **3 downs** (Charlie). Hints cost a down and are refused on the last down.
- **Eras:** 2002 onward only (Charlie).
- **Price:** free, with no monetization in v1 (Charlie). The later paid tier is "unlimited plays" (free play / random pairs). It would use StoreKit on iOS, with no prices or "Pro" wording in the app before then.
- **Deep cuts:** about 30% of Fridays use one endpoint from fame ranks 400–1200.
- **Difficulty** comes from par plus the number of optimal routes, not par alone. Par 4 doesn't exist among recognisable players since 2002 (see `spec.md`).

## Playtest round 1 (Charlie, Oct 17, 2026)

- **Par = fewest links + 1.**
  - An optimal chain is a **Birdie** (−1), and one extra link is Par.
  - Puzzles store `best` (fewest links) and `par`. The difficulty calendar is written in terms of `best`.
- **Hints reveal a team-season and a position.**
  - They point at the most famous player who fits the next link on an optimal path, for example "Go deep: a wide receiver on the 2012 Broncos is wide open."
  - The copy is per position group in `web/sports.js`. Templates are picked per puzzle and chain position, so a reload shows the same line.
- **Stars-only endpoints.** Charlie watches a lot of football and didn't know several endpoints, because the fame score was stats volume and rewarded long careers.
  - Fame now adds Pro Bowls, All-Pros and the Hall of Fame from nflverse `draft_picks`.
  - **What counts as a star:**
    - 2+ Pro Bowls, an All-Pro, the Hall of Fame, or 1 Pro Bowl for players who debuted in 2020 or later
    - undrafted players with a big production line (Romo, Gates, Welker)
    - at least 48 games since 2002
    - real offensive or defensive production, so kick returners and pre-2002 careers are out
  - **Pool sizes:** Monday uses the top 120 stars, Tuesday and Thursday the top 200, other days all ~314 stars.
  - **Friday deep cuts** (20% of Fridays) are one-time Pro Bowlers or long productive careers.

## Playtest round 2 (Charlie, Oct 17, 2026)

- **Prime-time puzzles feature a player from the game.**
  - These are Thursday Night, Sunday Night and Monday Night, plus Saturday games, Thanksgiving Night and Christmas.
  - One endpoint is a current (this season) star from either team, or, if neither team has a star free, another notable player from those rosters.
  - The theme reads "Monday Night: Bills at Rams", and the puzzle stores `game: {slot, away, home}`.
  - The franchise-weekend themes are gone.
- **Flexed games.** The data workflow runs every morning, August through February, and reads the nflverse schedule fresh (cache of 6 hours or less).
  - A future puzzle is re-picked when its date's featured game changed (flex, a move, or a new season's schedule).
  - It is also re-picked when its game-day player is no longer on either roster.
  - Today and earlier stay frozen.
- **Era mix for a younger audience.**
  - At least one endpoint played in the last five seasons.
  - About 40% of puzzles use two current players.
  - Never two players from way back.
  - Who starts and who finishes is a coin flip.
- **Hard mode is the default.**
  - It shows no teams for players, in the chain or in search; position and years stay so same-name players can be told apart.
  - Par = best + 2, so an optimal chain is an **Eagle**. Eagles are only possible on hard.
- **Easy mode** shows every team a player was on, with years, and par = best + 1.
- **Switching mode mid-game.**
  - Hard → easy is allowed mid-game; par drops by one.
  - Easy → hard only before the first move.
- **Hard stays the default** (Charlie). Only a choice made before the first move changes the saved default. Dropping to easy mid-game applies to that puzzle only.
- **Hero and help dialog.** The hero shows only "Par N". The puzzle explainer ("birdie in 4 · eagle in 3 … the shortest chain takes 3 links") lives in the ? dialog.

## Playtest round 3: friends found it too hard (Charlie, Oct 16, 2026)

- **Every endpoint entered the league after 2010:** drafted in 2011 or later, or an undrafted rookie from 2011 on.
- **Fantasy positions first.**
  - Endpoints are QB/RB/WR/TE stars, meaning a real fantasy season backed by Pro Bowls or All-Pros, a 1,100-point PPR career, or a 260-point PPR season.
  - A Pro Bowl only counts with a 150-point PPR season, so return specialists are out.
- **Defenders only if they're household names:** 3+ All-Pros, or 2 All-Pros and 6 Pro Bowls (Aaron Donald, T.J. Watt, Micah Parsons…).
  - About one puzzle in eight has one.
  - A puzzle never has two.
- **Easier calendar.**
  - Monday through Thursday and Saturday are 2-link puzzles with plenty of routes.
  - Friday and Sunday are the 3-link days.
  - Friday deep cuts are gone.
- **Variety.** A player appears as an endpoint at most 6 times a year, and not again within about 3 weeks.
- **Rebuilt in full.** All puzzles, including the ones already played, were remade with these rules (Charlie). Numbering is unchanged: No. 1 is still Oct 12.

## Two in the middle (Charlie, Oct 16, 2026)

- **Mix:** Charlie likes 2 players in the middle and wants each puzzle to have 1, 2 or 3 in the middle.
- **Calendar:** Tuesday, Thursday, Friday and Sunday aim for 2 in the middle, about 143 puzzles a year. Monday, Wednesday and Saturday have 1.
- **No 3-in-the-middle days:** that never happens between post-2010 stars.
- **Pool for 2-in-the-middle days:** stars come first. When star pairs run out, the far end may be a wider post-2010 fantasy name.

## Five 2-in-the-middle days, 2009 class (Charlie, Oct 16, 2026)

- **Calendar:** 2 in the middle on Tuesday, Thursday, Friday, Saturday and Sunday. 1 on Monday and Wednesday.
- **Entry year moved to 2009** (Charlie) for enough 2-in-the-middle pairs. That brings in Stafford, Gronk, Antonio Brown and others.
- **Rolling caps:** 8 appearances per player in any 365 days, and pairs may repeat after a year. A simulated second year still filled every 2-in-the-middle day.
- **Off-field crimes:** players best known for them are never endpoints (`NOT_ENDPOINTS`).

## iOS architecture: run `handoff-core.js` in JavaScriptCore; keep search and UI native

Pigskin Pantheon runs its whole site engine in a hidden WKWebView, because its engine is large and DOM-adjacent. Chainmates' core is different. It is about 430 lines of pure ES2018 with no DOM, fetch, timers or Intl dependency (Intl has a fallback), and it is exported as a UMD.

**Plan:**
- Bundle `core/handoff-core.js` and call it through a `JSContext` (JavaScriptCore). That is synchronous, has no web process, and starts in milliseconds.
- **The JS core owns:**
  - chain validation and why-valid lookups
  - guess, undo and hint state transitions
  - scoring, share text and stats/streaks
  - date-to-puzzle mapping

  These rules must match the web exactly, and they are tested once in Node.
- **Native Swift owns:**
  - autocomplete search over a Swift array, with the 120 ms debounce from `PlayerSearchScreen`
  - decoding `players.json` for display
  - all UI
- **`core/test/vectors.json`** holds shared input→output vectors. The iOS unit tests run the bundled JS against them, which proves the bridge round-trips correctly.

  If JavaScriptCore's non-JIT interpreter turns out too slow on old devices, the same vectors let us port the core to Swift function by function and verify each port. `buildIndex` takes about 90 ms in Node; expect a few hundred ms in a non-JIT JavaScriptCore, so build the index once at launch, off the main thread.

**Why not port to Swift now?** Two implementations of scoring and share text drift apart. The core will change during playtesting (downs, hint cost, rules), and every rule change would have to land twice.

## Backend (later): Convex vs Supabase

There is no backend for the MVP. Friend leagues and global "% made par" stats need one in v2.

**Convex**
- Pricing: per team/usage rather than per project.
- Fit: reactive queries suit live leaderboards. Its TypeScript functions could import `handoff-core.js` to re-validate submitted chains server-side.
- Drawback: a new stack for Charlie.

**Supabase**
- Pricing: the free tier pauses idle projects, and the paid plan is per project.
- Fit: Charlie already runs it for Pigskin Pantheon, including auth and account deletion, and that code can be copied.
- Drawback: it's Postgres plus RLS, so it's more SQL to own.

**Recommendation:** decide when friend leagues are actually scheduled. Global stats alone could be one Convex table, or one Supabase table plus an RPC.
