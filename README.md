# Chainmates

A daily teammate-chain trivia game. You get two players, for example *Brett Favre → Josh Jacobs*, and connect them through a chain of teammates in as few links as possible. Hard mode (the default) hides every team; par is the shortest chain + 2, so the shortest chain is an eagle. Easy mode shows each player's teams and years, with par = shortest + 1. You have 3 downs: a wrong guess is an incompletion. You share a spoiler-free result card.

It starts with the NFL (2002 onward, via [nflverse](https://github.com/nflverse), CC-BY 4.0) and is built to add other sports.

*Unofficial fan game. Not affiliated with or endorsed by the NFL, NFLPA, or any team.*

## Layout

```
web/      static single-page app (vanilla JS), plus the legal pages
core/     handoff-core.js: all game rules (UMD, no deps), with node:test tests and shared test vectors
data/nfl/ generated players.json and puzzles.json (committed)
tools/    build_data.py (nflverse → data), test_data.py, build_site.sh, dev.sh
docs/     spec.md (contract), decisions.md, design-notes.md, research.md
.github/  weekly in-season data refresh, plus a manual Pages deploy
```

## Develop

```sh
npm test                      # core tests, including validation of every stored puzzle
python3 tools/test_data.py    # data sanity checks
tools/dev.sh                  # build _site/ and serve it on http://localhost:8765
```

Rebuild the data (downloads are cached in `.cache/`):

```sh
pip install -r tools/requirements.txt
python3 tools/build_data.py            # refresh players and extend puzzles; past puzzles stay frozen
```

To pin a puzzle to a date, add it to `tools/puzzle_overrides.json`.

## Deploy

The site is hosted on GitHub Pages from `main`.
- Every push to `main` that touches `web/`, `core/` or `data/` deploys it (`.github/workflows/pages.yml`).
- The daily data refresh deploys after it commits new data (`.github/workflows/update-data.yml`, August through February).
- To deploy by hand: Actions ▸ Deploy site ▸ Run workflow.
- One-time setup: Settings ▸ Pages ▸ Source: **GitHub Actions**.

The live URL is https://cev64.github.io/chainmates/. Share cards link to it, via `CONFIG.shareUrl` in `web/app.js`.
