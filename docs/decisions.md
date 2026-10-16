# Decisions

## Multi-sport from day one (Oct 16, 2026)

Charlie doesn't want Handoff to be NFL-only, so nothing below the client's sport registry knows about the NFL:

- **Data:** each sport has its own folder, `data/<sport>/players.json` and `puzzles.json`, carrying a `sport` field. Teams, labels and colours live in the data.
- **Core:** `handoff-core.js` holds no hard-coded teams. Share text takes `title` and `emoji`.
- **Web:** `web/sports.js` holds the sport-specific words, such as "downs", "incompletion" and "Turnover on downs". There is no sport picker until a second sport exists.
- **Pipeline:** `tools/build_data.py` is the NFL builder. A new sport needs its own builder that writes the same format. Pipeline steps 4 and 5 (graph, BFS, puzzle picking) are generic and can be pulled into a shared module when the second sport lands.

**The name is the open question.** "Handoff" and "downs" are football words. If more sports are coming, a sport-neutral brand (for example *Chainmates*) with per-sport modes may be better. See `docs/research.md` for name and domain availability.

**Data sources to check per sport:**

| Sport | Option | Licence status |
|---|---|---|
| MLB | Lahman / Chadwick Bureau | open licences |
| NBA / WNBA | `hoopR` / `wehoop` (sportsdataverse) | check licences |
| NHL | the `fastRhockey` data releases | check licences |

Apply the same rule as for the NFL: use no scraping of sites whose terms forbid it.

## Rules (v1)

- **3 downs** (Charlie). Hints cost a down and are refused on the last down.
- **Eras:** 2002 onward only (Charlie).
- **Price:** free, with no monetization in v1 (Charlie). The later paid tier is "unlimited plays" (free play / random pairs). It would use StoreKit on iOS, with no prices or "Pro" wording in the app before then.
- **Deep cuts:** about 30% of Fridays use one endpoint from fame ranks 400–1200.
- **Difficulty** comes from par plus the number of optimal routes, not par alone. Par 4 doesn't exist among recognisable players since 2002 (see `spec.md`).

## iOS architecture: run `handoff-core.js` in JavaScriptCore; keep search and UI native

Pigskin Pantheon runs its whole site engine in a hidden WKWebView, because its engine is large and DOM-adjacent. Handoff's core is different. It is about 430 lines of pure ES2018 with no DOM, fetch, timers or Intl dependency (Intl has a fallback), and it is exported as a UMD.

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
