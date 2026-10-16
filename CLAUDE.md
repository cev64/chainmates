# Chainmates

A daily teammate-chain trivia game: connect two players through teammates in as few links as possible. It starts with the NFL and is sport-agnostic by design. There is a static web app (`web/`) and, later, a SwiftUI app (`ios/`). There's no backend.

Read these before changing anything:
- `docs/spec.md`: the rules, data formats and core API. It is the contract.
- `docs/decisions.md`
- `docs/design-notes.md`: the quality bar, taken from Pigskin Pantheon (`cev64/leaguehistoryapp`). Chainmates has **its own identity** built around a chain/link motif. Don't copy Pigskin Pantheon's look.

## Commands

- Tests: `npm test` (core, with the real-data checks) and `python3 tools/test_data.py` (data sanity).
- Browser checks: `tools/dev.sh`, then the Playwright scripts in `tests/e2e/`. See `tests/e2e/README.md`; they pin the clock to puzzle No. 5.
- Rebuild data: `pip install -r tools/requirements.txt && python3 tools/build_data.py`.
  - `--offline` uses the `.cache/` downloads.
  - `--rebuild --epoch YYYY-MM-DD` renumbers every puzzle. Only do this before launch.
- Site locally: `tools/dev.sh`, then open http://localhost:8765.
- Build the deployable site: `tools/build_site.sh`, which writes `_site/`.

## Conventions

- **No vibe-coded tells.** Avoid:
  - purple/indigo palettes
  - coloured left-border accent bars on rows or cards
  - gradient text, glow shadows, decorative glass/blur, gradient blobs
  - emoji in UI chrome
  - pills and tiny tracked-uppercase labels everywhere
  - nested cards

  Aim for an editorial puzzle-page feel: strong type, hairline rules, one sparing accent.
- **Motion is a feature.** Every state change animates: links spring in, connectors draw, undo retracts, sheets drag. Animate with transform/opacity only, keep it at 60fps, and give everything a `prefers-reduced-motion` fallback.

- **All game rules live in `core/handoff-core.js`.** Clients never re-implement validation, scoring, share text, streaks or date mapping. Change the core, then update `core/test/vectors.json` and the tests.
- **Puzzles dated today or earlier (America/New_York) are frozen.** `build_data.py` never changes them; keep it that way.
- **No sport-specific words in the core or the data pipeline's generic steps.** Per-sport words go in `web/sports.js`.
- **Branding:**
  - No team logos and no player photos. Show teams as ClubChips (abbreviation on team colour).
  - No "NFL" in the app name, subtitle, keywords or icon.
  - Footer and About carry the line "Unofficial fan game. Not affiliated with or endorsed by the NFL, NFLPA, or any team."
  - Credit nflverse (CC-BY 4.0).
- **Data sources:** don't scrape Pro Football Reference, and don't use ESPN's hidden APIs, Sleeper or NFL.com data.
- **iOS** (once it exists):
  - Show Charlie simulator screenshots for every iOS change.
  - iPad is landscape and iPhone is portrait.
  - Match Pigskin Pantheon's App Store rules: playable signed out, no prices or "Pro" text, StoreKit for unlocks, and keep `PrivacyInfo.xcprivacy` up to date.
- **Git:** `main` is the live site. Every push to `main` deploys to GitHub Pages, and so does the daily data bot. Work on a branch, and merge or push to `main` only when Charlie asks. Never force push.
