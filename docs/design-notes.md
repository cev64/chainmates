# Handoff: design notes (distilled from the Pigskin Pantheon reference)

Reference repo: Pigskin Pantheon, a static vanilla-JS site (GitHub Pages) plus a SwiftUI iOS 26 app.
Everything below was read from that repo; CSS/JS/Swift is copied verbatim unless a line says
**PROPOSAL** (my recommendation for Handoff, not something the reference does).

Handoff is a sibling app, so it should be recognisably the same family: navy chrome, white cards on a
hairline, one blue accent, gold as the brand highlight, red as a thin rule, Barlow Condensed
capitals for titles, Inter for everything else.

---------------------------------------------------------------------------------------------------

## 0. Read this first: what the reference really does

1. **The web app has no dark mode.** No toggle, no `data-theme`, no `localStorage` theme key. All of
   `index.html`, `season.html`, `design.css`, `ui.css`, `landing.css`, `account.css` and `chat.css` are
   light-only with hard-coded `#fff` surfaces. The only web dark mode is the **three legal pages**
   (`privacy.html`, `terms.html`, `support.html`), which switch `--lg-*` variables inside
   `@media (prefers-color-scheme: dark)` (snippet in section 2.4). `.topbar`, hero, and footer are
   navy in both worlds.
2. **The iOS app has full light/dark twins** (`Theme.swift`, `Color(light:dark:)`), following the
   system appearance. There is no in-app appearance picker. Hero cards and the recap share images are
   forced dark via `.environment(\.colorScheme, .dark)`.
3. Therefore Handoff's web dark values come from `Theme.swift` (section 2.3), switched by
   `prefers-color-scheme` (matching the legal pages). A `data-theme` override is a **PROPOSAL**
   (section 2.5).
4. **Web search has no debounce.** It runs on every `input` event and drops stale answers with a
   sequence counter (section 6). The iOS app waits 120 ms.
5. **There are no NFL logos anywhere.** NFL clubs are shown as a 3-letter abbreviation on the club's
   primary colour (the "club chip"), with text ink computed from luminance. Only primary colours exist
   in the reference; there is no secondary colour table.
6. iOS deployment target: **`IPHONEOS_DEPLOYMENT_TARGET = 26.1`** (both Debug and Release in
   `ios/PigskinPantheon.xcodeproj/project.pbxproj`). Xcode 26+, `SWIFT_VERSION = 5.0`,
   `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad), bundle id `com.pigskinpantheon.app`,
   `MARKETING_VERSION = 1.0`. Liquid Glass APIs (`.glass`, `.glassProminent`, `.tabBarMinimizeBehavior`)
   are used, which is why 26 is the floor.

### Source map (reference file to what it gives you)

| Need | File |
| --- | --- |
| Page-level tokens (`--ink`, `--navy`, `--shadow`...) | inline `<style>` of `index.html` / `season.html` |
| Final neutrals + card + type overrides (wins, loaded last) | `design.css` top |
| Motion, frosted header, sheets, search pill, keyframes | `ui.css`, `ui.js` |
| Landing hero, buttons, FAQ, footer | `landing.css`, `index.html` |
| Buttons, fields, modals, toast, menus | `account.css` |
| Club colours + search | `sleeper.js` (`CLUB`, `CLUB_COLOR`, `clubStyle`), `player-card.js` (`norm`, `search`) |
| iOS tokens/components | `Design/Theme.swift`, `Design/Components.swift` |
| Legal pages | `privacy.html`, `terms.html`, `support.html` |
| Data refresh | `.github/workflows/update-players.yml`, `tools/update-players.py` |

---------------------------------------------------------------------------------------------------

## 1. Fonts and base typography

### 1.1 Font `<link>` tags (verbatim, identical on every page)

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;700&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />
```

Head boilerplate the reference repeats on every page (copy for Handoff, change names):

```html
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
<meta name="theme-color" content="#071827" />
<meta name="mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<link rel="manifest" href="manifest.webmanifest" />
<link rel="icon" href="icons/favicon-32.png" sizes="32x32" type="image/png" />
<link rel="icon" href="icons/icon-192.png" sizes="192x192" type="image/png" />
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png" />
<style>@view-transition { navigation: auto; }  /* page-to-page crossfade */</style>
```

Manifest: `display: standalone`, `theme_color` and `background_color` both `#071827`, icons 192/512
(any) and 192/512 (maskable, crest inset to 76%).

CSS load order on a page: page inline `<style>` then `ui.css`, then `design.css` (wins), then
`account.css`, then `landing.css` (landing and legal pages only).

### 1.2 Font stacks and base rules (verbatim)

```css
/* design.css */
:root {
  --font-body: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  --font-display: "Barlow Condensed", "Arial Narrow", "Roboto Condensed", sans-serif;
}
body {
  font-family: var(--font-body);
  font-size: 14px;
  line-height: 1.45;
  color: var(--ink);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  font-variant-numeric: tabular-nums;
}
button, select, input, textarea { font-family: inherit; }

/* the titles that name a thing */
.hero h1, .page-title h2, .card-head h3, .bracket-head h3, .brand-title {
  font-family: var(--font-display);
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .03em;
  line-height: 1;
}
.hero h1 { letter-spacing: .01em; line-height: .88; }
.page-title h2 { font-size: 32px; letter-spacing: .02em; }
.card-head h3, .bracket-head h3 { font-size: 22px; }
.brand-title { font-size: 23px; letter-spacing: .04em; }
.brand-kicker { font-weight: 700; letter-spacing: .16em; }
.brand-accent { color: var(--gold, #f6b73c); }   /* second word of the brand in gold */
@media (max-width: 700px) {
  .page-title h2 { font-size: 27px; }
  .card-head h3, .bracket-head h3 { font-size: 20px; }
  .brand-title { font-size: 19px; letter-spacing: .03em; }
}
@media (max-width: 400px) { .brand-title { font-size: 15.5px; letter-spacing: .01em; } }
```

```css
/* page <style> (index.html / season.html) */
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  color: var(--ink);
  background: var(--page);
  font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  min-height: 100vh;
}
button, select { font: inherit; }
button { cursor: pointer; }

/* ui.css */
html { scrollbar-gutter: stable; }
body { overflow-x: clip; }                 /* clip, not hidden: sticky headers keep working */
body { -webkit-font-smoothing: antialiased; font-variant-numeric: tabular-nums; }
html, button, a, summary, select, [role="tab"] { -webkit-tap-highlight-color: transparent; }
button, summary, [role="tab"] { touch-action: manipulation; }
:focus:not(:focus-visible) { outline: none; }   /* taps leave no ring; keyboard still does */
```

Rules of thumb visible in the CSS: body copy 14px (landing 15 to 17.5px), small labels 10 to 11px
uppercase with `.04em` to `.16em` tracking, numbers always `tabular-nums`, card titles in Barlow
Condensed uppercase 20 to 22px, inputs 16px on phones (`font-size:16px` stops iOS zoom-on-focus).
Layout width: `min(1220px, calc(100% - 32px))` for app pages, `min(1180px, calc(100% - 32px))` on the
landing, `min(760px, calc(100% - 32px))` for legal text. Phone gutter is 16px (`Theme.gutter` on iOS).

Landing-page display sizes:

```css
.lp-hero h1 { font-family: "Barlow Condensed", sans-serif; font-weight: 700; text-transform: uppercase;
  font-size: clamp(44px, 11vw, 84px); line-height: .92; letter-spacing: .005em; }
.lp h2 { font-family: "Barlow Condensed", sans-serif; font-weight: 700; text-transform: uppercase;
  font-size: clamp(34px, 7vw, 54px); line-height: .98; letter-spacing: .005em; }
.lp h3 { font-family: "Barlow Condensed", sans-serif; font-weight: 700; text-transform: uppercase;
  font-size: clamp(28px, 5.4vw, 38px); line-height: 1; letter-spacing: .005em; }
.lp-kicker { display: inline-block; color: #1769e0; font-size: 12.5px; font-weight: 800;
  letter-spacing: .16em; text-transform: uppercase; }
```

---------------------------------------------------------------------------------------------------

## 2. Colour tokens and dark mode

### 2.1 The reference's web tokens, verbatim (light only)

The site layers several `:root` blocks. For a single app, collapse them (section 2.4). In the
reference, `design.css` loads last and so wins where names collide.

```css
/* index.html / season.html inline <style> */
:root {
  --ink: #0b1726;
  --muted: #637083;
  --line: #dce3eb;
  --surface: #ffffff;
  --surface-2: #f5f7fa;
  --page: #eef2f6;
  --navy: #071827;
  --navy-2: #102b43;
  --blue: #1769e0;
  --blue-2: #0f56bd;
  --red: #d71920;
  --gold: #f6b73c;
  --green: #16834a;
  --shadow: 0 12px 30px rgba(7, 24, 39, 0.10);
  --radius: 18px;
}

/* design.css (wins: "Bracketeer's neutrals") */
:root {
  --ink: #0b1f3f;
  --ink-2: #475467;
  --ink-3: #8a94a6;
  --muted: #667085;
  --line: #e4e7ec;
  --line-2: #d5dae1;
  --surface-2: #f7f8fa;
  --surface-3: #eef1f5;
  --accent: #1769e0;
  --accent-ink: #0f56bd;
  --accent-soft: #edf3ff;
  --card-shadow: 0 1px 2px rgba(16, 24, 40, .05);
  --card-radius: 14px;
}

/* ui.css: motion + frosted-sheet tokens */
:root {
  --ease: cubic-bezier(.22, 1, .36, 1);
  --spring: cubic-bezier(.34, 1.4, .64, 1);
}
:root {   /* ui.css, then overridden by design.css (brighter, near-white) */
  --glass-sheet: rgba(246, 247, 249, .9);
  --glass-tile: #fff;
  --glass-edge: var(--line);
  --glass-hair: rgba(16, 24, 40, .06);
  --tile-shadow: 0 1px 2px rgba(16, 24, 40, .05);
  --sheet-shadow: 0 32px 80px -24px rgba(8, 32, 79, .45), 0 10px 28px -12px rgba(8, 32, 79, .22), 0 0 0 .5px rgba(8, 32, 79, .14);
}

/* account.css */
:root {
  --acct-navy: #071827;  --acct-navy-2: #102b43;
  --acct-ink: #0b1f3f;   --acct-ink-2: #475467;  --acct-ink-3: #8a94a6;
  --acct-line: #e4e7ec;  --acct-blue: #1769e0;   --acct-gold: #f6b73c;  --acct-red: #d71920;
  --acct-ease: cubic-bezier(.2, .8, .2, 1);
}

/* landing.css (scoped to body.lp) */
body.lp {
  --lp-navy: #071827;  --lp-navy-2: #0d2238;  --lp-navy-3: #102b43;
  --lp-gold: #f6b73c;  --lp-gold-2: #ffd27a;  --lp-red: #d71920;
  --lp-ink: #0b1726;   --lp-muted: #586679;   --lp-line: #dce3eb;  --lp-page: #eef2f6;
  --lp-radius: 20px;   --lp-ease: cubic-bezier(.2, .7, .2, 1);
}
```

Colours used inline without a token (note them): green `#15803d` (positive / win pill), red
`#dc2626` (negative / loss pill), `#d6433d` (losers-bracket red), link blue on dark `#7fb2ff`,
warning note `#fff8e8` bg / `#8a5b00` text, error box `#fff1f1` bg / `#b4141a` text, gold ink
`#8a5a00` on gold-soft `#fdf1d8`, hairline-soft `#edf0f3`, placeholder `#8391a1` / `#98a4b3`.
Season page body background adds faint yard-line stripes:

```css
body {
  background:
    repeating-linear-gradient(90deg, transparent 0 149px, rgba(11,23,38,.045) 149px 150px),
    repeating-linear-gradient(90deg, transparent 0 29px, rgba(11,23,38,.018) 29px 30px),
    #f0f4f9;
}
```

### 2.2 Brand palette in one line

navy `#071827` (chrome), navy-2 `#102b43` / `#0d2238` / `#0F2A4A` (iOS), blue `#1769e0` (accent),
blue-ink `#0f56bd`, blue-soft `#edf3ff`, **gold `#f6b73c`** (+ light `#ffd27a` / `#f6c35a`), **red
`#d71920`** (the 4px rule under heroes and headers; the "live" dot; losers bracket), green `#16834a`
(web) / `#079455` (iOS).

### 2.3 iOS tokens with dark twins (`Theme.swift`; full file in Appendix A)

These are the only authored dark values in the reference. Use them for Handoff's web dark theme.

| Token | Light | Dark | Notes |
| --- | --- | --- | --- |
| ink | `#0B1F3F` | `#EEF2F8` | primary text |
| ink2 | `#475467` | `#C2CAD6` | secondary text |
| ink3 | `#8A94A6` | `#8C97A9` | tertiary / labels |
| muted | `#667085` | `#98A2B3` | |
| page | `#EEF1F5` | `#060E19` | page background |
| card | `#FFFFFF` | `#101B2B` | card surface |
| surface2 | `#F7F8FA` | `#15223A` | |
| surface3 | `#EEF1F5` | `#1B2A42` | input fill, pressed row |
| line | `#E4E7EC` | `#22324B` | hairline |
| line2 | `#D5DAE1` | `#2C3E5C` | stronger hairline |
| accent | `#1769E0` | `#5B9BFF` | also `AccentColor` asset |
| accentInk | `#0F56BD` | `#8AB8FF` | |
| accentSoft | `#EDF3FF` | `#13284A` | |
| navy | `#071827` | same | fixed |
| navy2 | `#0F2A4A` | same | fixed |
| gold | `#F6B73C` | same | fixed |
| goldInk | `#8A5A00` | `#F6C661` | text on gold-soft |
| goldSoft | `#FDF1D8` | `#3A2B0C` | |
| red | `#D92D20` | `#FF6B5E` | |
| redSoft | `#FEF3F2` | `#3A1414` | |
| green | `#079455` | `#47CD89` | |
| cardRadius | 14 | | `Theme.cardRadius` |
| gutter | 16 | | `Theme.gutter` |

