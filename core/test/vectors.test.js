'use strict';
// Runs the language-neutral vectors in vectors.json against the JS core (a Swift port runs the same file).
const test = require('node:test');
const assert = require('node:assert/strict');
const H = require('../handoff-core.js');
const V = require('./vectors.json');
const PLAYERS = require('./fixture-players.json');
const PUZZLES = require('./fixture-puzzles.json');
const idx = H.buildIndex(PLAYERS);
const pairs = (arr) => arr.map((x) => [x.team, x.season]);

test('vectors: normalize', () => { for (const v of V.normalize) assert.equal(H.normalize(v.in), v.out, JSON.stringify(v.in)); });

test('vectors: parseStints', () => { for (const v of V.parseStints) assert.deepEqual(pairs(H.parseStints(v.in)), v.out, v.in); });

test('vectors: sharedTeams', () => { for (const v of V.sharedTeams) assert.deepEqual(pairs(H.sharedTeams(idx, v.a, v.b)), v.out); });

test('vectors: shortestPath', () => {
  for (const v of V.shortestPath) {
    const r = H.shortestPath(idx, v.a, v.b);
    if (v.dist === null) { assert.equal(r, null); continue; }
    assert.equal(r.dist, v.dist, `${v.a}->${v.b}`);
    assert.equal(r.count, v.count, `${v.a}->${v.b}`);
    assert.deepEqual(r.path, v.path, `${v.a}->${v.b}`);
    assert.equal(r.links.length, v.dist);
  }
});

test('vectors: search', () => {
  for (const v of V.search) {
    const out = H.search(idx, v.query, { limit: v.limit, exclude: v.exclude }).map((p) => p.name);
    assert.deepEqual(out, v.out, v.query);
  }
});

test('vectors: score', () => {
  for (const v of V.score) assert.deepEqual(H.score({ chain: new Array(v.links + 1).fill('x'), par: v.par, best: v.best, status: v.status }), v.out);
});

test('vectors: shareText', () => {
  for (const v of V.shareText) assert.equal(H.shareText(v.puzzle, v.state, v.opts), v.out);
});

test('vectors: puzzleNumberForDate', () => {
  for (const v of V.puzzleNumberForDate) assert.equal(H.puzzleNumberForDate({ epoch: v.epoch }, v.ymd), v.n, v.ymd);
});

test('vectors: easternDate', () => {
  for (const v of V.easternDate) {
    assert.equal(H.easternDate(new Date(v.utc)), v.out, v.utc);
    assert.equal(H._easternDateFallback(new Date(v.utc)), v.out, v.utc);
  }
});

test('vectors: scripted games', () => {
  for (const g of V.game) {
    let p = PUZZLES.puzzles[g.puzzle - 1];
    if (g.legacy) { p = { ...p, par: p.best }; delete p.best; } // old data: no best, par = best
    let s = H.newGame(p);
    const got = [];
    for (const m of g.moves) {
      if (m[0] === 'g') { const r = H.guess(idx, s, m[1]); s = r.state; got.push(r.result.kind === 'rejected' ? 'rejected:' + r.result.reason : r.result.kind); }
      else if (m[0] === 'u') { s = H.undo(s); got.push('undo'); }
      else { const r = H.hint(idx, s); s = r.state; got.push(r.error ? 'error:' + r.error : `hint:${r.hint.team}:${r.hint.season}:${r.hint.pos}`); }
    }
    assert.deepEqual(got, g.results, g.name);
    const e = g.expect;
    assert.deepEqual({ chain: s.chain, downs: s.downs, inc: s.inc, hints: s.hints, status: s.status, log: s.log }, 
      { chain: e.chain, downs: e.downs, inc: e.inc, hints: e.hints, status: e.status, log: e.log }, g.name);
    if (e.score) assert.deepEqual(H.score(s), e.score, g.name); // only checked for finished games
    else assert.equal(s.status, 'playing', g.name + ': finished games need a score');
  }
});

test('vectors: stats', () => {
  for (const sv of V.stats) {
    let st = H.newStats();
    for (const r of sv.records) {
      const state = { chain: new Array(r.links + 1).fill('x'), par: r.par, best: r.best, status: r.won ? 'won' : 'lost', inc: r.inc, hints: r.hints };
      st = H.recordResult(st, r.n, state);
    }
    const f = sv.final;
    assert.deepEqual({ ...st, results: undefined }, { v: 1, ...f, results: undefined }, sv.name);
    for (const d of sv.display) assert.deepEqual(H.displayStreaks(st, d.today), d.out, sv.name + ' @' + d.today);
  }
});
