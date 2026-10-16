# Handoff

A daily teammate-chain trivia game. You get two players, for example *Brett Favre → Josh Jacobs*, and connect them through a chain of teammates in as few links as possible. Par is the shortest possible chain. You have 3 downs: a wrong guess is an incompletion. You share a spoiler-free result card.

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

To deploy, run the **Deploy site** workflow from the Actions tab. It is manual-only. One-time setup: go to Settings ▸ Pages ▸ Source and choose GitHub Actions.
