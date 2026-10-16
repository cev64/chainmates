# Browser checks

These are Playwright scripts. They pin the clock to 2026-10-16, which is puzzle No. 5, and play the daily puzzle in phone light, phone dark and desktop sizes. Each script prints `PASS`/`FAIL` lines.

```sh
tools/dev.sh &                            # serves _site on :8765
npm i --no-save playwright                # or set NODE_PATH to a global install
CHROMIUM_PATH=/opt/pw-browsers/chromium node tests/e2e/e2e.js /tmp/shots
CHROMIUM_PATH=/opt/pw-browsers/chromium node tests/e2e/extra.js /tmp/shots
CHROMIUM_PATH=/opt/pw-browsers/chromium node tests/e2e/ux.js /tmp/shots
```

Screenshots are written to the folder you pass as the argument.

To point them at another server, set `BASE_URL`, for example `BASE_URL=http://localhost:8768/`. New games start in hard mode (the core's `DEFAULT_MODE`), so the stored optimal chain scores an Eagle.
