// End-to-end check of the Chainmates web MVP. Usage: node e2e.js <shotsDir>
const { chromium } = require('playwright');
const fs = require('fs');
const H = require('../../core/handoff-core.js');
const OUT = process.argv[2];
const BASE = process.env.BASE_URL || 'http://localhost:8765/';
const NOW = new Date('2026-10-16T16:00:00Z');
const players = JSON.parse(fs.readFileSync(require('path').join(__dirname, '../../data/nfl/') + 'players.json'));
const puzzles = JSON.parse(fs.readFileSync(require('path').join(__dirname, '../../data/nfl/') + 'puzzles.json'));
const idx = H.buildIndex(players);
const pz = H.puzzleForDate(puzzles, H.easternDate(NOW));
const name = (id) => H.player(idx, id).name;
// what the stored optimal chain scores in the default mode (hard: par = fewest + 2, so an Eagle), straight from the core
const optimalLabel = H.score(Object.assign(H.newGame(pz), { chain: pz.chain.slice(), status: 'won' })).label;
// a famous player who never played with the start player (and isn't the finish)
const miss = players.players.map((r) => r[0]).find((id) => id !== pz.start && id !== pz.end && !pz.chain.includes(id) && !H.areTeammates(idx, pz.start, id));
let failures = 0;
const check = (ok, msg) => { console.log((ok ? 'PASS ' : 'FAIL ') + msg); if (!ok) failures++; };

async function pickPlayer(p, id, partial) {
  await p.fill('#guess', partial || name(id));
  const row = p.locator(`#acList [data-id="${id}"]`);
  await row.waitFor({ timeout: 4000 });
  await row.click();
}

