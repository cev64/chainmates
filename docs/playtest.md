# Playtest (milestone 5)

**Goal:** play 5 puzzles on your phone, then answer the tuning questions below. Your answers set the rules before the iOS port.

## How to play it

Pick one:
- **Preview link.** Claude publishes a private preview and gives you the link in chat. It's the same app and the same data, and progress is saved in that browser.
- **Locally.** Run `tools/dev.sh` and open http://localhost:8765. On a phone on the same Wi-Fi, use your computer's IP instead of localhost.
- **GitHub Pages.** Merge to `main`, then run **Deploy site** from the Actions tab. One-time setup: Settings ▸ Pages ▸ Source: GitHub Actions.

## What to play

1. **Today's daily puzzle,** cold. Don't read the how-to first; the brief's bar is "a stranger can finish without instructions".
2. **Archive ▸ a Monday** (par 2, many routes). Should feel easy.
3. **Archive ▸ a Thursday** (par 2, only 3–7 routes). Should feel tricky.
4. **Archive ▸ a Friday** (par 3, fewer routes, sometimes a deep cut). Should be the hardest.
5. **A themed weekend puzzle** ("Packers weekend" or "Sunday Night: …"). These open on the date they're scheduled.

Archive and replay games are practice, so they don't touch your stats.

## Questions to answer

**Rules**
- **Downs.** Did 3 feel right? Did you lose to bad luck (typos, the wrong one of two same-named players) or to not knowing?
- **Hint cost.** Is one down the right price? Did you use hints?
- **Rejected guesses are free.** Guessing a player already in your chain, or the start or finish player, costs nothing. Does that feel right?
- **Trades.** The rule is "same team, same season". A mid-season trade makes a player a teammate of everyone on both teams that year. Did that ever feel wrong?

**Difficulty**
- Were the endpoints players you'd heard of? Note any that made you go "who?". Picks come from the top 200 (Monday) to 400 by a stats-based fame score.
- Was par 2 too easy and par 3 too hard, or the other way round?
- Do the themed weekend puzzles land?

**Feel**
- Does anything feel slow, janky or confusing? Think about the animation speed, the search and the results sheet.
- Would you share the result card? Is anything missing from it?

## Known gaps

- There's no share image yet, only text.
- There's no offline or installable mode yet.
- There's no iOS app yet. That's milestone 6, after this playtest.
- Puzzle numbers start at an epoch of 2026-10-12, a placeholder. At launch, rebuild with `--rebuild --epoch <launch date>` so No. 1 is launch day.
- The share link points at `cev64.github.io/handoff/` until there's a domain (chainmates.app looked free on Oct 16).