The legal pages' own dark set (the only dark values shipped on the web):

| `--lg-*` | light | dark |
| --- | --- | --- |
| page | `#eef2f6` | `#08121d` |
| card | `#ffffff` | `#0f1e2f` |
| ink | `#0b1726` | `#e6edf5` |
| muted | `#586679` | `#9db0c3` |
| line | `#dce3eb` | `#223750` |
| link | `#1769e0` | `#7fb2ff` |
| soft | `#f5f7fa` | `#132740` |

### 2.4 Dark-mode switching mechanism: verbatim from the reference

The one and only web mechanism, from `privacy.html` / `terms.html` / `support.html` (identical in
all three). It is a media query on the OS setting. No JS, no attribute, no storage.

```css
body.lp:not(#_) {
  --lg-page: #eef2f6;
  --lg-card: #ffffff;
  --lg-ink: #0b1726;
  --lg-muted: #586679;
  --lg-line: #dce3eb;
  --lg-link: #1769e0;
  --lg-soft: #f5f7fa;
  background: var(--lg-page);
  color: var(--lg-ink);
}
@media (prefers-color-scheme: dark) {
  body.lp:not(#_) {
    --lg-page: #08121d;
    --lg-card: #0f1e2f;
    --lg-ink: #e6edf5;
    --lg-muted: #9db0c3;
    --lg-line: #223750;
    --lg-link: #7fb2ff;
    --lg-soft: #132740;
  }
}
```

(`:not(#_)` is the repo's specificity trick: an id selector's weight without needing an id.) The
header and footer on those pages are navy and unchanged by the media query. The only other
`color-scheme` use: `.year-control select { color-scheme: dark; }` to keep a native `<select>` list
navy.

iOS mechanism, verbatim: `Color(light:dark:)` wraps a `UIColor { $0.userInterfaceStyle == .dark ? d : l }`
provider, so every `Theme.*` colour follows the system. Forced-dark islands use
`.environment(\.colorScheme, .dark)` (welcome hero card, team season hero, trophy room, recap
images). No override setting.

### 2.5 PROPOSAL: Handoff's unified web token block (light + dark)