async function run(b, { label, width, height, scheme, mobile, full }) {
  const ctx = await b.newContext({ viewport: { width, height }, deviceScaleFactor: 2, colorScheme: scheme, hasTouch: mobile, isMobile: mobile });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: BASE.replace(/\/$/, '') });
  const p = await ctx.newPage();
  await p.clock.setFixedTime(NOW);
  const errors = [];
  p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  p.on('pageerror', (e) => errors.push(e.message));
  const shot = (n, opts) => p.screenshot({ path: `${OUT}/${label}-${n}.png`, ...(opts || {}) });

  await p.goto(BASE);
  if (full) { await p.waitForTimeout(30); }
  await p.waitForSelector('#viewGame:not([hidden])');
  await p.waitForSelector('#dlgHelp[open]');
  if (full) { await p.waitForTimeout(120); await shot('f0-help-rising'); }
  check(true, `${label}: how-to-play opens on first visit`);
  await p.waitForTimeout(600);
  if (full) await shot('0-howto');
  await p.waitForTimeout(400);
  await p.click('#dlgHelp [data-close].btn');
  await p.waitForTimeout(600);
  check(await p.locator('#heroInner').innerText().then((t) => t.includes('No. ' + pz.n)), `${label}: hero shows puzzle #${pz.n}`);
  check((await p.evaluate(() => window.__chainmates.difficulty)) === H.DEFAULT_MODE, `${label}: new game starts in ${H.DEFAULT_MODE} mode`);
  check((await p.locator('.pb-par').innerText()).trim() === 'Par ' + H.parFor(pz, H.DEFAULT_MODE), `${label}: par badge shows the mode's par`);
  check((await p.locator('#heroInner .pcard .club, #chain .node .club').count()) === 0, `${label}: hard mode shows no player teams`);
  await shot('1-fresh');

  if (full) {
    // incompletion
    await pickPlayer(p, miss);
    await p.waitForTimeout(140);
    await shot('f1-miss-midframe');
    await p.waitForTimeout(10);
    const t = await p.locator('#toasts').innerText();
    check(/Incompletion — .* were never teammates/.test(t) && /2 downs left/.test(t), `${label}: incompletion toast "${t.replace(/\n/g, ' | ')}"`);
    check((await p.locator('.down.used').count()) === 1, `${label}: one down used`);
    await p.waitForTimeout(3800);
    // rejected (start player) costs nothing: start is excluded from search, so this checks exclusion
    await p.fill('#guess', name(pz.start));
    await p.waitForTimeout(250);
    check((await p.locator(`#acList [data-id="${pz.start}"]`).count()) === 0, `${label}: chain players excluded from autocomplete`);
    // link + undo
    await pickPlayer(p, pz.chain[1]);
    await p.waitForTimeout(170);
    await shot('f2-link-midframe');
    await p.waitForTimeout(500);
    check((await p.locator('#chain .step').count()) === 2, `${label}: link added`);
    const conn = await p.locator('#chain .step >> nth=1 >> .conn').innerText();
    check(/Teammates on the \d{4} /.test(conn), `${label}: connector reason "${conn.replace(/\n/g, ' ')}"`);
    await p.click('#btnUndo');
    await p.waitForTimeout(130);
    await shot('f3-undo-midframe');
    check((await p.locator('#chain .step.retract').count()) === 1, `${label}: undo retract animation runs`);
    await p.waitForTimeout(450);
    check((await p.locator('#chain .step').count()) === 1, `${label}: undo removed the link`);
    check((await p.locator('.down.used').count()) === 1, `${label}: undo is free`);
    await p.waitForTimeout(3500);
    // persistence: reload resumes
    await p.reload();
    await p.waitForSelector('#viewGame:not([hidden])');
    check((await p.locator('.down.used').count()) === 1, `${label}: reload resumes saved state`);
  } else if (label.startsWith('desktop')) {
    // hint flow: confirm, costs a down, stays visible
    await p.click('#btnHint');
    await p.waitForSelector('#dlgHint[open]');
    await p.click('#hintOk');
    await p.waitForTimeout(300);
    const hint = await p.locator('#hintPill').innerText();
    check(/^Hint\. /.test(hint) && (await p.locator('#hintPill .club').count()) === 1, `${label}: hint shown "${hint.replace(/\n/g, ' ')}"`);
    check((await p.locator('.down.used').count()) === 1, `${label}: hint cost a down`);
    await p.waitForTimeout(3500);
  }

  // mid-game: one link + autocomplete open
  await pickPlayer(p, pz.chain[1]);
  await p.waitForTimeout(600);
  const nm = name(pz.chain[2]);
  await p.click('#guess');
  await p.type('#guess', nm.slice(0, 4), { delay: 30 });
  await p.waitForSelector('#acList:not([hidden]) .ac-row');
  await p.waitForTimeout(500);
  await shot('2-midgame-autocomplete');
  // keyboard: arrow down / up / Esc
  await p.keyboard.press('ArrowDown');
  check((await p.getAttribute('#guess', 'aria-activedescendant')) === 'ac-1', `${label}: ArrowDown moves the active row`);
  if (full) { await p.waitForTimeout(70); await shot('f9-highlight-gliding'); }
  await p.keyboard.press('Escape');
  check(await p.locator('#acList').isHidden(), `${label}: Esc closes the list`);

  // finish the stored optimal chain
  const mids = pz.chain.slice(2, -1);
  for (const id of mids.slice(0, -1)) { await pickPlayer(p, id); await p.waitForTimeout(700); }
  await pickPlayer(p, mids[mids.length - 1]);
  if (full) {
    await p.waitForTimeout(820);
    check((await p.locator('#chainCard.lock').count()) === 1, `${label}: lock-up runs on solve`);
    await shot('f4-lockup-midframe');
  }
  await p.waitForSelector('#sheet[open]', { timeout: 6000 });
  if (full) { await p.waitForTimeout(160); await shot('f5-sheet-rising'); }
  await p.waitForTimeout(1900);
  const sheetText = await p.locator('#sheet').innerText();
  check((await p.locator('.score-big').innerText()).trim() === optimalLabel, `${label}: solved sheet shows ${optimalLabel}`);
  check(sheetText.includes(`${pz.optimal.toLocaleString('en-US')} optimal chains exist`), `${label}: optimal count shown`);
  const share = await p.locator('#sharePreview').innerText();
  check(share.split('\n')[0].endsWith(' · Hard'), `${label}: hard share line "${share.split('\n')[0]}"`);
  check(share.startsWith('Chainmates #' + pz.n) && share.includes('cev64.github.io/chainmates/#' + pz.n) && share.includes(optimalLabel === 'Par' ? '\u26f3' : optimalLabel), `${label}: share text ok`);
  await shot('3-results');
  await p.click('#btnCopy');
  await p.waitForTimeout(300);
  const clip = await p.evaluate(() => navigator.clipboard.readText()).catch(() => '');
  check(clip === share, `${label}: copy puts the share text on the clipboard`);
  if (full) { await p.locator('#sheetScroll').evaluate((e) => e.scrollTo(0, e.scrollHeight)); await p.waitForTimeout(300); await shot('3b-results-bottom'); }
  if (full) {
    // drag the sheet a little: it follows the finger, then springs back
    await p.locator('#sheetScroll').evaluate((e) => e.scrollTo(0, 0));
    await p.waitForTimeout(200);
    const hero = await p.locator('.sheet-hero').boundingBox();
    const x = hero.x + hero.width / 2, y = hero.y + 60;
    await p.mouse.move(x, y); await p.mouse.down();
    for (let i = 1; i <= 8; i++) { await p.mouse.move(x, y + i * 15); await p.waitForTimeout(40); }
    await shot('f6-sheet-dragging');
    const ty = await p.locator('#sheet .sheet-panel').evaluate((e) => e.style.transform);
    check(/translateY\(1[12]\d/.test(ty), `${label}: sheet follows the drag (${ty})`);
    await p.waitForTimeout(250);
    await p.mouse.up();
    await p.waitForTimeout(700);
    check(await p.locator('#sheet').evaluate((d) => d.open), `${label}: slow small drag springs back`);
    // a quick flick dismisses it
    await p.mouse.move(x, y); await p.mouse.down();
    for (let i = 1; i <= 4; i++) { await p.mouse.move(x, y + i * 40); await p.waitForTimeout(12); }
    await p.mouse.up();
    await p.waitForTimeout(600);
    check(!(await p.locator('#sheet').evaluate((d) => d.open)), `${label}: flick dismisses the sheet`);
    await p.click('#btnSeeResults');
    await p.waitForTimeout(500);
    await p.waitForTimeout(200);
  }
  await p.keyboard.press('Escape');
  await p.waitForTimeout(900);
  check(!(await p.locator('#sheet').evaluate((d) => d.open)), `${label}: Esc closes the sheet`);
  await shot('4-solved-board', { fullPage: true });

  if (full) {
    await p.click('#btnStats');
    await p.waitForTimeout(90);
    await shot('f7-view-transition');
    await p.waitForTimeout(260);
    await shot('f8-stats-counting');
  } else await p.goto(BASE + '#stats');
  await p.waitForSelector('#viewStats:not([hidden])');
  await p.waitForTimeout(1500);
  check((await p.locator('.tile >> nth=0 >> b').innerText()) === '1', `${label}: stats count 1 game`);
  await shot('5-stats');
  await p.goto(BASE + '#archive');
  await p.waitForSelector('#viewArchive:not([hidden])');
  await p.waitForTimeout(800);
  await shot('6-archive');

  if (full) {
    // practice mode: older puzzle, doesn't touch stats
    await p.click(`a[href="#${pz.n - 1}"]`);
    await p.waitForSelector('#viewGame:not([hidden])');
    check(/practice/i.test(await p.locator('#heroInner').innerText()), `${label}: archive opens practice mode`);
    await shot('7-practice');
    // future puzzle is locked
    await p.goto(BASE + '#' + (pz.n + 3));
    await p.waitForTimeout(300);
    const st = await p.locator('#viewStatus').innerText();
    check(/Not available yet/i.test(st), `${label}: future puzzle locked`);
    await shot('8-future');
  }
  check(errors.length === 0, `${label}: no console errors ${errors.join(' | ')}`);
  await ctx.close();
}

(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  console.log(`puzzle #${pz.n}: ${pz.chain.map(name).join(' -> ')}; miss guess: ${name(miss)}`);
  await run(b, { label: 'phone-light', width: 390, height: 844, scheme: 'light', mobile: true, full: true });
  await run(b, { label: 'phone-dark', width: 390, height: 844, scheme: 'dark', mobile: true });
  await run(b, { label: 'desktop-light', width: 1280, height: 800, scheme: 'light', mobile: false });
  await b.close();
  console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
  process.exit(failures ? 1 : 0);
})();
// legal pages
(async () => {})();
