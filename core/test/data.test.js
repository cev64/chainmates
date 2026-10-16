'use strict';
// Validates real data under data/<sport>/{players,puzzles}.json when present (skips gracefully otherwise).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const H = require('../handoff-core.js');

const DATA = path.join(__dirname, '../../data');
const sports = fs.existsSync(DATA)
  ? fs.readdirSync(DATA).filter((d) => fs.existsSync(path.join(DATA, d, 'players.json')) && fs.existsSync(path.join(DATA, d, 'puzzles.json')))
  : [];

if (!sports.length) {
  test('real data', (t) => t.skip('no data/<sport>/players.json + puzzles.json yet'));
}

for (const sport of sports) {
  test(`data/${sport}: puzzles validate`, () => {
    const playersJson = JSON.parse(fs.readFileSync(path.join(DATA, sport, 'players.json'), 'utf8'));
    const puzzlesJson = JSON.parse(fs.readFileSync(path.join(DATA, sport, 'puzzles.json'), 'utf8'));

    const t0 = process.hrtime.bigint();
    const idx = H.buildIndex(playersJson);
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    console.log(`# ${sport}: buildIndex ${ms.toFixed(0)} ms for ${idx.n} players, ${idx.tsKeys.length} team-seasons`);
    assert.equal(idx.sport, playersJson.sport || null);
    if (playersJson.sport) assert.equal(playersJson.sport, sport);
    assert.ok(ms < 1000, `buildIndex too slow: ${ms}ms`);

    const t1 = process.hrtime.bigint();
    let legacyCount = 0;
    puzzlesJson.puzzles.forEach((p, i) => {
      const ctx = `${sport} puzzle #${p.n}`;
      assert.equal(p.n, i + 1, `${ctx}: n === i + 1`);
      assert.equal(H.puzzleNumberForDate(puzzlesJson, p.date), p.n, `${ctx}: date matches epoch + n - 1`);
      // New format: best = fewest links, par = best + 1, the stored chain is an optimal one (best + 1 players).
      // Old-format data (no `best`, par = fewest links) is tolerated: the new assertions are skipped, loudly.
      const hasBest = p.best !== undefined;
      if (!hasBest) legacyCount++;
      const best = hasBest ? p.best : p.par;
      if (hasBest) {
        assert.equal(p.par, p.best + 1, `${ctx}: par === best + 1`);
        assert.ok(p.best >= 2, `${ctx}: best >= 2`);
      }
      // Modes: the stored par is the easy par; hard is one more. Both come from parFor.
      assert.equal(H.parFor(p, 'easy'), best + 1, `${ctx}: easy par`);
      assert.equal(H.parFor(p, 'hard'), best + 2, `${ctx}: hard par`);
      if (hasBest) assert.equal(H.parFor(p, 'easy'), p.par, `${ctx}: stored par is the easy par`);
      assert.equal(H.newGame(p).par, best + 2, `${ctx}: newGame defaults to hard`);
      assert.equal(H.score({ ...H.newGame(p), chain: p.chain, status: 'won' }).label, 'Eagle', `${ctx}: the stored chain is an Eagle in hard`);
      assert.equal(H.score({ ...H.newGame(p, { mode: 'easy' }), chain: p.chain, status: 'won' }).label, 'Birdie', `${ctx}: and a Birdie in easy`);
      assert.equal(p.chain.length, best + 1, `${ctx}: chain has best + 1 players`);
      assert.equal(p.chain[0], p.start, `${ctx}: chain starts at start`);
      assert.equal(p.chain[best], p.end, `${ctx}: chain ends at end`);
      const v = H.validateChain(idx, p.chain);
      assert.ok(v.ok, `${ctx}: chain invalid ${JSON.stringify(v)}`);
      assert.equal(p.links.length, best, `${ctx}: links length`);
      p.links.forEach(([team, season], k) => {
        const sh = H.sharedTeams(idx, p.chain[k], p.chain[k + 1]);
        assert.ok(sh.some((x) => x.team === team && x.season === season), `${ctx}: link ${k} ${team} ${season} not shared`);
      });
      const sp = H.shortestPath(idx, p.start, p.end);
      assert.ok(sp, `${ctx}: no path`);
      assert.equal(sp.dist, best, `${ctx}: best equals shortest distance`);
      if (p.optimal !== undefined) assert.equal(sp.count, p.optimal, `${ctx}: optimal count`);
    });
    if (legacyCount) {
      console.log(`# ${sport}: SKIPPED best/par assertions for ${legacyCount} of ${puzzlesJson.puzzles.length} puzzles: old data format without "best" (expected best === shortestPath dist, par === best + 1, best >= 2). Rebuild data with tools/build_data.py.`);
    }
    console.log(`# ${sport}: validated ${puzzlesJson.puzzles.length} puzzles in ${(Number(process.hrtime.bigint() - t1) / 1e6).toFixed(0)} ms`);
  });
}
