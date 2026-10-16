// Safe Enter, space-insensitive search, and re-viewing a past daily. Usage: node ux.js <shotsDir>
const { chromium } = require('playwright');
const fs = require('fs');
const H = require('../../core/handoff-core.js');
const pj = JSON.parse(fs.readFileSync(require('path').join(__dirname, '../../data/nfl/') + 'players.json'));
const zj = JSON.parse(fs.readFileSync(require('path').join(__dirname, '../../data/nfl/') + 'puzzles.json'));
const idx = H.buildIndex(pj);
const SHOTS = process.argv[2];
let fails = 0; const check = (ok, m) => { console.log((ok ? 'PASS ' : 'FAIL ') + m); if (!ok) fails++; };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
  const p = await ctx.newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e))); p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  await p.clock.install({ time: new Date('2026-10-16T16:00:00Z') });
  await p.goto('http://localhost:8765/');
  await p.waitForSelector('#guess', { state: 'visible' });
  await p.evaluate(() => { const d = document.querySelector('dialog[open]'); if (d) d.close(); });
  const pz = H.puzzleForDate(zj, '2026-10-16');
  const downs = () => p.evaluate(() => JSON.parse(localStorage.getItem('chainmates.nfl.daily.5') || '{}').downs);
  // 1) Enter on an ambiguous partial name must not guess
  await p.fill('#guess', 'mar'); await p.clock.runFor(300); await p.keyboard.press('Enter'); await p.clock.runFor(300);
  const st1 = await p.evaluate(() => JSON.parse(localStorage.getItem('chainmates.nfl.daily.5') || 'null'));
  check(!st1 || st1.chain.length === 1 && st1.downs === 3, 'Enter on "mar" does not guess');
  // 2) "le veon" finds Le'Veon Bell
  await p.fill('#guess', 'le veon'); await p.clock.runFor(300);
  const first = await p.textContent('.ac-row');
  check(/Le.Veon Bell/.test(first), '"le veon" -> ' + first.trim().slice(0, 30));
  // 3) Play the stored chain via exact names + Enter
  for (const id of pz.chain.slice(1, -1)) {
    const name = H.player(idx, id).name;
    await p.fill('#guess', name); await p.clock.runFor(300);
    const rows = await p.$$eval('.ac-row', rs => rs.map(r => r.dataset.id));
    const i = rows.indexOf(id);
    for (let k = 0; k < i; k++) await p.keyboard.press('ArrowDown');
    await p.keyboard.press('Enter'); await p.clock.runFor(1500);
  }
  await p.clock.runFor(3000);
  const st = await p.evaluate(() => JSON.parse(localStorage.getItem('chainmates.nfl.daily.5')));
  check(st.status === 'won', 'daily #5 won');
  const sub = await p.textContent('.sheet, dialog[open]').catch(() => '');
  check(!/0 hints|0 incompletions/.test(sub), 'zero counts hidden in sheet');
  // 4) Next day: archive -> #5 shows the daily result with Replay
  await p.clock.setSystemTime(new Date('2026-10-17T16:00:00Z'));
  await p.goto('http://localhost:8765/#5'); await p.waitForSelector('#resultStrip:not([hidden])', { timeout: 5000 }).catch(() => {});
  await p.evaluate(() => { const d = document.querySelector('dialog[open]'); if (d) d.close(); });
  const strip = await p.textContent('#resultStrip').catch(() => '');
  check(/Par/.test(strip) && /Replay as practice/.test(strip), 'past daily shows its result + Replay (' + strip.replace(/\s+/g, ' ').trim() + ')');
  await p.screenshot({ path: SHOTS + '/past-daily.png' });
  await p.click('text=Replay as practice'); await p.clock.runFor(800);
  const chainLen = await p.evaluate(() => document.querySelectorAll('#chain .chain-card, #chain li').length);
  const url = p.url();
  check(/#p5$/.test(url), 'replay goes to #p5');
  const prac = await p.evaluate(() => localStorage.getItem('chainmates.nfl.practice.5'));
  const strip2 = await p.isHidden('#resultStrip');
  check(strip2, 'practice replay starts fresh (no result strip)');
  await p.screenshot({ path: SHOTS + '/practice-replay.png' });
  check(errs.length === 0, 'no console errors ' + errs.join(' | '));
  await b.close();
  console.log(fails ? 'FAILURES ' + fails : 'ALL PASS');
})();
