# Research check (Oct 16, 2026)

## Is the NFL teammate-chain lane open?

**Not on the web any more.** Four small, fan-made NFL teammate-chain games have appeared:

| Game | Notes |
|---|---|
| The Chains (chains-game.com) | Daily, launched around Aug 2026 (#74 on Oct 15). Links are a shared team (any season) **or a shared college**. Fixed par 5, rarity tiers per connector, a "Chains+" tier. The most polished. |
| NFL Chainle (wordlecup.today/en/nfl-chainle) | Daily, same-team overlaps from game appearances. Part of a multi-sport "-dle" portal. |
| Touchdown (touchdown.life) | "Connect two NFL players through 6 or fewer mutual teammates." Daily. Rules not verified. |
| Teammate Chain (austinkrance.com/pages/football) | Hobby project, 1970 onward, three strikes. |

None of them shows usage numbers, ratings or reviews. **No NFL teammate-chain app was found on the App Store.** The native iOS lane is still open.

**How Handoff differs:**
- Strict same-season teammates, with the reason shown on every link.
- Par is computed per puzzle, and the difficulty calendar sets it by weekday.
- Golf-style scoring with downs.
- A polished native iOS app.
- A spoiler-free share card.

### Other competitors

- **Dribble Game** (NBA teammate chain): 1,013 ratings, 4.78 average. Last updated Dec 2024, so it is dormant. It has no NFL mode and no sister football app. This suggests the genre is a niche rather than a mass hit.
- **Gridiron Trivia** (iOS): 794 ratings, 4.8. It has 9 or more modes and ships a new one every 1–2 weeks. It has no teammate chain yet, and it is the likeliest to add one.
- **Two-Minute Drill:** a play-calling game. It has no chain mode and no share card.
- **Immaculate Grid** (Sports Reference): has football grids. It has no chain mode.

## Name: "Handoff"

- **App Store:** no game or sports app is called Handoff. There are several business apps named Handoff, including a construction estimator with 1.9K ratings.
- **Search risk:** "Handoff" is Apple's Continuity feature, so App Store and web searches for the word are crowded.
- **Domains** (RDAP, Oct 16):

| Domain | Status |
|---|---|
| handoff.app | registered |
| handoffgame.com | registered |
| playhandoff.com | registered (Sep 2026) |
| gethandoff.com | registered |
| handoff.game | likely available |
| handoff.football | likely available |
| playhandoff.app | likely available |
| handofffootball.com | likely available |

- **Alternatives with a likely-free domain:**
  - Huddle Chain (huddlechain.com / .app)
  - Chainmates (.app)
  - Six Yards (sixyards.app)
  - Pigskin Chain (pigskinchain.com)
- Confirm any domain with a registrar before buying it.

## nflverse data (verified Oct 16)

- `rosters/roster_{season}.parquet` (2002–2026): one row per player-season.
- `weekly_rosters/roster_weekly_{season}.parquet` (2002–2026): per-week `status`.
  - From around 2013 onward, `ACT` means active for that game day, `INA` inactive, and `DEV` practice squad.
  - In early seasons, `ACT` means the 53-man roster.
  - Teams use GSIS codes in early years (ARZ, BLT, CLV, HST, SL).
- `stats_player/stats_player_week_{season}.parquet`: per-game stat lines.
  - It includes defense, kicking and returns.
  - `player_id` is the gsis_id.
  - Team codes are normalised to current franchises (LV for the 2003 Raiders).
- `stats_player/stats_player_reg_{season}.parquet`: season totals with `games`.
- `snap_counts/snap_counts_{season}.parquet` (2012 onward): keyed by `pfr_player_id`.
- `players/players.parquet`: master table. It maps gsis_id to pfr_id, and has draft and position fields.
- The GitHub releases API is not reachable from the sandbox, but the release-download URLs are.
- Pro Bowl and All-Pro flags are **not** in these assets, so the fame score is stats-based.