One `:root` set (collapsing the reference's layers), dark values from `Theme.swift`, switched by the
same `prefers-color-scheme` mechanism, plus an optional explicit override for a future toggle.
Everything surface-ish must use tokens (the reference hard-codes `#fff` in many places; do not copy
that).

```css
:root {
  color-scheme: light dark;
  --font-body: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  --font-display: "Barlow Condensed", "Arial Narrow", "Roboto Condensed", sans-serif;

  --ink: #0b1f3f;  --ink-2: #475467;  --ink-3: #8a94a6;  --muted: #667085;
  --page: #eef1f5; --card: #ffffff;   --surface-2: #f7f8fa; --surface-3: #eef1f5;
  --line: #e4e7ec; --line-2: #d5dae1;
  --accent: #1769e0; --accent-ink: #0f56bd; --accent-soft: #edf3ff;
  --navy: #071827; --navy-2: #102b43;
  --gold: #f6b73c; --gold-2: #ffd27a; --gold-ink: #8a5a00; --gold-soft: #fdf1d8;
  --red: #d71920;  --red-soft: #fef3f2; --green: #16834a;
  --good: #15803d; --bad: #dc2626;

  --card-radius: 14px;
  --card-shadow: 0 1px 2px rgba(16, 24, 40, .05);
  --ease: cubic-bezier(.22, 1, .36, 1);
  --spring: cubic-bezier(.34, 1.4, .64, 1);
  --glass-sheet: rgba(246, 247, 249, .9);
  --sheet-shadow: 0 32px 80px -24px rgba(8, 32, 79, .45), 0 10px 28px -12px rgba(8, 32, 79, .22), 0 0 0 .5px rgba(8, 32, 79, .14);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ink: #eef2f8;  --ink-2: #c2cad6;  --ink-3: #8c97a9;  --muted: #98a2b3;
    --page: #060e19; --card: #101b2b;   --surface-2: #15223a; --surface-3: #1b2a42;
    --line: #22324b; --line-2: #2c3e5c;
    --accent: #5b9bff; --accent-ink: #8ab8ff; --accent-soft: #13284a;
    --gold-ink: #f6c661; --gold-soft: #3a2b0c;
    --red: #ff6b5e;  --red-soft: #3a1414; --green: #47cd89;
    --card-shadow: none;
    --glass-sheet: rgba(16, 27, 43, .86);
  }
}
:root[data-theme="dark"] {      /* same values as above, for a manual toggle */
  --ink: #eef2f8;  --ink-2: #c2cad6;  --ink-3: #8c97a9;  --muted: #98a2b3;
  --page: #060e19; --card: #101b2b;   --surface-2: #15223a; --surface-3: #1b2a42;
  --line: #22324b; --line-2: #2c3e5c;
  --accent: #5b9bff; --accent-ink: #8ab8ff; --accent-soft: #13284a;
  --gold-ink: #f6c661; --gold-soft: #3a2b0c;
  --red: #ff6b5e;  --red-soft: #3a1414; --green: #47cd89;
  --card-shadow: none;
  --glass-sheet: rgba(16, 27, 43, .86);
}
body { background: var(--page); color: var(--ink); }
```

Optional toggle (PROPOSAL; the reference has none). Keep the media query as the default and store
only an explicit override, wrapped in try/catch like the reference does for all `localStorage` use:

```js
const KEY = "handoff-theme";
try { const t = localStorage.getItem(KEY); if (t) document.documentElement.dataset.theme = t; } catch (e) {}
```

Navy chrome (header, hero, footer, toast) stays navy in both themes, exactly as on the legal pages.
`<meta name="theme-color" content="#071827">` is fixed.

---------------------------------------------------------------------------------------------------

## 3. Component CSS (verbatim, trimmed to the essentials)

Where the reference hard-codes `#fff`, swap to `var(--card)` in Handoff so dark mode works.

### 3.1 Cards

```css
/* design.css (final) */
.card {
  background: #fff;
  border: 1px solid var(--line);
  border-radius: var(--card-radius);       /* 14px */
  box-shadow: var(--card-shadow);          /* 0 1px 2px rgba(16,24,40,.05) */
}
.card-head {
  background: #fff;
  border-bottom: 1px solid var(--line);
  padding: 14px 16px;
  gap: 10px;
}
.card-head > span { color: var(--ink-3); font-size: 11.5px; font-weight: 500; letter-spacing: 0; text-transform: none; }
.card-head h3 { gap: 10px; color: var(--ink); }           /* + display font, 22px, from section 1.2 */
.division-chip { min-width: 26px; height: 26px; border-radius: 8px; background: var(--ink); box-shadow: none; }
@media (max-width: 700px) {
  .card { border-radius: 12px; box-shadow: var(--card-shadow); }
  .card-head { padding: 11px 12px; }
  .division-chip { min-width: 22px; height: 22px; border-radius: 6px; }
}
/* page-level base (index/season <style>) also sets `.card { overflow: hidden; }` */
/* landing cards */
.lp-card { overflow: hidden; padding: 24px 22px 0; border-radius: var(--lp-radius);   /* 20px */
  background: #fff; border: 1px solid var(--lp-line); }
/* tile inside a card ("superlative") */
.superlative { background: #fff; border: 1px solid var(--line); border-radius: 10px; box-shadow: var(--card-shadow); }
.superlative small { color: var(--ink-3); font-size: 10.5px; font-weight: 700; letter-spacing: .08em; }
.superlative strong { color: var(--ink); font-size: 14px; font-weight: 600; }
/* empty / loading note */
.lh-status { display: grid; justify-items: center; gap: 6px; margin: 0 0 16px; padding: 34px 22px;
  background: #fff; border: 1px dashed var(--line); border-radius: var(--card-radius);
  color: var(--muted); text-align: center; }
.lh-status strong { display: block; color: var(--ink); font-size: 16px; font-weight: 700; }
.lh-status.lh-error { border-style: solid; border-color: rgba(215, 25, 32, .28); }
.lh-spinner { width: 26px; height: 26px; margin-bottom: 6px; border-radius: 50%;
  border: 3px solid var(--surface-3); border-top-color: var(--accent); animation: lhSpin .8s linear infinite; }
@keyframes lhSpin { to { transform: rotate(360deg); } }
```

iOS card: white `RoundedRectangle(cornerRadius: 14, style: .continuous)` + `0 1/1 blur rgba(16,24,40,.05)`
shadow + `strokeBorder(Theme.line)`. iOS grouped sections ("HomeSection") use radius **22** with no stroke.

### 3.2 Buttons

```css
/* Primary on the dark landing: gold gradient (landing.css) */
.lp-btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  min-height: 50px; padding: 0 24px; border-radius: 14px;
  font-size: 16px; font-weight: 800; text-decoration: none; white-space: nowrap;
  transition: transform .2s var(--lp-ease), box-shadow .2s var(--lp-ease), background-color .2s ease, border-color .2s ease;
}
.lp-btn:active { transform: translateY(1px); }
.lp-btn-gold {
  background: linear-gradient(180deg, var(--lp-gold-2), var(--lp-gold));
  color: var(--lp-navy);
  box-shadow: 0 10px 24px rgba(246, 183, 60, .28), inset 0 1px 0 rgba(255, 255, 255, .5);
}
.lp-btn-gold:hover { box-shadow: 0 14px 30px rgba(246, 183, 60, .38), inset 0 1px 0 rgba(255, 255, 255, .5); transform: translateY(-1px); }
.lp-btn-ghost { border: 1.5px solid rgba(255, 255, 255, .28); color: #fff; background: rgba(255, 255, 255, .06); }   /* on navy */
.lp-btn-ghost:hover { border-color: rgba(255, 255, 255, .55); background: rgba(255, 255, 255, .1); }
.lp-btn-sm { min-height: 40px; padding: 0 16px; border-radius: 11px; font-size: 14px; }
.lp-btn:focus-visible { outline: 3px solid var(--lp-gold); outline-offset: 3px; }
```

```css
/* In-app buttons on white (account.css): secondary = default, primary = navy */
.acct-btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  min-height: 44px; padding: 0 18px; border-radius: 12px;
  border: 1px solid var(--acct-line); background: #fff; color: var(--acct-ink);
  font: 800 14px/1 var(--font-body, Inter, system-ui, sans-serif); text-decoration: none; cursor: pointer;
  transition: background-color .15s var(--acct-ease), border-color .15s var(--acct-ease), transform .15s var(--acct-ease), opacity .15s;
}
.acct-btn:hover { border-color: #c5ccd6; background: #f7f8fa; }
.acct-btn:active { transform: scale(.97); }
.acct-btn:focus-visible { outline: 2px solid var(--acct-blue); outline-offset: 2px; }
.acct-btn:disabled { opacity: .5; cursor: default; transform: none; }
.acct-btn-primary { background: var(--acct-navy); border-color: var(--acct-navy); color: #fff; }
.acct-btn-primary:hover { background: var(--acct-navy-2); border-color: var(--acct-navy-2); }
.acct-btn-wide { width: 100%; }
.acct-btn-small { min-height: 34px; padding: 0 12px; border-radius: 9px; font-size: 12.5px; }
.acct-btn-quiet { background: transparent; }                       /* ghost on white */
.acct-btn.is-busy { position: relative; color: transparent !important; }
.acct-btn.is-busy::after { content: ""; position: absolute; width: 16px; height: 16px; border-radius: 50%;
  border: 2px solid rgba(255, 255, 255, .35); border-top-color: #fff; animation: acctSpin .7s linear infinite; }
@keyframes acctSpin { to { transform: rotate(360deg); } }
.acct-link { display: inline; padding: 0; border: 0; background: none; cursor: pointer; color: var(--acct-blue);
  font: 600 13px/1.4 var(--font-body); text-decoration: underline; text-decoration-color: rgba(23,105,224,.35); text-underline-offset: 3px; }

/* The form submit used on the front page (index.html): navy, 46px */
.signin-go { height: 46px; padding: 0 22px; border: 0; border-radius: 12px; background: var(--navy); color: #fff;
  font: inherit; font-size: 14px; font-weight: 800; letter-spacing: .02em; cursor: pointer;
  transition: background-color .2s ease, transform .16s ease; }
.signin-go:hover { background: var(--navy-2); }
.signin-go:disabled { opacity: .6; cursor: progress; }

/* Round glass icon button on a dark header (sheets): */
.drawer-close, .bx-close { display: grid; place-items: center; padding: 0; border-radius: 50%;
  border: 1px solid rgba(255,255,255,.26); background: rgba(255,255,255,.16); color: #fff;
  -webkit-backdrop-filter: blur(10px); backdrop-filter: blur(10px);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.25), 0 4px 12px -4px rgba(0,0,0,.3); }
```

Mapping for Handoff: primary CTA on navy = `.lp-btn-gold`; primary on white = `.acct-btn-primary`
(navy fill); secondary = `.acct-btn`; ghost on navy = `.lp-btn-ghost`; ghost on white =
`.acct-btn-quiet`. Press feedback is always `scale(.96 to .97)` or `translateY(1px)`.

### 3.3 Inputs, search field, autocomplete dropdown rows

```css
/* text field with leading icon (index.html .signin-field) */
.signin-field { position: relative; display: flex; align-items: center; min-width: 0; }
.signin-field svg { position: absolute; left: 14px; color: var(--muted); pointer-events: none; }
.signin-field input {
  width: 100%; min-width: 0; height: 46px; padding: 0 14px 0 42px;
  border: 1px solid var(--line); border-radius: 12px;
  background: var(--surface-2); color: var(--ink);
  font: inherit; font-size: 16px; font-weight: 600;
  transition: border-color .2s ease, box-shadow .2s ease, background-color .2s ease;
}
.signin-field input::placeholder { color: #98a4b3; font-weight: 500; }
.signin-field input:focus { outline: none; background: #fff; border-color: var(--blue); box-shadow: 0 0 0 4px rgba(23, 105, 224, .14); }

/* dialog fields (account.css) */
.acct-field { display: grid; gap: 6px; }
.acct-field > span { color: var(--acct-ink-2); font-size: 12.5px; font-weight: 700; }
.acct-field input { width: 100%; height: 44px; padding: 0 13px; border-radius: 11px;
  border: 1px solid var(--line-2, #d5dae1); background: #fff; color: var(--acct-ink);
  font: 500 15px/1 var(--font-body); transition: border-color .15s, box-shadow .15s; }
.acct-field input:focus { outline: none; border-color: var(--acct-blue); box-shadow: 0 0 0 3px rgba(23, 105, 224, .16); }
.acct-error { margin: 0; padding: 9px 11px; border-radius: 10px; background: #fff1f1; color: #b4141a; font-size: 13px; font-weight: 600; }
```

The player-search pill and its dropdown (ui.css; the closest thing to an autocomplete). Markup
(`alltime.html`):

```html
<nav class="season-nav find-pill" id="findPill" aria-label="Player search">
  <div class="sn-cap">
    <div class="sn-find-bar" role="search">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/></svg>
      <input id="playerSearch" type="search" autocomplete="off" spellcheck="false" autocapitalize="words" enterkeyhint="search"
        placeholder="Search any player" aria-label="Search players" aria-controls="playerResults" />
      <button type="button" class="sn-clear" aria-label="Clear search" hidden><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
    </div>
    <div class="sn-drop"><div><div class="player-results" id="playerResults" role="listbox" aria-label="Players"></div></div></div>
  </div>
</nav>
```

```css
.find-pill .sn-find-bar {
  display: flex; align-items: center; gap: 10px; height: 46px; padding: 0 8px 0 14px;
  border-radius: 14px; background: #fff; color: var(--muted, #637083);
  box-shadow: 0 0 0 1px var(--line, #dce3eb), 0 10px 26px -18px rgba(7, 24, 39, .4);
  transition: box-shadow .25s var(--ease), height .5s var(--spring);
}
.find-pill.searching .sn-find-bar { box-shadow: 0 0 0 1.5px var(--blue, #1769e0), 0 0 0 5px rgba(23, 105, 224, .12); }
.sn-find-bar input { flex: 1 1 auto; min-width: 0; height: 100%; border: 0; outline: 0; padding: 0; margin: 0;
  background: transparent; color: var(--ink, #0b1726); font: inherit; font-size: 14px; font-weight: 600;
  -webkit-appearance: none; appearance: none; }
.sn-find-bar input::placeholder { color: #8391a1; font-weight: 500; }
.sn-find-bar input::-webkit-search-cancel-button { -webkit-appearance: none; display: none; }
@media (max-width: 700px) { .sn-find-bar input { font-size: 16px; } }   /* no zoom-on-focus in iOS */
.sn-clear { flex: none; width: 28px; height: 28px; padding: 0; border: 0; border-radius: 50%; cursor: pointer;
  display: grid; place-items: center; background: rgba(12, 28, 45, .08); color: var(--ink, #0b1726);
  transition: background-color .2s var(--ease), transform .18s var(--ease); animation: uiPopIn .35s var(--spring) both; }
.sn-clear[hidden] { display: none; }
.sn-clear:active { transform: scale(.9); }

/* results drop out of the capsule by animating grid rows 0fr -> 1fr */
.sn-drop { display: grid; grid-template-columns: minmax(0, 1fr); grid-template-rows: 0fr; transition: grid-template-rows .45s var(--ease); }
.sn-drop > div { min-height: 0; overflow: hidden; }
.season-nav.found .sn-drop { grid-template-rows: 1fr; transition: grid-template-rows .55s var(--spring); }
.sn-drop .player-results { max-height: min(58vh, 460px); overflow-y: auto; overscroll-behavior: contain; padding: 8px 0 2px; scrollbar-width: thin; }

/* the capsule while pinned / searching: frosted card */
.season-nav.searching .sn-cap {
  padding: 8px; background-color: rgba(255, 255, 255, .86);
  -webkit-backdrop-filter: blur(18px) saturate(1.7); backdrop-filter: blur(18px) saturate(1.7);
  border-color: rgba(7, 24, 39, .08);
  box-shadow: 0 18px 44px rgba(7, 24, 39, .16), 0 2px 8px rgba(7, 24, 39, .06);
}

/* the result rows */
.player-results { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px; }
.player-result {
  display: grid; grid-template-columns: 40px minmax(0, 1fr) auto; gap: 10px; align-items: center;
  padding: 8px 10px; border: 1px solid rgba(255, 255, 255, .8); border-radius: 14px;
  background: rgba(255, 255, 255, .78); box-shadow: 0 0 0 .5px rgba(7, 24, 39, .08), 0 6px 16px -12px rgba(7, 24, 39, .35);
  font: inherit; text-align: left; color: var(--ink, #0b1726); cursor: pointer;
  animation: uiRowIn .45s var(--ease) both; animation-delay: calc(var(--ui-i, 0) * 30ms);   /* stagger */
  transition: background-color .2s var(--ease), border-color .2s var(--ease), transform .18s var(--ease);
}
@media (hover: hover) { .player-result:hover { background: #fff; border-color: rgba(23, 105, 224, .45); } }
.player-result:active { transform: scale(.98); }
.player-result:focus-visible { outline: 2px solid var(--blue, #1769e0); outline-offset: 1px; }
.pr-photo { width: 40px; height: 40px; border-radius: 50%; overflow: hidden; display: grid; place-items: center; background: #eef1f4; }
.pr-photo img { width: 100%; height: 100%; object-fit: cover; object-position: top; }
.pr-who { min-width: 0; }
.player-result strong { display: block; font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.player-result small { display: block; color: var(--muted, #637083); font-size: 11px; font-weight: 600; }
.pr-nums { text-align: right; font-variant-numeric: tabular-nums; }
.pr-nums b { display: block; font-size: 13px; }
.pr-nums small { font-size: 9.5px !important; letter-spacing: .09em; text-transform: uppercase; font-weight: 900 !important; }
.player-empty { grid-column: 1 / -1; padding: 8px 10px 6px; color: var(--muted, #637083); font-size: 12px; }
@media (max-width: 700px) {
  .player-results { grid-template-columns: 1fr; gap: 5px; }
  .player-result { grid-template-columns: 34px minmax(0, 1fr) auto; gap: 8px; padding: 6px 8px; border-radius: 12px; }
  .pr-photo { width: 34px; height: 34px; }
  .player-result strong { font-size: 12.5px; }
  .player-result small { font-size: 10px; }
}
```

Result row HTML (from `ui.js playerFinder`): `<button class="player-result" role="option" style="--ui-i:N" data-player="ID">`
containing `.pr-photo` (headshot `<img>` or club chip fallback), `.pr-who` (`<strong>name</strong><small>POS · CLUB · years</small>`),
`.pr-nums` (`<b>count</b><small>starts</small>`). Empty text: "No one by that name has played in this league."

### 3.4 Chips, pills, segmented controls

```css
/* Pill with dot on navy (landing hero) */
.lp-pill { display: inline-flex; align-items: center; gap: 8px; padding: 7px 13px; border-radius: 999px;
  border: 1px solid rgba(246, 183, 60, .45); background: rgba(246, 183, 60, .1);
  color: var(--lp-gold-2); font-size: 12px; font-weight: 800; letter-spacing: .12em; text-transform: uppercase; }
.lp-dot { width: 7px; height: 7px; border-radius: 50%; background: #3ddc84; box-shadow: 0 0 0 4px rgba(61, 220, 132, .18); }

/* Status tags (design.css) */
.seed-tag { min-width: 30px; text-align: center; font-size: 10px; font-weight: 700; letter-spacing: .02em;
  padding: 2px 6px; border-radius: 99px; line-height: 1.4; }
.seed-tag.div      { background: var(--accent-soft); color: var(--accent-ink); }
.seed-tag.div.lead { background: var(--ink); color: #fff; }
.seed-tag.wc       { background: #fdf1d8; color: #8a5a00; }
.seed-tag.out      { background: var(--surface-3); color: var(--ink-3); }
.clinch-tag { width: 17px; height: 17px; border-radius: 50%; font-size: 10px; font-weight: 700; background: #e7f5ec; color: #15803d; }
.result-pill { border-radius: 7px; font-weight: 700; }
.result-pill.win  { background: #15803d; }     /* white text */
.result-pill.loss { background: #dc2626; }
/* "LIVE" badge on iOS: 9.5pt heavy white on green capsule, tracking .6 */

/* Segmented control with a gliding white pill (ui.css) */
.sn-seg { display: flex; position: relative; gap: 2px; padding: 3px; border-radius: 12px; background: rgba(12, 28, 45, .07); }
.sn-seg button { flex: 1 1 0; min-width: 0; position: relative; z-index: 1; background: none; border: 0; border-radius: 9px;
  padding: 8px 6px; font: inherit; font-size: 13px; font-weight: 700; line-height: 1.2; letter-spacing: -.005em;
  color: var(--muted, #637083); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; cursor: pointer;
  transition: color .25s var(--ease), transform .18s var(--ease); }
.sn-seg button[aria-selected="true"] { color: var(--ink, #0b1726); }
.sn-seg button:active { transform: scale(.96); }
.sn-seg-ind { position: absolute; top: 3px; left: 3px; height: calc(100% - 6px); border-radius: 9px; background: #fff;
  width: calc((100% - 6px - (var(--n, 1) - 1) * 2px) / var(--n, 1));
  transform: translateX(calc(var(--k, 0) * (100% + 2px)));
  box-shadow: 0 1px 3px rgba(16, 24, 40, .14), 0 1px 1px rgba(16, 24, 40, .05); pointer-events: none; z-index: 0; }
.sn-seg-ind.ready { transition: transform .45s var(--ease), width .45s var(--ease); }

/* Two-up tab switch (index.html .platform-tabs) */
.platform-tabs { display: inline-grid; grid-auto-flow: column; gap: 2px; padding: 3px; border: 1px solid var(--line); border-radius: 11px; background: var(--surface-2); }
.platform-tab { min-width: 74px; height: 30px; padding: 0 12px; border: 0; border-radius: 8px; background: transparent;
  color: var(--muted); font: inherit; font-size: 12.5px; font-weight: 800; letter-spacing: .02em; cursor: pointer; }
.platform-tab[aria-selected="true"] { background: #fff; color: var(--ink); box-shadow: 0 1px 3px rgba(11, 23, 38, .14); }

/* TOC chips on the legal pages */
.lg .lg-toc a { display: inline-block; padding: 6px 12px; border: 1px solid var(--lg-line); border-radius: 999px;
  background: var(--lg-soft); font-size: 14px; font-weight: 600; text-decoration: none; color: var(--lg-ink); }
```

### 3.5 The team "club chip" (3-letter abbreviation on team colour)

Web: an inline style produced by `clubStyle(abbr)` (`sleeper.js`, verbatim in section 5.2) on a
small element. The base class styles (`alltime.html` / `index.html`, and `player-card.js`):

```css
.starters-chip { display: inline-block; width: 28px; padding: 3px 0; border-radius: 4px;
  background: #e7ebef; color: #4b5866; font-size: 8px; font-weight: 900; text-align: center; }   /* grey = no club (FA) */
.starters-year .starters-chip { width: 24px; padding: 2px 0; font-size: 7px; }
.pc-chip { display: inline-block; padding: 1px 4px; border-radius: 4px; background: #e7ebef; color: #4b5866; font-size: 8px; font-weight: 900; }
/* round version: club badge on a player photo / defence "photo" */
.pc-photo > .pc-club-big { width: 100%; height: 100%; border-radius: 50%; display: grid; place-items: center;
  background: #e7ebef; color: #4b5866; font-size: 22px; font-weight: 900; letter-spacing: .04em; }
.pc-photo .pc-club .pc-chip { width: 100%; height: 100%; padding: 0; border-radius: 50%; display: grid; place-items: center;
  font-size: 9px; line-height: 1; letter-spacing: -.01em; }
```

Usage: `<span class="starters-chip" style="background:#97233F;color:#ffffff" title="ARI">ARI</span>`.
iOS: `ClubChip` = 9.5pt heavy text, `minWidth 28 / minHeight 15`, horizontal padding 4, corner radius 4
continuous, fill = club colour (fallback `ink3`), ink = `readableInk` (Appendix B).

A fantasy-team badge (rounded square with initial on a team colour, not an NFL chip):

```css
.team-badge { width: 34px; height: 34px; display: inline-grid; place-items: center; border-radius: 10px; font-size: 17px;
  color: #fff; background: var(--team-color, var(--navy-2)); border: 2px solid rgba(255,255,255,.5);
  box-shadow: 0 0 0 1px rgba(7,24,39,.12), inset 0 -8px 14px rgba(0,0,0,.13); flex: 0 0 auto; }
```

### 3.6 Page header / nav

Sticky navy bar. Base (`index.html`), the frosted override under 1200px (`ui.css`), and landing nav:

```css
.topbar { position: sticky; top: 0; z-index: 40; background: rgba(7, 24, 39, .96); backdrop-filter: blur(16px);
  border-bottom: 1px solid rgba(255,255,255,.08); color: #fff; }
.topbar-inner { width: min(1220px, calc(100% - 32px)); margin: 0 auto; min-height: 72px;
  display: flex; align-items: center; justify-content: space-between; gap: 18px; }
.brand { display: flex; align-items: center; gap: 12px; min-width: 0; color: inherit; text-decoration: none; }
.brand-mark { width: 46px; height: 46px; display: grid; place-items: center; flex: 0 0 auto; }
.brand-kicker { display: block; font-size: 10px; letter-spacing: .22em; text-transform: uppercase; color: #9eb0c1; font-weight: 800; margin-bottom: 2px; }
.brand-title { display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-size: 19px; font-weight: 800; letter-spacing: -.02em; }

@media (max-width: 1199px) {
  .topbar { background: rgba(7, 24, 39, .84); -webkit-backdrop-filter: blur(18px) saturate(1.6); backdrop-filter: blur(18px) saturate(1.6);
    transition: box-shadow .3s var(--ease), border-color .3s var(--ease); }
  .topbar.scrolled { box-shadow: 0 10px 28px rgba(7, 24, 39, .22); border-bottom-color: transparent; }
  .topbar { padding-top: env(safe-area-inset-top); }
}
```

```js
// ui.js: header gains a shadow once the page scrolls under it
let scrollRaf = 0;
window.addEventListener("scroll", () => {
  if (scrollRaf) return;
  scrollRaf = requestAnimationFrame(() => {
    scrollRaf = 0;
    const bar = document.querySelector(".topbar");
    if (bar) bar.classList.toggle("scrolled", window.scrollY > 4);
  });
}, { passive: true });
```

```css
/* landing / legal nav */
.lp-nav { position: sticky; top: 0; z-index: 120; background: rgba(7, 24, 39, .86);
  -webkit-backdrop-filter: blur(16px) saturate(1.5); backdrop-filter: blur(16px) saturate(1.5);
  border-bottom: 1px solid rgba(255, 255, 255, .08); color: #fff; }
.lp-nav-inner { display: flex; align-items: center; gap: 12px; min-height: 64px; }
.lp-logo { display: inline-flex; align-items: center; gap: 10px; color: #fff; text-decoration: none;
  font-family: "Barlow Condensed", sans-serif; font-weight: 700; font-size: 21px; letter-spacing: .03em; text-transform: uppercase; }
.lp-logo img { display: block; width: 36px; height: 36px; object-fit: contain; }
.lp-links { display: none; gap: 4px; margin-left: 18px; }            /* shown >= 900px */
.lp-links a { padding: 8px 12px; border-radius: 9px; color: rgba(255, 255, 255, .78); font-size: 14px; font-weight: 600; text-decoration: none; }
.lp-links a:hover { color: #fff; background: rgba(255, 255, 255, .08); }
.lp-nav-end { margin-left: auto; display: flex; align-items: center; gap: 8px; }
@media (min-width: 900px) { .lp-links { display: flex; } }
.lp-skip { position: absolute; left: 16px; top: -60px; z-index: 300; padding: 10px 14px; border-radius: 10px; background: var(--lp-gold); color: var(--lp-navy); font-weight: 800; text-decoration: none; }
.lp-skip:focus { top: 12px; }
```

Brand markup: `<a class="lp-logo"><img src="icons/crest.png" width="40" height="40"><span>Pigskin <span class="brand-accent">Pantheon</span></span></a>`.
Handoff equivalent: `Hand<span class="brand-accent">off</span>` or "The <accent>Handoff</accent>" (second word in gold).

Phone bottom capsule (`.season-nav.sn-bottom`) pins the primary view-switcher at the bottom, in
thumb reach (breakpoint `max-width: 760px`).

### 3.7 Hero / landing background (navy gradient, glows, yard lines)

```css
/* landing.css .lp-hero (the canonical recipe) */
.lp-hero {
  position: relative; overflow: hidden; color: #fff;
  background:
    radial-gradient(900px 520px at 85% 15%, rgba(23, 105, 224, .26), transparent 60%),   /* blue glow, top right */
    radial-gradient(700px 480px at 10% 100%, rgba(246, 183, 60, .12), transparent 60%),  /* gold glow, bottom left */
    repeating-linear-gradient(90deg, transparent 0 149px, rgba(255, 255, 255, .045) 149px 150px),   /* yard lines every 150px */
    linear-gradient(180deg, var(--lp-navy), var(--lp-navy-2));                                      /* #071827 -> #0d2238 */
  border-bottom: 4px solid var(--lp-red);
}
.lp-hero-grid { display: grid; gap: 40px; padding: 44px 0 56px; }
@media (min-width: 900px) { .lp-hero-grid { grid-template-columns: minmax(0, 1fr) minmax(0, 1.08fr); align-items: center; gap: 48px; padding: 70px 0 84px; } }
.lp-lede { margin: 18px 0 0; max-width: 560px; color: #c3d0dc; font-size: 17.5px; line-height: 1.55; }
.lp-ctas { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 26px; }
.lp-hero .lp-ctas .lp-btn { flex: 1 1 220px; }
.lp-proof { display: grid; gap: 8px; margin: 22px 0 0; padding: 0; list-style: none; color: #aebdcc; font-size: 14px; font-weight: 600; }
```

Season-page hero (field with hash ticks + a faint ball emoji):

```css
.hero {
  position: relative; overflow: hidden;
  background:
    repeating-linear-gradient(90deg, transparent 0 28px, rgba(255,255,255,.075) 28px 30px) 0 34% / 100% 7px no-repeat,   /* upper hash row */
    repeating-linear-gradient(90deg, transparent 0 28px, rgba(255,255,255,.075) 28px 30px) 0 68% / 100% 7px no-repeat,   /* lower hash row */
    repeating-linear-gradient(90deg, transparent 0 149px, rgba(255,255,255,.055) 149px 150px),
    repeating-linear-gradient(90deg, transparent 0 29px, rgba(255,255,255,.022) 29px 30px),
    rgba(7, 24, 39, .98);
  color: #fff; border-bottom: 4px solid var(--red);
}
.hero::before { content: "🏈"; position: absolute; right: -26px; top: 50%; transform: translateY(-50%) rotate(-24deg);
  font-size: 150px; line-height: 1; opacity: .055; pointer-events: none; z-index: 0; }
```

Dark feature band and closing CTA band:

```css
.lp-feature-dark { padding: 30px 18px; border-radius: 26px; color: #fff;
  background: radial-gradient(700px 400px at 70% 0%, rgba(246, 183, 60, .14), transparent 60%), linear-gradient(180deg, #0a1220, #070b12); }
.lp-final { padding: 72px 0; color: #fff; text-align: center;
  background: radial-gradient(600px 300px at 50% 0%, rgba(246, 183, 60, .18), transparent 70%), var(--lp-navy); }
.lp-find { padding: 56px 0 64px; background: linear-gradient(180deg, #e6ecf3, var(--lp-page)); border-top: 1px solid var(--lp-line); }
.demo-strip { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; padding: 10px 14px; border-radius: 14px;
  background: linear-gradient(90deg, #0d2238, #163a5f); color: #dbe5ee; font-size: 13.5px; line-height: 1.4; box-shadow: 0 8px 20px rgba(7, 24, 39, .14); }
.demo-strip-tag { padding: 3px 8px; border-radius: 999px; background: #f6b73c; color: #071827; font-size: 11px; font-weight: 900; letter-spacing: .12em; text-transform: uppercase; }
```

Team-colour hero for sheets (e.g. a team's card header), `--drawer-color` = the team colour:

```css
.drawer-hero {
  background:
    radial-gradient(120% 150% at 0% 0%, rgba(255, 255, 255, .24), rgba(255, 255, 255, 0) 55%),
    linear-gradient(140deg,
      color-mix(in srgb, var(--drawer-color, var(--navy-2)) 86%, #fff) 0%,
      var(--drawer-color, var(--navy-2)) 45%,
      color-mix(in srgb, var(--drawer-color, var(--navy-2)) 70%, #071827) 100%);
  box-shadow: inset 0 -1px 0 rgba(255, 255, 255, .12);
}
.bx-head { background: radial-gradient(120% 180% at 0% 0%, rgba(255, 255, 255, .16), rgba(255, 255, 255, 0) 55%),
  linear-gradient(140deg, #1c3a57 0%, #0e2439 50%, #071827 100%); }
```

### 3.8 Footer

Site footer (`design.css`): small grey text, a row of yard ticks above. The landing/legal variant is
navy and wins on those pages.

```css
body:not(#_) .footer { padding: 26px 16px 34px; text-align: center; color: #718092; font-size: 11px; line-height: 1.6; }
body:not(#_) .footer::before {
  content: ""; display: block; width: min(360px, 52%); height: 7px; margin: 0 auto 15px;
  background: repeating-linear-gradient(90deg, currentColor 0 1px, transparent 1px 15px);   /* yard ticks */
  opacity: .45;
}
body:not(#_) .footer a { color: inherit; text-decoration: underline; text-underline-offset: 2px; }

/* landing.css: navy footer (no ticks) */
body.lp:not(#_) .lp-footer { margin: 0; padding: 28px 0 40px; background: var(--lp-navy); color: #8597aa; font-size: 13px; border-top: 1px solid rgba(255, 255, 255, .08); }
body.lp:not(#_) .lp-footer::before { display: none; }
body.lp:not(#_) .lp-footer a { color: #c3d0dc; }
.lp-footer-inner { display: grid; gap: 12px; justify-items: center; text-align: center; }
.lp-footer p { margin: 0; font-size: 13px; line-height: 1.5; }
.lp-logo-sm { font-size: 17px; } .lp-logo-sm img { width: 28px; height: 28px; }
```

Footer markup and disclaimer pattern are in section 9.

### 3.9 Modals and sheets

```css
/* Centered dialog (account.css) */
.acct-modal { position: fixed; inset: 0; z-index: 300; display: none; place-items: center; padding: 16px; }
.acct-modal.open { display: grid; }
.acct-modal-backdrop { position: absolute; inset: 0; background: rgba(7, 24, 39, .55); -webkit-backdrop-filter: blur(4px); backdrop-filter: blur(4px); }
.acct-modal-card { position: relative; width: min(420px, 100%); max-height: calc(100dvh - 32px); overflow-y: auto;
  padding: 26px 24px 22px; border-radius: 20px; background: #fff; color: var(--acct-ink);
  box-shadow: 0 30px 80px rgba(3, 12, 22, .35); animation: acctPop .26s var(--acct-ease) both; }
.acct-modal-card h2 { margin: 0 0 8px; font: 700 28px/1 var(--font-display); text-transform: uppercase; letter-spacing: .02em; }
.acct-close { position: absolute; top: 12px; right: 12px; width: 34px; height: 34px; border: 0; border-radius: 50%; background: #f2f4f7; color: var(--acct-ink-2); font-size: 20px; line-height: 1; cursor: pointer; }
.acct-confirm-actions { display: flex; justify-content: flex-end; gap: 10px; }
@keyframes acctPop { from { opacity: 0; transform: translateY(-6px) scale(.98); } to { opacity: 1; transform: none; } }
html.lh-modal-open, html.lh-panel-open { overflow: hidden; }

/* Gate (blocking card with red top rule) */
.acct-gate { position: fixed; inset: 0; z-index: 200; display: grid; place-items: center; padding: 16px; background: rgba(7, 24, 39, .6);
  -webkit-backdrop-filter: blur(10px) saturate(1.2); backdrop-filter: blur(10px) saturate(1.2); animation: acctFade .3s var(--acct-ease) both; }
.acct-gate-card { width: min(460px, 100%); padding: 28px 26px 22px; border-radius: 22px; background: #fff; text-align: center;
  border-top: 4px solid var(--acct-red); box-shadow: 0 30px 80px rgba(3, 12, 22, .4); }

/* Slide-in panel from the right */
.acct-panel { position: fixed; top: 0; right: 0; bottom: 0; z-index: 260; width: min(420px, 100vw); display: flex; flex-direction: column;
  background: #f7f8fa; box-shadow: -20px 0 60px rgba(3, 12, 22, .25); transform: translateX(104%); visibility: hidden;
  transition: transform .38s var(--acct-ease), visibility 0s linear .38s; }
.acct-panel-head { padding: calc(22px + env(safe-area-inset-top)) 60px 20px 20px; background: var(--acct-navy); color: #fff; border-bottom: 4px solid var(--acct-red); }
html.lh-panel-open .acct-panel { transform: none; visibility: visible; transition: transform .38s var(--acct-ease); }
```

Frosted bottom sheet / centred card (player card and others; `ui.css` + `player-card.js`):

```css
.pc-backdrop, .drawer-backdrop, .bx-backdrop { background: rgba(8, 32, 79, .26);
  -webkit-backdrop-filter: blur(10px) saturate(1.2); backdrop-filter: blur(10px) saturate(1.2); transition: opacity .35s var(--ease); }
.pc { position: fixed; z-index: 201; left: 50%; top: 50%; width: min(900px, calc(100vw - 32px)); max-height: 92vh;
  transform: translate(-50%, -48%) scale(.98); opacity: 0; pointer-events: none; transition: opacity .18s ease, transform .18s ease;
  display: flex; flex-direction: column;
  background: var(--glass-sheet); border-radius: 24px; overflow: hidden;
  -webkit-backdrop-filter: blur(30px) saturate(1.6); backdrop-filter: blur(30px) saturate(1.6);
  box-shadow: var(--sheet-shadow); }
.pc.open { opacity: 1; pointer-events: auto; transform: translate(-50%, -50%); }
.pc::after { content: ""; position: absolute; inset: 0; border-radius: inherit; pointer-events: none; z-index: 7;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .5); }           /* hairline of light on the edge */
@media (min-width: 761px) {   /* desktop: opens with a little spring, closes quickly */
  .pc { transition: opacity .2s var(--ease), transform .25s var(--ease); }
  .pc.open { transition: opacity .3s var(--ease), transform .5s var(--spring); }
}
@media (max-width: 760px) {   /* phone: bottom sheet with a grabber; swipe down to close (player-card.js swipeToClose) */
  .team-drawer, .bx-modal { border-radius: 24px 24px 0 0; }
  .team-drawer::before, .bx-modal::before { content: ""; position: absolute; z-index: 8; top: 6px; left: 50%; width: 36px; height: 5px;
    margin-left: -18px; border-radius: 3px; background: rgba(255, 255, 255, .55); pointer-events: none; }
}
```

Swipe-to-close rules (`player-card.js`): drag starts anywhere once content is scrolled to top;
sheet follows the finger 1:1 while backdrop fades; on release a flick or a drag past 1/3 of the
sheet continues down at finger speed, anything less springs back with a little overshoot; sideways
gestures ignored; `Escape` closes only the top card (`stopImmediatePropagation`); `SHEET_MAX = 760`.

Dropdown menu on navy (season picker / profile menu):

```css
.ui-menu { position: absolute; top: calc(100% + 6px); right: 0; z-index: 60; min-width: max(100%, 136px);
  max-height: min(60vh, 360px); overflow-y: auto; overscroll-behavior: contain; padding: 5px; border-radius: 12px;
  background: rgba(10, 30, 48, .985); -webkit-backdrop-filter: blur(18px) saturate(1.6); backdrop-filter: blur(18px) saturate(1.6);
  border: 1px solid rgba(255, 255, 255, .14); box-shadow: 0 18px 44px rgba(3, 12, 22, .45), 0 2px 8px rgba(3, 12, 22, .25);
  color: #fff; animation: uiPopover .28s var(--ease) both; transform-origin: top right; }
.ui-menu-item { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 36px; padding: 0 10px 0 12px;
  border-radius: 8px; font-size: 13px; font-weight: 800; letter-spacing: .01em; white-space: nowrap; color: #dbe5ee; cursor: pointer; outline: none; }
.ui-menu-item:focus, .ui-menu-item:focus-visible { background: rgba(255, 255, 255, .09); color: #fff; }
.ui-menu-item.on { color: #f6c35a; background: rgba(246, 183, 60, .12); }      /* current item in gold */
@media (pointer: coarse) { .ui-menu-item { min-height: 42px; font-size: 14px; } }
```

### 3.10 Toasts and install pill

```css
.acct-toast { position: fixed; left: 50%; bottom: calc(24px + env(safe-area-inset-bottom)); z-index: 400;
  max-width: calc(100vw - 32px); padding: 11px 16px; border-radius: 12px;
  background: var(--acct-navy); color: #fff; font: 600 13.5px/1.35 var(--font-body);
  box-shadow: 0 12px 30px rgba(3, 12, 22, .35);
  transform: translate(-50%, 20px); opacity: 0; pointer-events: none;
  transition: transform .3s var(--acct-ease), opacity .3s var(--acct-ease); }
.acct-toast.show { transform: translate(-50%, 0); opacity: 1; }
@media (prefers-reduced-motion: reduce) { .acct-panel, .acct-toast { transition: none; } }

/* pwa.js install pill (bottom right) */
.lh-install { position: fixed; z-index: 175; right: max(16px, env(safe-area-inset-right));
  bottom: calc(var(--lhc-lift, 0px) + 16px + env(safe-area-inset-bottom)); display: flex; align-items: center; gap: 4px;
  padding: 4px 4px 4px 14px; border-radius: 999px; background: linear-gradient(145deg, #16324a, #071827);
  box-shadow: 0 14px 32px rgba(6, 21, 35, .38); color: #fff; animation: lh-install-in .28s ease-out both; }
@keyframes lh-install-in { from { opacity: 0; transform: translateY(12px); } }
```

Toast is added/removed by toggling `.show` (no auto-stacking). z-index ladder: sticky capsule
35 to 45, header 40, popover 60, install pill 175, gate 200, sheets 201, panel 255/260, menu 250,
modal 300, confirm 320, toast 400.

### 3.11 FAQ accordion (landing + support)

```css
.lp-faq details { border: 1px solid var(--lp-line); border-radius: 16px; background: var(--lp-page); }
.lp-faq summary { position: relative; padding: 18px 52px 18px 20px; cursor: pointer; list-style: none; font-size: 16.5px; font-weight: 700; border-radius: 16px; }
.lp-faq summary::-webkit-details-marker { display: none; }
.lp-faq summary::after { content: ""; position: absolute; right: 20px; top: 50%; width: 10px; height: 10px; margin-top: -7px;
  border-right: 2.5px solid #1769e0; border-bottom: 2.5px solid #1769e0; transform: rotate(45deg); transition: transform .25s var(--lp-ease); }
.lp-faq details[open] summary::after { transform: rotate(-135deg); margin-top: -2px; }
```

---------------------------------------------------------------------------------------------------

## 4. Tables and rows (for the chain / results lists)

```css
.table-wrap th { background: transparent; color: var(--ink-3); font-size: 11px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; padding: 10px 10px 8px; border-bottom: 1px solid var(--line); }
.table-wrap td { padding: 9px 10px; border-bottom: 1px solid var(--line); color: var(--ink-2); font-size: 13px; }
.table-wrap tr:last-child td { border-bottom: 0; }
.table-wrap tbody tr:hover { background: var(--surface-2); }
.table-wrap .positive { color: #15803d; }   .table-wrap .negative { color: #dc2626; }
/* winning / selected side: soft blue wash with a 3px leading rule */
.game-side.winner { background: var(--accent-soft); box-shadow: inset 3px 0 0 var(--accent); }
.matchup-row.winner .score { color: var(--accent-ink); font-weight: 700; }
/* the loser fades to --ink-3, weight 500; champion row: rgba(246,183,60,.09) + inset 3px gold */
```

---------------------------------------------------------------------------------------------------

## 5. NFL team colours

### 5.1 Table (primary colour; ink derived by luminance)

Source: `sleeper.js CLUB_COLOR` / `season.html NFL_TEAMS` / `NFLClub.colors` (all identical except
where noted). The reference stores **primary colour only**; the chip's text colour is derived
(`readableInk`: luminance `0.299R + 0.587G + 0.114B` over 255; `> 0.62` gives dark ink `#0b1726`,
else white). I computed the ink column below; only Pittsburgh gets dark ink.

| Abbr | Primary | Ink | Abbr | Primary | Ink |
| --- | --- | --- | --- | --- | --- |
| ARI | `#97233F` | `#ffffff` | MIN | `#4F2683` | `#ffffff` |
| ATL | `#A71930` | `#ffffff` | NE | `#002244` | `#ffffff` |
| BAL | `#241773` | `#ffffff` | NO | `#A08A5B` | `#ffffff` (lum .546) |
| BUF | `#00338D` | `#ffffff` | NYG | `#0B2265` | `#ffffff` |
| CAR | `#0085CA` | `#ffffff` | NYJ | `#125740` | `#ffffff` |
| CHI | `#0B162A` | `#ffffff` | PHI | `#004C54` | `#ffffff` |
| CIN | `#FB4F14` | `#ffffff` | **PIT** | `#FFB612` | **`#0b1726`** (lum .726) |
| CLE | `#311D00` | `#ffffff` | SEA | `#002244` | `#ffffff` |
| DAL | `#041E42` | `#ffffff` | SF | `#AA0000` | `#ffffff` |
| DEN | `#FB4F14` | `#ffffff` | TB | `#D50A0A` | `#ffffff` |
| DET | `#0076B6` | `#ffffff` | TEN | `#0C2340` | `#ffffff` |
| GB | `#203731` | `#ffffff` | WSH | `#5A1414` | `#ffffff` |
| HOU | `#03202F` | `#ffffff` | FA (no club) | `#8A94A1` | `#ffffff` |
| IND | `#002C5F` | `#ffffff` | JAX | `#101820` | `#ffffff` |
| KC | `#E31837` | `#ffffff` | LAC | `#0080C6` | `#ffffff` |
| LAR | `#003594` | `#ffffff` | LV | `#111111` | `#ffffff` |
| MIA | `#008E97` | `#ffffff` | | | |

Notes: Denver and Cincinnati share `#FB4F14`; New England and Seattle share `#002244`. In
`player-card.js` (white header text on a big hero) PIT is `#101820` instead of gold (too light for
white), everything else the same. On web the grey default when a club is unknown/FA is
`background:#e7ebef;color:#4b5866` (the `.starters-chip` / `.pc-chip` base).

### 5.2 Historical codes and the exact JS (verbatim)

Sleeper (and old data) uses legacy codes. The reference normalises **before** lookup; it keeps no
separate colour rows for them, so a historical code just takes its franchise's colour. (There is no
OAK-era silver/black, SD powder blue, or STL navy/gold in the reference; if Handoff wants era
colours that is new work.)

```js
// sleeper.js, verbatim
// Sleeper's club codes, spelled the way the site's logos are named.
const CLUB = { WAS: "WSH", JAC: "JAX", OAK: "LV", SD: "LAC", STL: "LAR", LA: "LAR" };
const club = (code) => (code ? CLUB[code] || code : "FA");

/* An NFL club is shown as its abbreviation on the club's colour (no logos:
   those belong to the NFL). The ink is worked out from the colour, so
   Pittsburgh's yellow gets black text and Philadelphia's green white. */
const CLUB_COLOR = {
  ARI: "#97233F", ATL: "#A71930", BAL: "#241773", BUF: "#00338D", CAR: "#0085CA", CHI: "#0B162A",
  CIN: "#FB4F14", CLE: "#311D00", DAL: "#041E42", DEN: "#FB4F14", DET: "#0076B6", GB: "#203731",
  HOU: "#03202F", IND: "#002C5F", JAX: "#101820", KC: "#E31837", LAC: "#0080C6", LAR: "#003594",
  LV: "#111111", MIA: "#008E97", MIN: "#4F2683", NE: "#002244", NO: "#A08A5B", NYG: "#0B2265",
  NYJ: "#125740", PHI: "#004C54", PIT: "#FFB612", SEA: "#002244", SF: "#AA0000", TB: "#D50A0A",
  TEN: "#0C2340", WSH: "#5A1414",
};
function clubStyle(abbr) {
  const hex = CLUB_COLOR[abbr];
  if (!hex) return "";
  const n = parseInt(hex.slice(1), 16);
  const lum = (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
  return `background:${hex};color:${lum > 0.62 ? "#0b1726" : "#ffffff"}`;
}
```

Handoff-ready object (**PROPOSAL** formatting of the above: abbreviation, primary, ink, plus the
alias map; every alias resolves to the franchise's current colour):

```js
const NFL = {
  ARI: ["#97233F", "#ffffff"], ATL: ["#A71930", "#ffffff"], BAL: ["#241773", "#ffffff"], BUF: ["#00338D", "#ffffff"],
  CAR: ["#0085CA", "#ffffff"], CHI: ["#0B162A", "#ffffff"], CIN: ["#FB4F14", "#ffffff"], CLE: ["#311D00", "#ffffff"],
  DAL: ["#041E42", "#ffffff"], DEN: ["#FB4F14", "#ffffff"], DET: ["#0076B6", "#ffffff"], GB:  ["#203731", "#ffffff"],
  HOU: ["#03202F", "#ffffff"], IND: ["#002C5F", "#ffffff"], JAX: ["#101820", "#ffffff"], KC:  ["#E31837", "#ffffff"],
  LAC: ["#0080C6", "#ffffff"], LAR: ["#003594", "#ffffff"], LV:  ["#111111", "#ffffff"], MIA: ["#008E97", "#ffffff"],
  MIN: ["#4F2683", "#ffffff"], NE:  ["#002244", "#ffffff"], NO:  ["#A08A5B", "#ffffff"], NYG: ["#0B2265", "#ffffff"],
  NYJ: ["#125740", "#ffffff"], PHI: ["#004C54", "#ffffff"], PIT: ["#FFB612", "#0b1726"], SEA: ["#002244", "#ffffff"],
  SF:  ["#AA0000", "#ffffff"], TB:  ["#D50A0A", "#ffffff"], TEN: ["#0C2340", "#ffffff"], WSH: ["#5A1414", "#ffffff"],
  FA:  ["#8A94A1", "#ffffff"],
};
// Historical / alternate codes -> current. Reference has exactly these six:
const ALIAS = { WAS: "WSH", JAC: "JAX", OAK: "LV", SD: "LAC", STL: "LAR", LA: "LAR" };
// (not in the reference, add if your data needs them: LVR -> LV, ARZ -> ARI, BLT -> BAL, CLV -> CLE, HST -> HOU, SL -> LAR)
const club = (code) => (code ? ALIAS[code] || code : "FA");
```

(`demo.js` uses `WAS` for Washington in its own sample data, which `club()` maps to `WSH`.)

---------------------------------------------------------------------------------------------------

## 6. Player search (web)

Source: `player-card.js` (`norm`, `search`), `ui.js` (`playerFinder`, `slashOpens`, `findPill`),
`sleeper.js` (`players()`, `headshot()`).

### 6.1 Normalisation (verbatim)

```js
/* Search: names containing every word typed, in any order, accents and
   punctuation ignored; the most-started first. */
const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[.'’]/g, "");
```

(NFD decompose, strip combining marks, lowercase, delete `.`, `'` and `’`. Hyphens are kept, so
"amon ra" does not match "Amon-Ra"; "stbrown" does not either. Handoff may want to also strip `-`.)

### 6.2 Matching and ranking (verbatim)

```js
function search(query, limit = 8) {
  return load().then((d) => {
    if (!d) return [];
    const words = norm(query).split(/\s+/).filter(Boolean);
    if (!words.length) return [];
    return d.players
      .filter((p) => { const n = norm(p.n); return words.every((w) => n.includes(w)); })   // every word, any order, substring
      .map((p) => {
        const starts = p.r.filter((r) => r[3] !== "BE" && r[3] !== "IR");
        return { id: p.id, name: p.n, pos: p.p, club: p.r[p.r.length - 1][6], headshot: p.h,
          starts: starts.length, pts: starts.reduce((t, r) => t + r[4], 0),
          seasons: [...new Set(p.r.map((r) => r[0]))], prefix: norm(p.n).startsWith(words[0]) };
      })
      .sort((a, b) => (b.prefix - a.prefix) || b.starts - a.starts || a.name.localeCompare(b.name))
      .slice(0, limit);
  });
}
```

Ranking order: (1) names that **start with the first typed word** first; (2) then the most-started
(for Handoff swap in a popularity score, e.g. career length, or fame); (3) then alphabetical.
Limit **8** on web, **25** in the iOS app (`Bridge.player.search(q, 25)`). The player index is
loaded lazily and cached; `search("", 0)` on input focus is used purely to prefetch it.

### 6.3 The input wiring (verbatim essentials from `ui.js`)

```js
function playerFinder(input, list, { limit = 8, onChange } = {}) {
  let seq = 0, shown = false;
  function run() {                      // called on EVERY "input" event: no debounce
    const q = input.value.trim();
    const mine = ++seq;                 // sequence token: stale answers are dropped
    if (!q || !window.PlayerCard) { list.innerHTML = ""; tell(false); return; }
    window.PlayerCard.search(q, limit).then((hits) => {
      if (mine !== seq) return;
      /* render rows (section 3.3) or: <div class="player-empty">No one by that name has played in this league.</div> */
      tell(true);
    });
  }
  input.addEventListener("input", run);
  // a photo that can't load (offline, say) gives way to the player's club chip
  list.addEventListener("error", (e) => { /* swap <img> for club chip */ }, true);
  input.addEventListener("focus", () => window.PlayerCard && window.PlayerCard.search("", 0));   // prefetch
  input.addEventListener("keydown", (e) => {
    const first = list.querySelector("[data-player]");
    if (e.key === "Enter" && first) { e.preventDefault(); first.click(); }       // Enter opens the first hit
    if (e.key === "ArrowDown" && first) { e.preventDefault(); first.focus(); }
  });
  list.addEventListener("keydown", (e) => {       // up/down walk the results; up from the first returns to the field
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
    const items = [...list.querySelectorAll("[data-player]")], i = items.indexOf(document.activeElement);
    if (i < 0) return;
    e.preventDefault();
    const next = items[i + (e.key === "ArrowDown" ? 1 : -1)];
    (next || (e.key === "ArrowUp" ? input : items[i])).focus();
  });
  return { run, clear() { seq++; input.value = ""; list.innerHTML = ""; tell(false); }, get shown() { return shown; } };
}

/* "/" opens search from anywhere, unless a field or an open card already has the keyboard. */
function slashOpens(open) {
  document.addEventListener("keydown", (e) => {
    if (e.key !== "/" || e.metaKey || e.ctrlKey || e.altKey) return;
    const t = e.target;
    if (t && t.closest && t.closest("input, select, textarea, [contenteditable]")) return;
    if (document.querySelector(".team-drawer.open, .bx-modal.open, .pc.open")) return;
    e.preventDefault();
    open();
  });
}
```

Also: Escape clears, blurs and folds the results; a click anywhere outside folds them (text stays);
the clear (x) button appears only when the field has text (`hidden` toggled on `input`).

### 6.4 Data shape and headshots

`data/players.json`, one entry per line, written by the daily workflow (section 10):
`"<sleeperId>": [name, position, clubCode, eligibleSlots?]`, e.g. `"7":["Kurt Warner","QB",null]`;
a defence is `["Bears D/ST","DST","CHI"]`-style (third element is the team code, id is the team code
string). ~457 KB. Fetched once, cached in IndexedDB for a day (`TTL.players = DAY`). Headshots:
`https://sleepercdn.com/content/nfl/players/thumb/${encodeURIComponent(id)}.jpg` (round crop,
`object-fit: cover; object-position: top`); a defence has no photo, so its club chip fills the circle.
Image `error` falls back to the club chip. (APP_STORE.md flags headshots as a possible 5.2.1 review
risk; initials are the safe fallback.)

### 6.5 iOS search behaviours (`PlayerSearchScreen.swift`)

- `.searchable(text:prompt: "Search any player")`, `.autocorrectionDisabled()`, `.textInputAutocapitalization(.words)`.
- `.task(id: trimmed)` with **120 ms** `Task.sleep` as the debounce; cancelled tasks bail.
- Empty query shows "Recently viewed" (long-press to remove) and "Most started" cards, then the hits.
- Keyboard Search key opens the first hit (`.onSubmit(of: .search)`), matching web Enter.
- States: `LoadingCard("Searching...")`, `ContentUnavailableView("No results")` with the same
  "No one by that name has played in this league." copy, `EmptyCard` with a warning symbol on failure.
- Row: 42pt round photo + stroke, name 15 semibold, `ClubChip` + detail 12, optional team marks,
  trailing count 17 bold monospaced digits over "starts" 10 semibold, chevron. Two columns when
  `horizontalSizeClass == .regular`. Pressed state: accent at 8% + 0.99 scale. Rows `Felt(...)` = light haptic.
- Results animate with `.animation(.smooth(duration: 0.2), value: hits)`.

---------------------------------------------------------------------------------------------------

## 7. Motion

### 7.1 Principle (from the `ui.css` header, verbatim)

"The feel: quiet at rest, lively on interaction. Selections glide, new things settle in, changes
show where they came from, and floating chrome (the pinned season capsule, the header on a phone,
popovers and the backdrops behind sheets) is frosted glass. Nothing blinks, jumps or pops without a
reason. One ease-out for movement, one gentle spring for 'settle' moments."

### 7.2 Curves and durations

| Name | Value | Use |
| --- | --- | --- |
| `--ease` | `cubic-bezier(.22, 1, .36, 1)` | all movement (expo-ish ease-out) |
| `--spring` | `cubic-bezier(.34, 1.4, .64, 1)` | settle / pop / overshoot |
| `--lp-ease` | `cubic-bezier(.2, .7, .2, 1)` | landing buttons, FAQ chevron |
| `--acct-ease` | `cubic-bezier(.2, .8, .2, 1)` | dialogs, panel, toast |
| hover / colour | `.15s` to `.2s` | buttons, inputs, rows |
| press | `.16s` to `.18s`, `scale(.96)`..`.98` | `:active` |
| entrance rise | `.42s` to `.55s` `uiRise` (translateY 10px, fade) | views, cards |
| stagger | `28ms` per card (first 8), `24ms` per row (cap 14), `30ms` per search row | cascades |
| sheet open | `.3s` opacity, `.5s` transform with `--spring` (desktop); `.35s` backdrop | |
| panel slide | `.38s` | account panel |
| toast | `.3s` | |
| dropdown reveal | `.45s --ease` close, `.55s --spring` open (grid `0fr`->`1fr`) | search results |
| landing bob | `6s`/`7s` ease-in-out infinite, 6px | decorative floats only |
| view-transition | `@view-transition { navigation: auto; }` | page crossfade |

Keyframes worth copying:

```css
@keyframes uiRise    { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: none; } }
@keyframes uiFade    { from { opacity: 0; } to { opacity: 1; } }
@keyframes uiPopIn   { from { opacity: 0; transform: scale(.55); } to { opacity: 1; transform: none; } }
@keyframes uiPopover { from { opacity: 0; transform: translateY(-4px); filter: blur(3px); } to { opacity: 1; transform: none; filter: none; } }
@keyframes uiRowIn   { from { opacity: 0; transform: translateY(12px); } to { opacity: 1; transform: none; } }
@keyframes uiLift    { from { opacity: 0; transform: translateY(8px); filter: blur(4px); } to { opacity: 1; transform: none; filter: none; } }
@keyframes uiTileIn  { from { opacity: 0; transform: translateY(10px) scale(.92); } to { opacity: 1; transform: none; } }
@keyframes uiBadgeIn { from { opacity: 0; transform: scale(.4) rotate(-10deg); } to { opacity: 1; transform: none; } }
@keyframes uiScoreIn { from { opacity: 0; transform: scale(.7); } to { opacity: 1; transform: none; } }
@keyframes uiWipe    { from { clip-path: inset(0 100% 0 0 round 3px); } to { clip-path: inset(0 0 0 0 round 3px); } }
@keyframes uiGrowX   { from { transform: scaleX(0); } to { transform: none; } }
@keyframes uiRollInUp  { from { opacity: 0; transform: translateY(55%);  filter: blur(6px); } to { opacity: 1; transform: none; filter: none; } }
@keyframes uiRollOutUp { to { opacity: 0; transform: translateY(-55%); filter: blur(6px); } }
@keyframes lpBob { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-6px); } }
```

Title roll (`UI.roll(el, text, dir)`): old text slides out `.38s` while new text slides in `.5s`
(`up` when moving forward, `down` back), blur 6px; the old copy is removed after 650 ms.
Entrance staggering uses `--ui-i` set per element: `animation-delay: calc(var(--ui-i, 0) * 30ms)`.

### 7.3 Reduced motion (verbatim)

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { transition: none !important; animation: none !important; }
}
/* landing */
@media (prefers-reduced-motion: reduce) { html:has(body.lp) { scroll-behavior: auto; } }
@media (prefers-reduced-motion: no-preference) {
  .lp-float-ai { animation: lpBob 6s ease-in-out infinite; }
}
/* spinner: slows rather than stops */
@media (prefers-reduced-motion: reduce) { body:not(#_) .lh-spinner { animation-duration: 2.4s; } }
```

JS side: `const REDUCE = matchMedia("(prefers-reduced-motion: reduce)");` and every scripted animation
checks `REDUCE.matches` first (e.g. `roll()` just sets the text). Also
`const FINE = matchMedia("(hover: hover) and (pointer: fine)")`, `COARSE = matchMedia("(pointer: coarse)")`,
`PHONE = matchMedia("(max-width: 760px)")`. Hover styles are normally wrapped in `@media (hover: hover)`.

### 7.4 Web haptics (verbatim)

```js
const HAPTIC = { tick: 4, tap: 6 };   // ms
function haptic(kind) {
  if (!COARSE.matches || !navigator.vibrate) return;
  try { navigator.vibrate(HAPTIC[kind] || kind); } catch (_) { /* not allowed yet */ }
}
```

`tick` for each step of a wheel, `tap` when something is chosen. Android only (iOS Safari has no `vibrate`).

### 7.5 iOS motion vocabulary

`.smooth(duration: 0.2 / 0.25 / 0.3 / 0.35 / 0.5)` for state and navigation changes,
`.spring(response: 0.5, dampingFraction: 0.82)` for bars tucking away (`ScrollMinimizer`, threshold
14pt travel, offset < 24 resets), `.snappy` for the copied checkmark, `.easeOut(duration: 0.1 to 0.12)`
for pressed rows, `.contentTransition(.numericText())` for page titles, `.symbolEffect(.replace)`.

---------------------------------------------------------------------------------------------------

## 8. iOS summary

### 8.1 Type

`Theme.swift` (Appendix A): `Font.display(_ size, weight: .bold)` = `.system(size:weight:).width(.condensed)`
(the system's condensed width stands in for Barlow Condensed); `View.displayStyle(size)` =
`.font(.display(size)).textCase(.uppercase).tracking(size * 0.02)`. App init sets
`UINavigationBar.appearance()`: large title `systemFont(34, .heavy, width: .condensed)`, inline title
`systemFont(18, .bold, width: .condensed)`. Global tint `.tint(Theme.accent)`; `AccentColor` asset =
light `#1769E0`, dark `#5B9BFF`. Body type is the system font (SF), not Inter. Typical sizes:
card head 20 (display), page title 30 (display), row title 15 semibold, secondary 12, micro labels
10 to 10.5 semibold/bold uppercase with `.tracking(0.6)`.

### 8.2 Components (`Design/Components.swift`, signatures)

- `TeamBadge(name:icon:color:logo:size:corner:)`: fantasy-team mark; remote logo bare, else initials/emoji on a `tint` to `#0B1220` diagonal gradient with an inset 35% white rim.
- `enum Initials { static func of(_ name: String) -> String }`: first letters of up to 2 capitalised words.
- `Card(padding:content:)`: white (`Theme.card`) 14pt continuous radius, 1pt `Theme.line` stroke, `0.05` shadow (radius 1, y 1) on the shape only.
- `CardHead(title:symbol:meta:)`: 24pt ink chip with SF Symbol, title `displayStyle(20)`, meta 12 medium `ink3`, bottom hairline.
- `CardIcon`: SF Symbol name constants (`list.bullet`, `calendar`, `trophy.fill`...).
- `PageTitle(text:)`: 5x28 accent capsule + `displayStyle(30)`, `.numericText()` transition.
- `StatPair(label:value:valueColor:)`: 10pt uppercase label over 13 semibold monospaced value.
- `Superlative(label:title:detail:)`: `surface2` tile, 10pt radius.
- `ClubChip(club:)`, `NFLClub.colors` (Appendix B).
- `LoadingCard(title:detail:)`, `EmptyCard(title:detail:symbol:)` (uses `ContentUnavailableView`).
- `AdaptiveGrid(minWidth:340, spacing:14)`, `PairRow(minWidth:320, spacing:14)` (`ViewThatFits`), `PageScroll(maxWidth:1180, onScroll:)` (page bg `Theme.page`, 16pt gutters, 14pt spacing).
- `ScrollMinimizer` (`@Observable`): tucks a bar on scroll-down, restores on scroll-up.
- `Haptics.select()` / `Haptics.tap(.light)` (UIKit generators), `Felt(style)` PrimitiveButtonStyle wrapper that adds a light tap to any button style (`Felt(.glass)`, `Felt(.glassProminent)`, `Felt(RowPressStyle())`).
- `View.frosted(_ shape, opacity: 0.1)`: white 10% fill + 0.75pt white 14% stroke ("glass without glass"; real glass is for bars only because it re-samples every scroll frame).
- Home (`FinderViews.swift`): `HomeSection(title:meta:footer:content)` (radius 22, `Theme.card`, title `.title3.bold`), `LeagueRow(name:avatar:detail:live:action:)` (12pt gaps, 16/11 padding, chevron `.tertiary`, "LIVE" 9.5 heavy white on green capsule), `RowPressStyle` (surface3 on press, `.easeOut(0.12)`), `RowDivider(inset: 68)`, `FieldBox(symbol:content)` (46pt min height, `surface3` fill, 12 radius continuous, 16pt text, 15 semibold symbol in `ink3`), `PlatformPicker` (system segmented `Picker`), primary action `Button` with `.buttonStyle(Felt(.glassProminent)).controlSize(.large)` and a `ProgressView` swap while loading.
- Notes under forms: `.footnote`, `ink2`; errors `Theme.red`; transitions `.opacity`.
- `IconTile(symbol:color)`: 30x30, 8pt radius, white 15 semibold symbol on `color.gradient` (Settings-app rows).

### 8.3 HeroBackground recipe (`HomeView.swift`, verbatim)

```swift
private struct HeroBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x071827), Color(hex: 0x0D2238)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x1769E0, alpha: 0.30), .clear], center: UnitPoint(x: 0.9, y: 0.05), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(hex: 0xF6B73C, alpha: 0.12), .clear], center: UnitPoint(x: 0.05, y: 1), startRadius: 0, endRadius: 280)
            Canvas { context, size in
                var x: CGFloat = 52
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.04)))
                    x += 53
                }
            }
        }
    }
}
```

Used on `WelcomeCard`: padding 18, `.foregroundStyle(.white)`, `.environment(\.colorScheme, .dark)`, clipped to
radius 22 continuous; feature chips are `white 8%` rounded rects (radius 12) with gold SF Symbols;
CTA is `Felt(.glass)` + `.controlSize(.large)`.

### 8.4 RecapShare canvas recipe (`RecapShare.swift`)

Shareable pictures drawn natively with `ImageRenderer` (scale 1, proposed size 1080 x 1350, forced
`.colorScheme(.dark)`), exported as PNG via `Transferable` (`DataRepresentation(exportedContentType: .png)`),
shared with `ShareLink(items:subject:message:preview:)`. Stage: `TabView(.page)` of pictures
(aspect 1080/1350, radius 14, shadow `.black 0.25, 12, y 6`), buttons `Felt(.glassProminent)` Share,
`.glass` Copy as text (`UIPasteboard`, checkmark for 1.8 s, `.sensoryFeedback(.success)`),
`.glass` Share as text. `presentationDetents([.large])`.

Canvas constants (`enum RecapSheet`): `W = 1080`, `H = 1350`, `PAD = 72`, gold `#F6B73C`,
soft `#DBE5EE @ 0.7`, dim `#DBE5EE @ 0.5`, red `#D71920`.

Frame (`SheetFrame`): vertical gradient stops `#102B43 @0`, `#071827 @0.35`, `#050F1A @1`; a 10px
full-width red bar at the top; league name uppercase 30 bold gold at y = PAD+30; title 104 bold
condensed (display) white at y = PAD+30+92; kicker 28 semibold soft at +46; content starts at
`PAD + 30 + 92 + 46 + 44`; footer: 2px white-12% rule at `H - PAD - 34`, "PIGSKIN PANTHEON" 24 bold
`#DBE5EE @0.75` left and host 24 medium dim right at `H - PAD + 6`. Text helper places by baseline
like canvas `fillText` (x, baseline y, max width with tail truncation, left/center/right);
`wrap(text,font,max,lines)` wraps greedily and runs overflow into the last line. Boxes: white 5-6%
rounded rects radius 12 to 16. Tiles: two per row, `tw = (W - 2*PAD - 24)/2`, `th = 126`,
label 20 bold gold, title 26 bold, detail 21 medium soft. Rows alternate `white 4%` stripes; winner
score in gold, loser at `#DBE5EE @0.6`; movement arrows `#3CCF7A` up / `#FF6B6B` down; badge =
coloured disc with first letter. Headline rule: red 10px bar, headline 62 display bold, dek 26 medium,
"also" bullets with 10px red dots.

Handoff mapping: a daily result card (chain solved in N, streak, emoji-free grid) using this frame:
navy gradient, red top bar, gold kicker, display title, footer rule + wordmark + host.

### 8.5 Other iOS behaviours worth matching

Grouped Settings-style home (large title, sections, footnotes), `.accountToast()` for confirmations,
`.scrollDismissesKeyboard(.interactively)`, iPad is **landscape-first** and two-column
(`horizontalSizeClass == .regular`), `PageScroll` caps content at 1180 (search 1000), universal-link
`?league=<id>` deep link, debug-only launch env vars (`PP_*`) in `#if DEBUG`. Privacy manifest:
`PrivacyInfo.xcprivacy`; Info.plist `ITSAppUsesNonExemptEncryption = NO`.

---------------------------------------------------------------------------------------------------

## 9. Legal pages and footer pattern

### 9.1 Page structure (all three share one template)

Head: `<title>Privacy Policy · Pigskin Pantheon</title>`, canonical, `og:*` (type website, site_name,
title, description, url, image `.../img/landing/og.jpg`), manifest, fonts, theme-color, `ui.css`,
`design.css`, `landing.css`, and a page `<style>` block (the `.lg*` rules + the dark media query in
section 2.4). Body `class="lp"`. Order: skip link, `<header class="lp-nav">` (logo + Privacy/Terms/Support
links with `aria-current="page"` + gold "Open your league" button), `<main class="lg-main" id="main">`
containing `<article class="lg">`, then the shared footer.

```css
.lg-main { width: min(760px, calc(100% - 32px)); margin: 0 auto; padding: 32px 0 56px; }
.lg { background: var(--lg-card); border: 1px solid var(--lg-line); border-radius: 20px; padding: 28px 22px 32px; font-size: 16.5px; line-height: 1.7; color: var(--lg-ink); }
@media (min-width: 640px) { .lg { padding: 44px 48px 52px; } }
.lg h1 { margin: 0 0 6px; font-family: "Barlow Condensed", sans-serif; font-weight: 700; font-size: clamp(34px, 7vw, 46px); line-height: 1.05; letter-spacing: .02em; text-transform: uppercase; color: var(--lg-ink); }
.lg .lg-meta { margin: 0 0 22px; color: var(--lg-muted); font-size: 14.5px; }
.lg h2 { margin: 34px 0 8px; font-size: 21px; line-height: 1.3; font-weight: 700; color: var(--lg-ink); }
.lg h3 { margin: 22px 0 4px; font-size: 17px; font-weight: 700; color: var(--lg-ink); }
.lg p { margin: 0 0 14px; } .lg ul, .lg ol { margin: 0 0 14px; padding-left: 22px; } .lg li { margin: 0 0 7px; }
.lg a { color: var(--lg-link); text-decoration: underline; text-underline-offset: 2px; overflow-wrap: anywhere; }
.lg a:focus-visible, .lg summary:focus-visible { outline: 3px solid var(--lp-gold); outline-offset: 2px; border-radius: 4px; }
.lg .lg-box { margin: 0 0 20px; padding: 16px 18px; background: var(--lg-soft); border: 1px solid var(--lg-line); border-radius: 14px; }
.lg details { margin: 0 0 10px; border: 1px solid var(--lg-line); border-radius: 14px; background: var(--lg-soft); }
.lg summary { cursor: pointer; padding: 14px 18px; font-weight: 700; list-style: none; }
.lg summary::before { content: "+"; display: inline-block; width: 1.2em; font-weight: 700; color: var(--lg-muted); }
.lg details[open] summary::before { content: "\2212"; }
.lg details > div { padding: 0 18px 4px 38px; }
.lg .lg-toc { margin: 0 0 20px; padding: 0; list-style: none; display: flex; flex-wrap: wrap; gap: 8px; }
html:has(body.lp) { scroll-padding-top: 84px; }
```

Section lists (headings with ids for the TOC chips):

- **Privacy** (`Effective October 8, 2026 · Applies to the ... website (...) and the ... iPhone app`): "The short version" box (6 bullets), TOC chips, then Who we are, What we collect (h3s: Account information, What you enter and what you sync, Usage counts, Messages to us, Technical data, On your device), Private ESPN leagues and keys, League data from Sleeper and ESPN, Ask the League (AI chat), Analytics ads and tracking, Payments, How we use information, Who we share with, Retention and deletion, Your rights and choices, Security, International transfers, Children, Changes to this policy, Contact. Tone: first person plural, individual developer in the US, "We do not sell", names every processor (Supabase, Google, Anthropic, Stripe, Cloudflare, GitHub), iPhone app "no ads, no analytics, no tracking", min age 13, deletion in-app or by email.
- **Terms** (17 numbered sections): 1 Acceptance, 2 Eligibility, 3 Your account, 4 Acceptable use, 5 AI chat, 6 Third-party services and trademarks, 7 Your ESPN credentials, 8 Our content and your content, 9 Plans and payments, 10 No warranties, 11 Limitation of liability, 12 Your responsibility, 13 Termination, 14 Changes, 15 Governing law, 16 **Apple App Store terms** (custom EULA: 10 numbered points: acknowledgement, scope of licence, maintenance and support, warranty, product claims, IP claims, legal compliance, developer name and address, third-party terms, third-party beneficiary), 17 Contact.
- **Support**: "Contact us" box (mailto + gold "Email support" button, "run by one person, replies can take a few days"), "Frequently asked questions" as `<details>` (open a league, reset password, delete account, private data/keys, missing history, how the AI works, is it free, affiliation, something is broken: what to send), "More" links.

Checklist per APP_STORE.md: Privacy URL `/privacy.html`, Support URL `/support.html`, a real `support@` mailbox, privacy policy linked from inside the app (Account screen + home footer, `Legal.swift`), account deletion in-app, no ads/tracking (privacy manifest).

### 9.2 Footer pattern and disclaimer (verbatim markup)

```html
<footer class="footer lp-footer">
  <div class="lp-wrap lp-footer-inner">
    <a class="lp-logo lp-logo-sm" href="index.html"><img src="icons/crest.png" alt="" width="28" height="28" /><span>Pigskin <span class="brand-accent">Pantheon</span></span></a>
    <p><a href="privacy.html">Privacy</a> · <a href="terms.html">Terms</a> · <a href="support.html">Support</a></p>
    <p>Not affiliated with or endorsed by Sleeper, ESPN, the NFL or the NFLPA.</p>
  </div>
</footer>
```

The landing page extends the disclaimer: "Not affiliated with or endorsed by Sleeper, ESPN, the NFL or the NFLPA. League data from the
[Sleeper API](https://docs.sleeper.com/) and ESPN Fantasy." App version (`Legal.disclaimer`) is the
same sentence. For Handoff: **"Not affiliated with or endorsed by the NFL, the NFLPA or any NFL team."**
plus the data credit (Sleeper API for player names/headshots), and keep "no logos" (club chips only)
as the reference's trademark-safe pattern. In-app footer shows the same three links.

---------------------------------------------------------------------------------------------------

## 10. Data refresh workflow

`tools/update-players.py` (stdlib only): GET `https://api.sleeper.app/v1/players/nfl` with a
`User-Agent: league-history-players/1.0`, 120 s timeout. Refuses to overwrite if the answer is not a
dict with at least 1000 entries (non-zero exit, keeps the old file). Writes `data/players.json` as
`{` + one `"id":[name,position,club(,eligibleSlots)]` per line + `}`; numeric ids first in numeric
order, then defences by club code, so a day's diff shows only changed players. Defence entry:
`["<Last> D/ST","DST",pid]`. `eligible` (fantasy_positions) is appended only if it differs from the
position's implied slot (`IMPLIED = {DE:DL, DT:DL, NT:DL, CB:DB, S:DB, SS:DB, FS:DB, ILB:LB, OLB:LB, MLB:LB, DEF:DEF}`).
Sleeper asks that this ~5 MB file is fetched at most once a day, hence the cron. Site reads the
slim copy (`fetchJSON("data/players.json")`), never Sleeper's; iOS bundles the JS and fetches only
this data file (App Review 2.5.2).

Workflow, verbatim (`.github/workflows/update-players.yml`):

```yaml
# Refreshes data/players.json from Sleeper once a day, in the morning, so
# the site never asks Sleeper for its players file itself (Sleeper asks for
# that file to be fetched at most once a day and kept on our side).
#
# Scheduled runs only happen from the repository's default branch, and
# GitHub may start them a little late when it is busy. "Run workflow" on the
# Actions tab runs it by hand.
name: Update players

on:
  schedule:
    - cron: "0 12 * * *"   # 12:00 UTC: 8am Eastern / 7am Central in summer, an hour earlier in winter
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: update-players
  cancel-in-progress: false

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Fetch Sleeper's players file
        run: python tools/update-players.py

      - name: Commit if anything changed
        run: |
          if git diff --quiet -- data/players.json; then
            echo "No player changes today."
            exit 0
          fi
          git config user.name "github-actions[bot]"
          git config user.email "41898283+github-actions[bot]@users.noreply.github.com"
          git add data/players.json
          git commit -m "Update players from Sleeper ($(date -u +%Y-%m-%d))"
          git push
```

Handoff note: the daily puzzle likely needs a second scheduled job (build tomorrow's chain). Same
pattern: cron at 12:00 UTC (08:00 ET), `contents: write`, `concurrency` group with
`cancel-in-progress: false`, commit only when `git diff --quiet` fails, bot identity above.

---------------------------------------------------------------------------------------------------

## 11. Build checklist for Handoff (PROPOSAL, derived from the above)

1. One `tokens` block (section 2.5) with light + dark, `color-scheme: light dark`, no hard-coded `#fff`.
2. Navy header (frosted `rgba(7,24,39,.84)` + blur 18) with the crest/wordmark, second word in gold, 4px red rule under the hero.
3. Hero uses the `.lp-hero` recipe; game surface is white `.card`s (14px radius, hairline, 1px shadow).
4. Titles Barlow Condensed uppercase; everything else Inter; numbers tabular.
5. Chain nodes use club chips (abbr on primary, luminance ink) and Sleeper headshots with chip fallback; no logos.
6. Search: `norm()` verbatim, all-words substring match, prefix-first ranking, 8 results, per-keystroke with a sequence guard (add a 0 to 120 ms debounce if the roster is large), Enter picks first, arrows walk, `/` focuses, Escape clears.
7. Motion: `--ease` / `--spring`, press scale .96 to .98, stagger rows 24 to 30 ms, a global reduced-motion kill switch, `@media (hover: hover)` guards.
8. Sheets: frosted, 24px radius, swipe-down on phones, `Escape` closes the top layer.
9. Footer: yard-tick row, links to Privacy / Terms / Support, "Not affiliated with or endorsed by the NFL, the NFLPA or any NFL team."
10. Legal pages from the `.lg` template (with the `prefers-color-scheme` block), App Store basics from `ios/APP_STORE.md`.
11. iOS later: copy Appendix A and B; deployment target 26.1 matches the reference; use `Felt(...)` for haptics.

---------------------------------------------------------------------------------------------------

## Appendix A: `ios/PigskinPantheon/Design/Theme.swift` (full, verbatim)

```swift
import SwiftUI
import UIKit

/// The site's design language (design.css, ui.css), as SwiftUI tokens:
/// quiet white cards on a hairline, grey-blue labels, navy ink, the
/// league's blue accent and gold. Every colour has a dark-mode twin.
enum Theme {
    // Ink
    static let ink = Color(light: 0x0B1F3F, dark: 0xEEF2F8)
    static let ink2 = Color(light: 0x475467, dark: 0xC2CAD6)
    static let ink3 = Color(light: 0x8A94A6, dark: 0x8C97A9)
    static let muted = Color(light: 0x667085, dark: 0x98A2B3)

    // Surfaces
    static let page = Color(light: 0xEEF1F5, dark: 0x060E19)
    static let card = Color(light: 0xFFFFFF, dark: 0x101B2B)
    static let surface2 = Color(light: 0xF7F8FA, dark: 0x15223A)
    static let surface3 = Color(light: 0xEEF1F5, dark: 0x1B2A42)
    static let line = Color(light: 0xE4E7EC, dark: 0x22324B)
    static let line2 = Color(light: 0xD5DAE1, dark: 0x2C3E5C)

    // Accent
    static let accent = Color(light: 0x1769E0, dark: 0x5B9BFF)
    static let accentInk = Color(light: 0x0F56BD, dark: 0x8AB8FF)
    static let accentSoft = Color(light: 0xEDF3FF, dark: 0x13284A)

    // The league's own
    static let navy = Color(hex: 0x071827)
    static let navy2 = Color(hex: 0x0F2A4A)
    static let gold = Color(hex: 0xF6B73C)
    static let goldInk = Color(light: 0x8A5A00, dark: 0xF6C661)
    static let goldSoft = Color(light: 0xFDF1D8, dark: 0x3A2B0C)
    static let red = Color(light: 0xD92D20, dark: 0xFF6B5E)
    static let redSoft = Color(light: 0xFEF3F2, dark: 0x3A1414)
    static let green = Color(light: 0x079455, dark: 0x47CD89)

    static let cardRadius: CGFloat = 14
    static let gutter: CGFloat = 16
}

// MARK: Type

extension Font {
    /// Barlow Condensed on the site: the titles that name a thing. Here the
    /// system's own condensed width, bold, set in capitals by the caller.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

extension View {
    /// A display title: condensed, bold, upper case, tracked out a little.
    func displayStyle(_ size: CGFloat) -> some View {
        self.font(.display(size)).textCase(.uppercase).tracking(size * 0.02)
    }
}

// MARK: Colour helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    init(light: UInt32, dark: UInt32) {
        // Both made once: the provider runs each time the colour is drawn.
        let l = UIColor(hex: light), d = UIColor(hex: dark)
        self.init(UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }

    /// A CSS colour as the engine writes them: "#304f91" or "hsl(120 42% 38%)".
    init?(css: String?) {
        guard let css = css?.trimmingCharacters(in: .whitespaces), !css.isEmpty else { return nil }
        if css.hasPrefix("#") {
            var hex = String(css.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let value = UInt32(hex, radix: 16) else { return nil }
            self.init(hex: value)
            return
        }
        if css.hasPrefix("hsl") {
            let numbers = css.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
                .compactMap(Double.init)
            guard numbers.count >= 3 else { return nil }
            let h = numbers[0] / 360, s = numbers[1] / 100, l = numbers[2] / 100
            // HSL to HSB
            let v = l + s * min(l, 1 - l)
            let sb = v == 0 ? 0 : 2 * (1 - l / v)
            self.init(hue: h, saturation: sb, brightness: v)
            return
        }
        return nil
    }

    /// Black or white, whichever reads on this colour (the site's readableInk).
    static func readableInk(on hex: String?) -> Color {
        guard let hex, hex.hasPrefix("#"), let n = UInt32(hex.dropFirst(), radix: 16) else { return .white }
        let lum = (0.299 * Double((n >> 16) & 255) + 0.587 * Double((n >> 8) & 255) + 0.114 * Double(n & 255)) / 255
        return lum > 0.62 ? Color(hex: 0x0B1726) : .white
    }
}

// MARK: Numbers, as the site writes them

enum Fmt {
    private static let two: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// 1,209.32
    static func pts(_ n: Double?) -> String {
        guard let n else { return "—" }
        return two.string(from: NSNumber(value: n)) ?? String(format: "%.2f", n)
    }
    /// 120.9
    static func one(_ n: Double) -> String { String(format: "%.1f", n) }
    /// .594
    static func pct(_ v: Double) -> String {
        let s = String(format: "%.3f", v)
        return s.hasPrefix("0") ? String(s.dropFirst()) : s
    }
    /// +240.45 / -36.51
    static func signed(_ n: Double) -> String { (n > 0 ? "+" : "") + pts(n) }

    static func ordinal(_ n: Int) -> String {
        // The site's: s[(v - 20) % 10] || s[v] || s[0]
        let s = ["th", "st", "nd", "rd"], v = n % 100, i = (v - 20) % 10
        let suffix = (0..<4).contains(i) ? s[i] : (0..<4).contains(v) ? s[v] : s[0]
        return "\(n)\(suffix)"
    }

    static func record(_ w: Int, _ l: Int, _ t: Int = 0) -> String { t > 0 ? "\(w)–\(l)–\(t)" : "\(w)–\(l)" }

    static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : (many ?? one + "s"))"
    }
}

/// A column of records. Its width is set for W–L ("10–3"), and a tie adds
/// a third number ("10–3–1") that the width can't hold. The column widens
/// to the widest record in it, measured in the column's own type, and keeps
/// its set width while nobody in it has tied.
enum RecordColumn {
    static func width(_ records: some Sequence<String>, size: CGFloat, weight: UIFont.Weight, atLeast base: CGFloat = 0) -> CGFloat {
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        let widest = records.reduce(0) { max($0, ($1 as NSString).size(withAttributes: [.font: font]).width) }
        // A point either side for the rounding between this and SwiftUI.
        return max(base, ceil(widest) + 2)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
```

## Appendix B: `ClubChip` and `NFLClub` (verbatim from `Design/Components.swift`)

Note: `NFLClub.colors` has the 32 current clubs plus `FA`; no historical keys. Normalise legacy codes (WAS, JAC, OAK, SD, STL, LA) to current ones before lookup, as `sleeper.js` does. `Color.readableInk(on:)` and `Color(css:)` live in Theme.swift (Appendix A).

```swift
/// An NFL club as its abbreviation on the club's colour (no logos).
struct ClubChip: View {
    let club: String
    var body: some View {
        let hex = NFLClub.colors[club]
        Text(club)
            .font(.system(size: 9.5, weight: .heavy))
            .foregroundStyle(Color.readableInk(on: hex))
            .padding(.horizontal, 4)
            .frame(minWidth: 28, minHeight: 15)
            .background(Color(css: hex) ?? Theme.ink3, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

enum NFLClub {
    static let colors: [String: String] = [
        "ARI": "#97233F", "ATL": "#A71930", "BAL": "#241773", "BUF": "#00338D", "CAR": "#0085CA", "CHI": "#0B162A",
        "CIN": "#FB4F14", "CLE": "#311D00", "DAL": "#041E42", "DEN": "#FB4F14", "DET": "#0076B6", "GB": "#203731",
        "HOU": "#03202F", "IND": "#002C5F", "JAX": "#101820", "KC": "#E31837", "LAC": "#0080C6", "LAR": "#003594",
        "LV": "#111111", "MIA": "#008E97", "MIN": "#4F2683", "NE": "#002244", "NO": "#A08A5B", "NYG": "#0B2265",
        "NYJ": "#125740", "PHI": "#004C54", "PIT": "#FFB612", "SEA": "#002244", "SF": "#AA0000", "TB": "#D50A0A",
        "TEN": "#0C2340", "WSH": "#5A1414", "FA": "#8A94A1",
    ]
}
```

## Appendix C: haptics and the tap-back button style (verbatim from `Design/Components.swift`)

```swift

/// The taps the app gives back, for the places a modifier can't reach
/// (UIKit gestures, the trophy room's scene). Views use `.sensoryFeedback`.
@MainActor
enum Haptics {
    /// A detent: a stop passed, a choice changed.
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    /// Something opened or landed.
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

/// A button that taps back: drawn in the style it names (`Felt(.glass)`,
/// `Felt(.plain)`, `Felt(RowPressStyle())`), with a light tap as its action
/// runs. On the action, not the touch, so a scroll that begins on a row
/// stays quiet. A button whose action already answers with feedback of its
/// own (a sort, a week, a tab, the trophy room's steps) keeps its plain
/// style, so nothing taps twice.
struct Felt: PrimitiveButtonStyle {
    private let draw: @MainActor (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        draw = { c in
            AnyView(Button(role: c.role) { Haptics.tap(); c.trigger() } label: { c.label }.buttonStyle(style))
        }
    }

    init<S: ButtonStyle>(_ style: S) {
        draw = { c in
            AnyView(Button(role: c.role) { Haptics.tap(); c.trigger() } label: { c.label }.buttonStyle(style))
        }
    }

    func makeBody(configuration: Configuration) -> some View { draw(configuration) }
}

extension View {
    /// A pane of white over a dark hero (a stat tile, a badge): the look of
    /// tinted glass without glass, which belongs to the bars over the page.
    /// Glass in the page re-samples what's behind it on every frame of a
    /// scroll; a fill is drawn once.
    func frosted<S: InsettableShape>(_ shape: S, opacity: Double = 0.1) -> some View {
        background(.white.opacity(opacity), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.75))
    }
}
```
