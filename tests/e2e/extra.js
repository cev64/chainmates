const { chromium } = require('playwright');
const fs = require('fs');
const H = require('../../core/handoff-core.js');
const pj = JSON.parse(fs.readFileSync(require('path').join(__dirname, '../../data/nfl/') + 'players.json'));
const zj = JSON.parse(fs.readFileSync(require('path').join(__dirname, '../../data/nfl/') + 'puzzles.json'));
const idx = H.buildIndex(pj);
const NOW = new Date('2026-10-16T16:00:00Z');
const today = H.puzzleForDate(zj, H.easternDate(NOW));
const pz = H.puzzleByNumber(zj, today.n - 1);
const misses = pj.players.map(r => r[0]).filter(id => id !== pz.start && id !== pz.end && !H.areTeammates(idx, pz.start, id)).slice(0, 3);
let fails = 0; const check = (ok, m) => { console.log((ok ? 'PASS ' : 'FAIL ') + m); if (!ok) fails++; };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, reducedMotion: 'reduce' });
  const p = await ctx.newPage(); await p.clock.setFixedTime(NOW);
  const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
  await p.addInitScript(() => { try { localStorage.setItem('chainmates.nfl.seen-help', '1'); } catch (e) {} });
  await p.goto('http://localhost:8765/#' + pz.n);
  await p.waitForSelector('#viewGame:not([hidden])');
  check(!(await p.locator('#dlgHelp').evaluate(d => d.open)), 'help not shown when already seen');
  // hint disabled on last down
  for (let i = 0; i < 3; i++) {
    if (i === 2) check(await p.locator('#btnHint').isDisabled(), 'hint disabled on the last down');
    await p.fill('#guess', H.player(idx, misses[i]).name);
    await p.locator(`#acList [data-id="${misses[i]}"]`).click();
    await p.waitForTimeout(100);
  }
  await p.waitForSelector('#sheet[open]');
  check((await p.locator('.score-big').innerText()).trim() === 'X', 'loss shows X');
  check((await p.locator('#sharePreview').innerText()).includes('Turnover on downs'), 'loss share text');
  check(/doesn't count/.test(await p.locator('#sheet').innerText()), 'practice note in sheet');
  await p.screenshot({ path: process.argv[2] + '/phone-light-9-lost-practice.png' });
  await p.keyboard.press('Escape'); await p.waitForTimeout(200);
  await p.screenshot({ path: process.argv[2] + '/phone-light-9b-lost-board.png', fullPage: true });
  const stats = await p.evaluate(() => localStorage.getItem('chainmates.nfl.stats'));
  check(stats === null, 'practice did not touch stats');
  await p.goto('http://localhost:8765/#archive'); await p.waitForTimeout(300);
  const row = await p.locator(`a[href="#${pz.n}"]`).innerText();
  check(/X/.test(row) && /practice/i.test(row), 'archive shows practice X badge: ' + row.replace(/\n/g, ' '));
  // theme toggle persists
  await p.click('#btnTheme'); await p.click('#btnTheme');
  check(await p.evaluate(() => document.documentElement.dataset.theme) === 'dark', 'theme toggle -> dark');
  await p.reload(); await p.waitForTimeout(200);
  check(await p.evaluate(() => document.documentElement.dataset.theme) === 'dark', 'theme persists before paint');
  // horizontal overflow
  for (const h of ['', '#archive', '#stats', '#' + pz.n]) {
    await p.goto('http://localhost:8765/' + h); await p.waitForTimeout(250);
    check(await p.evaluate(() => document.documentElement.scrollWidth) <= 390, 'no horizontal scroll at ' + (h || 'today'));
  }
  // load failure
  const ctx2 = await b.newContext({ viewport: { width: 390, height: 844 } });
  const p2 = await ctx2.newPage();
  await p2.route('**/players.json', r => r.abort());
  await p2.goto('http://localhost:8765/'); await p2.waitForTimeout(500);
  check(/couldn't load/i.test(await p2.locator('#viewStatus').innerText()), 'error state when data fails');
  await p2.screenshot({ path: process.argv[2] + '/phone-light-10-error.png' });
  check(errs.length === 0, 'no console errors ' + errs.join('|'));
  await b.close();
  console.log(fails ? fails + ' FAILURES' : 'ALL PASS');
})();
