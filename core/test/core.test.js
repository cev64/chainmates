'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const H = require('../handoff-core.js');
const PLAYERS = require('./fixture-players.json');
const PUZZLES = require('./fixture-puzzles.json');

const idx = H.buildIndex(PLAYERS);
const P1 = PUZZLES.puzzles[0]; // T001 -> T003, best 3 / par 4, two optimal sequences
const P2 = PUZZLES.puzzles[1]; // T001 -> T009, best 3 / par 4, via a mid-season trade
const P3 = PUZZLES.puzzles[2]; // T004 -> T003, best 2 / par 3
// The same puzzles as older data had them: no `best`, par = best.
const legacy = (p) => { const q = { ...p, par: p.best }; delete q.best; return q; };
const LEGACY1 = legacy(P1), LEGACY3 = legacy(P3);
const names = (arr) => arr.map((p) => p.name);

function deepFreeze(o) {
  if (o && typeof o === 'object' && !Object.isFrozen(o)) { Object.freeze(o); Object.values(o).forEach(deepFreeze); }
  return o;
}
const easy = (p, o) => H.newGame(p, { ...o, mode: 'easy' });
const hard = (p, o) => H.newGame(p, { ...o, mode: 'hard' });
// Plays moves from a fresh game in `mode` ('easy' by default: the original par = best + 1). 'legacy' starts from a state
// saved before modes existed: no `mode`, par = best + 1 as stored then.
function start(puzzle, mode) {
  if (mode !== 'legacy') return H.newGame(puzzle, { mode });
  const s = easy(puzzle);
  delete s.mode;
  return s;
}
function play(puzzle, moves, mode = 'easy') {
  let s = start(puzzle, mode);
  for (const m of moves) {
    if (m === 'u') s = H.undo(s);
    else if (m === 'h') s = H.hint(idx, s).state;
    else s = H.guess(idx, s, m).state;
  }
  return s;
}

test('DOWNS and index basics', () => {
  assert.equal(H.DOWNS, 3);
  assert.equal(idx.sport, 'nfl');
  assert.equal(H.player(idx, 'nope'), null);
  const p = H.player(idx, 'T001');
  assert.deepEqual([p.id, p.name, p.pos, p.fame, p.first, p.last], ['T001', 'Peyton Marlow', 'QB', 990, 2002, 2015]);
  assert.equal(p.stints.length, 9 + 4);
});

test('parseStints: ranges, singles, trades', () => {
  assert.deepEqual(H.parseStints('DEN:2012-2014;IND:2010'), [
    { team: 'DEN', season: 2012 }, { team: 'DEN', season: 2013 }, { team: 'DEN', season: 2014 }, { team: 'IND', season: 2010 }]);
  assert.deepEqual(H.parseStints('NYJ:2010;MIN:2010;NE:2010'), [
    { team: 'NYJ', season: 2010 }, { team: 'MIN', season: 2010 }, { team: 'NE', season: 2010 }]);
  assert.deepEqual(H.parseStints('OAK:2019;LV:2020-2021').map((s) => s.team + s.season), ['OAK2019', 'LV2020', 'LV2021']);
  assert.deepEqual(H.parseStints(''), []);
});

test('teamLabel / teamFullName honour season name overrides', () => {
  assert.equal(H.teamLabel(idx, 'DEN', 2015), '2015 Broncos');
  assert.equal(H.teamLabel(idx, 'OAK', 2018), '2018 Raiders');
  assert.equal(H.teamLabel(idx, 'WAS', 2010), '2010 Washington');
  assert.equal(H.teamLabel(idx, 'WAS', 2020), '2020 Football Team');
  assert.equal(H.teamLabel(idx, 'WAS', 2023), '2023 Commanders');
  assert.equal(H.teamFullName(idx, 'DEN', 2015), 'Denver Broncos');
  assert.equal(H.teamFullName(idx, 'LV', 2021), 'Las Vegas Raiders');
  assert.equal(H.teamFullName(idx, 'WAS', 2023), 'Washington Commanders');
  assert.equal(H.teamFullName(idx, 'WAS', 2010), 'Washington');
  assert.equal(H.teamLabel(idx, 'XXX', 2010), '2010 XXX');
});

test('sharedTeams / areTeammates', () => {
  assert.deepEqual(H.sharedTeams(idx, 'T001', 'T004'), [{ team: 'DEN', season: 2015 }, { team: 'DEN', season: 2014 }]);
  assert.deepEqual(H.sharedTeams(idx, 'T004', 'T001'), H.sharedTeams(idx, 'T001', 'T004'));
  // mid-season trade: both NYJ 2010 and MIN 2010 exist for Brandt
  assert.deepEqual(H.sharedTeams(idx, 'T002', 'T005'), [{ team: 'NYJ', season: 2010 }]);
  assert.deepEqual(H.sharedTeams(idx, 'T002', 'T009'), [{ team: 'MIN', season: 2010 }]);
  assert.deepEqual(H.sharedTeams(idx, 'T012', 'T002'), [{ team: 'NYJ', season: 2010 }]);
  // OAK 2019 vs LV 2020 are different clubs/seasons: never teammates across the move
  assert.equal(H.areTeammates(idx, 'T004', 'T003'), false);
  assert.equal(H.areTeammates(idx, 'T007', 'T003'), true);
  // sorted season desc then team
  assert.deepEqual(H.sharedTeams(idx, 'T007', 'T003').map((x) => x.season), [2021, 2020]);
  assert.deepEqual(H.sharedTeams(idx, 'T001', 'T017'), []);
  assert.equal(H.areTeammates(idx, 'T001', 'T001'), false);
  assert.equal(H.areTeammates(idx, 'T001', 'nope'), false);
  // same abbreviation but different season is not a link
  assert.equal(H.areTeammates(idx, 'T013', 'T018'), false);
});

test('shortestPath: dist, path, links, count', () => {
  const r = H.shortestPath(idx, 'T001', 'T003');
  assert.equal(r.dist, 3);
  assert.equal(r.count, 2); // via T004 or T006
  assert.deepEqual(r.path, ['T001', 'T004', 'T007', 'T003']); // deterministic: lowest index (most famous) first
  assert.deepEqual(r.links, [{ team: 'DEN', season: 2015 }, { team: 'OAK', season: 2017 }, { team: 'LV', season: 2021 }]);
  assert.deepEqual(H.shortestPath(idx, 'T001', 'T003'), r); // deterministic
});

test('shortestPath: players sharing two team-seasons are one edge', () => {
  // T001 and T004 share DEN 2014 and DEN 2015, T001 and T006 share DEN 2013 only: 2 sequences, not 3
  assert.equal(H.shortestPath(idx, 'T001', 'T003').count, 2);
  const direct = H.shortestPath(idx, 'T001', 'T004');
  assert.equal(direct.dist, 1);
  assert.equal(direct.count, 1);
  // T001 and T016 share DEN 2012 and DEN 2013
  assert.deepEqual([H.shortestPath(idx, 'T001', 'T015').dist, H.shortestPath(idx, 'T001', 'T015').count], [1, 1]);
});

test('shortestPath: trade path, unique path, self, unreachable, unknown', () => {
  const r = H.shortestPath(idx, 'T001', 'T009');
  assert.deepEqual([r.dist, r.count], [3, 1]);
  assert.deepEqual(r.path, ['T001', 'T005', 'T002', 'T009']);
  assert.deepEqual(r.links, [{ team: 'IND', season: 2010 }, { team: 'NYJ', season: 2010 }, { team: 'MIN', season: 2010 }]);
  assert.deepEqual(H.shortestPath(idx, 'T004', 'T003'), {
    dist: 2, path: ['T004', 'T007', 'T003'], count: 1,
    links: [{ team: 'OAK', season: 2017 }, { team: 'LV', season: 2021 }] });
  assert.deepEqual(H.shortestPath(idx, 'T001', 'T001'), { dist: 0, path: ['T001'], links: [], count: 1 });
  assert.equal(H.shortestPath(idx, 'T001', 'T017'), null);
  assert.equal(H.shortestPath(idx, 'T001', 'nope'), null);
  // longer chain still counts correctly
  const far = H.shortestPath(idx, 'T012', 'T008');
  assert.deepEqual([far.dist, far.count], [6, 2]);
});

test('validateChain', () => {
  const ok = H.validateChain(idx, P1.chain);
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.links, [{ team: 'DEN', season: 2015 }, { team: 'OAK', season: 2017 }, { team: 'LV', season: 2021 }]);
  assert.deepEqual(H.validateChain(idx, ['T001', 'T003']), { ok: false, at: 1, reason: 'not-teammates' });
  assert.deepEqual(H.validateChain(idx, ['T001', 'T004', 'T001']), { ok: false, at: 2, reason: 'duplicate' });
  assert.deepEqual(H.validateChain(idx, ['T001', 'zzz']), { ok: false, at: 1, reason: 'unknown' });
  assert.equal(H.validateChain(idx, ['T001']).ok, false);
});

test('normalize', () => {
  assert.equal(H.normalize("Ja'Marr Pierce"), 'jamarr pierce');
  assert.equal(H.normalize('Ja’Marr'), 'jamarr');
  assert.equal(H.normalize('Sébastien Lamont'), 'sebastien lamont');
  assert.equal(H.normalize('Amon-Ra  St. Brown'), 'amon ra st brown');
  assert.equal(H.normalize('D.J. Rader'), 'dj rader');
  assert.equal(H.normalize('José Muñoz'), 'jose munoz');
  assert.equal(H.normalize('  '), '');
});

test('search: ranking, accents, exclude, limit', () => {
  // rank 0 full-name prefix, 1 word prefix, 2 substring, fame desc inside a rank
  assert.deepEqual(names(H.search(idx, 'mar')), ['Marcus Dell', 'Peyton Marlow', "Ja'Marr Pierce", 'Demarcus Hale']);
  assert.deepEqual(names(H.search(idx, 'tom')), ['Tom Brandt', 'Tommy Brandt Jr.']);
  assert.deepEqual(names(H.search(idx, 'brandt')), ['Tom Brandt', 'Tommy Brandt Jr.']);
  assert.deepEqual(names(H.search(idx, 'brandt tom')), ['Tom Brandt', 'Tommy Brandt Jr.']); // tokens each prefix a word
  assert.deepEqual(names(H.search(idx, "ja'marr")), ["Ja'Marr Pierce"]);
  assert.deepEqual(names(H.search(idx, 'jamarr')), ["Ja'Marr Pierce"]);
  // a space where the name has an apostrophe (or none where it has a space) still matches
  assert.deepEqual(names(H.search(idx, 'ja marr')), ["Ja'Marr Pierce"]);
  assert.deepEqual(names(H.search(idx, 'ricky o neal')), ["Ricky O'Neal"]);
  assert.deepEqual(names(H.search(idx, 'amonra')), ['Amon-Ra Stone']);
  assert.deepEqual(names(H.search(idx, 'sebastien')), ['Sébastien Lamont']);
  assert.deepEqual(names(H.search(idx, 'Sébast')), ['Sébastien Lamont']);
  assert.deepEqual(names(H.search(idx, 'munoz')), ['José Muñoz']);
  assert.deepEqual(names(H.search(idx, 'dj')), ['D.J. Rader']);
  assert.deepEqual(names(H.search(idx, 'amon ra')), ['Amon-Ra Stone']);
  assert.deepEqual(names(H.search(idx, 'mar', { exclude: ['T006'] })), ['Peyton Marlow', "Ja'Marr Pierce", 'Demarcus Hale']);
  assert.equal(H.search(idx, 'e', { limit: 3 }).length, 3);
  assert.equal(H.search(idx, 'e').length, 8);
  assert.deepEqual(H.search(idx, ''), []);
  assert.deepEqual(H.search(idx, 'zzzz'), []);
  // word-prefix match, most famous first
  assert.equal(H.search(idx, 'br')[0].name, 'Tom Brandt'); // word prefix, fame 940 beats Tommy (500)
});

test('easternDate: Intl path vs fallback across boundaries', () => {
  const cases = [
    // midnight Eastern rollover in EDT (UTC-4)
    ['2026-10-16T03:59:59Z', '2026-10-15'], ['2026-10-16T04:00:00Z', '2026-10-16'],
    // DST ends 2026-11-01 06:00Z (2:00 EDT -> 1:00 EST)
    ['2026-11-01T03:59:59Z', '2026-10-31'], ['2026-11-01T04:00:00Z', '2026-11-01'],
    ['2026-11-01T05:59:59Z', '2026-11-01'], ['2026-11-01T06:00:00Z', '2026-11-01'],
    // midnight rollover in EST (UTC-5)
    ['2026-11-02T04:59:59Z', '2026-11-01'], ['2026-11-02T05:00:00Z', '2026-11-02'],
    // DST starts 2026-03-08 07:00Z (2:00 EST -> 3:00 EDT)
    ['2026-03-08T04:59:59Z', '2026-03-07'], ['2026-03-08T05:00:00Z', '2026-03-08'],
    ['2026-03-08T06:59:59Z', '2026-03-08'], ['2026-03-08T07:00:00Z', '2026-03-08'],
    ['2026-03-09T03:59:59Z', '2026-03-08'], ['2026-03-09T04:00:00Z', '2026-03-09'],
    // new year, summer, 2027 / 2028 transitions
    ['2027-01-01T04:59:59Z', '2026-12-31'], ['2027-01-01T05:00:00Z', '2027-01-01'],
    ['2027-03-14T06:59:59Z', '2027-03-14'], ['2028-03-12T04:59:59Z', '2028-03-11'], ['2028-03-12T05:00:00Z', '2028-03-12'],
    ['2027-11-07T03:59:59Z', '2027-11-06'], ['2027-11-07T04:00:00Z', '2027-11-07'],
    ['2026-07-04T03:59:59Z', '2026-07-03'], ['2026-07-04T04:00:00Z', '2026-07-04'],
  ];
  for (const [iso, want] of cases) {
    assert.equal(H.easternDate(new Date(iso)), want, 'Intl ' + iso);
    assert.equal(H._easternDateFallback(new Date(iso)), want, 'fallback ' + iso);
  }
  assert.match(H.easternDate(), /^\d{4}-\d\d-\d\d$/);
});

test('easternDate: fallback agrees with Intl on a sweep of 2024-2030', () => {
  const start = Date.UTC(2024, 0, 1), end = Date.UTC(2030, 11, 31);
  for (let t = start; t < end; t += 3 * 3600 * 1000 + 17 * 60000) {
    const d = new Date(t);
    assert.equal(H._easternDateFallback(d), H.easternDate(d), d.toISOString());
  }
});

test('puzzleNumberForDate / puzzleForDate / puzzleByNumber', () => {
  assert.equal(H.puzzleNumberForDate(PUZZLES, '2026-10-12'), 1);
  assert.equal(H.puzzleNumberForDate(PUZZLES, '2026-10-14'), 3);
  assert.equal(H.puzzleNumberForDate(PUZZLES, '2026-10-11'), 0);
  assert.equal(H.puzzleNumberForDate(PUZZLES, '2026-12-01'), 51); // spans the DST change
  assert.equal(H.puzzleNumberForDate(PUZZLES, '2027-10-12'), 366);
  assert.equal(H.puzzleForDate(PUZZLES, '2026-10-13').n, 2);
  assert.equal(H.puzzleForDate(PUZZLES, '2026-10-11'), null);
  assert.equal(H.puzzleForDate(PUZZLES, '2026-10-15'), null);
  assert.equal(H.puzzleByNumber(PUZZLES, 3).kind, 'wed');
  assert.equal(H.puzzleByNumber(PUZZLES, 0), null);
  assert.equal(H.puzzleByNumber(PUZZLES, 4), null);
  assert.equal(H.puzzleByNumber(PUZZLES, 1.5), null);
  // DST rollover moment maps to the Eastern date
  assert.equal(H.puzzleNumberForDate(PUZZLES, H.easternDate(new Date('2026-10-13T03:59:59Z'))), 1);
  assert.equal(H.puzzleNumberForDate(PUZZLES, H.easternDate(new Date('2026-10-13T04:00:00Z'))), 2);
});

test('fixture puzzles: best is the shortest distance, par = best + 1, stored chain has best + 1 players', () => {
  for (const p of PUZZLES.puzzles) {
    assert.equal(p.best, H.shortestPath(idx, p.start, p.end).dist, `#${p.n} best`);
    assert.equal(p.par, p.best + 1, `#${p.n} par`);
    assert.equal(p.chain.length, p.best + 1, `#${p.n} chain`);
    assert.equal(p.links.length, p.best, `#${p.n} links`);
    assert.equal(H.validateChain(idx, p.chain).ok, true);
  }
  assert.deepEqual(PUZZLES.puzzles.map((p) => [p.best, p.par]), [[3, 4], [3, 4], [2, 3]]);
});

test('modes: MODES, DEFAULT_MODE, parFor', () => {
  assert.deepEqual(H.MODES, { hard: { parOffset: 2 }, easy: { parOffset: 1 } });
  assert.equal(H.DEFAULT_MODE, 'hard');
  assert.equal(H.parFor(P1, 'hard'), 5);
  assert.equal(H.parFor(P1, 'easy'), 4);
  assert.equal(H.parFor(P3, 'hard'), 4);
  assert.equal(H.parFor(P3, 'easy'), 3);
  // puzzles.json keeps par = easy par; parFor reads best
  for (const p of PUZZLES.puzzles) assert.equal(H.parFor(p, 'easy'), p.par);
  // an unknown or missing mode means hard
  assert.equal(H.parFor(P1, 'nightmare'), 5);
  assert.equal(H.parFor(P1), 5);
  assert.equal(H.parFor(P1, 'toString'), 5);
  // no `best` (older data): best = par
  assert.equal(H.parFor(LEGACY1, 'easy'), 4);
  assert.equal(H.parFor(LEGACY1, 'hard'), 5);
  // best wins over par when both exist
  assert.equal(H.parFor({ best: 2, par: 9 }, 'hard'), 4);
});

test('game: newGame shape, copies best, hard by default', () => {
  assert.deepEqual(H.newGame(P1), { n: 1, start: 'T001', end: 'T003', mode: 'hard', par: 5, best: 3, chain: ['T001'], downs: 3, inc: 0, hints: 0, hintAt: {}, status: 'playing', log: [] });
  assert.deepEqual(H.newGame(P1, { mode: 'hard' }), H.newGame(P1));
  assert.deepEqual(H.newGame(P1, { mode: 'easy' }), { n: 1, start: 'T001', end: 'T003', mode: 'easy', par: 4, best: 3, chain: ['T001'], downs: 3, inc: 0, hints: 0, hintAt: {}, status: 'playing', log: [] });
  assert.equal(H.newGame(P1, { downs: 5 }).downs, 5);
  assert.equal(H.newGame(P1, { downs: 0 }).downs, 3);
  assert.equal(H.newGame(P1, { downs: 5, mode: 'easy' }).downs, 5);
  assert.deepEqual([H.newGame(P3).par, H.newGame(P3).best], [4, 2]);
  assert.deepEqual([easy(P3).par, easy(P3).best], [3, 2]);
  // unknown mode -> hard; the state is never left without a mode
  assert.deepEqual([H.newGame(P1, { mode: 'zzz' }).mode, H.newGame(P1, { mode: 'zzz' }).par], ['hard', 5]);
  assert.equal(H.newGame(P1, {}).mode, 'hard');
  assert.equal(H.newGame(P1, { mode: undefined }).mode, 'hard');
});

test('game: newGame on older data without best falls back to best = par', () => {
  const g = easy(LEGACY1);
  assert.equal(g.best, 3);
  assert.equal(g.par, 4); // best + the easy offset; the stored par (3) was the best
  assert.equal(H.newGame(LEGACY1).par, 5);
  assert.deepEqual(easy(LEGACY3).best, 2);
  // a puzzle that has best is never overridden by par
  assert.equal(easy({ ...P1, best: 2, par: 3 }).best, 2);
  assert.equal(H.newGame({ ...P1, best: 2, par: 3 }).par, 4);
});

test('game: birdie (optimal chain) after one incompletion', () => {
  let r = H.guess(idx, easy(P1), 'T012');
  assert.equal(r.result.kind, 'incompletion');
  r = H.guess(idx, r.state, 'T004');
  assert.equal(r.result.kind, 'link');
  assert.deepEqual(r.result.links, [{ team: 'DEN', season: 2015 }, { team: 'DEN', season: 2014 }]);
  r = H.guess(idx, r.state, 'T007');
  assert.equal(r.result.kind, 'solved');
  assert.deepEqual(r.result.links, [{ team: 'OAK', season: 2017 }]);
  assert.deepEqual(r.result.final, [{ team: 'LV', season: 2021 }, { team: 'LV', season: 2020 }]);
  assert.equal(r.state.status, 'won');
  assert.deepEqual(r.state.chain, ['T001', 'T004', 'T007', 'T003']);
  assert.deepEqual(H.score(r.state), { links: 3, par: 4, best: 3, over: -1, label: 'Birdie', won: true, mode: 'easy' });
  assert.deepEqual(r.state.log, [{ t: 'g', id: 'T012', ok: false }, { t: 'g', id: 'T004', ok: true }, { t: 'g', id: 'T007', ok: true }]);
  assert.equal(JSON.stringify(JSON.parse(JSON.stringify(r.state))), JSON.stringify(r.state));
  // the other optimal route (via the tight end) is a birdie too
  assert.equal(H.score(play(P1, ['T006', 'T007'])).label, 'Birdie');
  // and so is the two-link puzzle
  assert.deepEqual(H.score(play(P3, ['T007'])), { links: 2, par: 3, best: 2, over: -1, label: 'Birdie', won: true, mode: 'easy' });
});

test('game: par win (one link past best)', () => {
  const s = play(P1, ['T004', 'T006', 'T007']);
  assert.equal(s.status, 'won');
  assert.deepEqual(s.chain, ['T001', 'T004', 'T006', 'T007', 'T003']);
  assert.deepEqual(H.score(s), { links: 4, par: 4, best: 3, over: 0, label: 'Par', won: true, mode: 'easy' });
  // undo then re-route to the optimal chain: birdie
  const u = play(P1, ['T004', 'T006', 'u', 'u', 'T006', 'T007']);
  assert.deepEqual(u.chain, ['T001', 'T006', 'T007', 'T003']);
  assert.equal(H.score(u).label, 'Birdie');
  // a detour of two extra links is +1
  const plus1 = play(P1, ['T015', 'T006', 'T004', 'T007']);
  assert.deepEqual(plus1.chain, ['T001', 'T015', 'T006', 'T004', 'T007', 'T003']);
  assert.deepEqual(H.score(plus1), { links: 5, par: 4, best: 3, over: 1, label: '+1', won: true, mode: 'easy' });
  // P3 par win: three links
  assert.deepEqual(H.score(play(P3, ['T006', 'T007'])), { links: 3, par: 3, best: 2, over: 0, label: 'Par', won: true, mode: 'easy' });
});

test('game: scoring does not depend on incompletions or hints', () => {
  const s = play(P1, ['T012', 'h', 'T004', 'T007']); // 1 incompletion + 1 hint, still the optimal chain
  assert.equal(s.inc, 1);
  assert.equal(s.hints, 1);
  assert.equal(H.score(s).label, 'Birdie');
});

test('game: incompletion, then loss after 3 incompletions', () => {
  let r = H.guess(idx, easy(P1), 'T012');
  assert.deepEqual(r.result, { kind: 'incompletion', downsLeft: 2 });
  assert.equal(r.state.inc, 1);
  assert.deepEqual(r.state.chain, ['T001']);
  r = H.guess(idx, r.state, 'T017');
  assert.deepEqual(r.result, { kind: 'incompletion', downsLeft: 1 });
  r = H.guess(idx, r.state, 'T010');
  assert.equal(r.result.kind, 'lost');
  assert.equal(r.state.status, 'lost');
  assert.equal(r.state.downs, 0);
  assert.equal(r.state.inc, 3);
  const sc = H.score(r.state);
  assert.deepEqual([sc.links, sc.par, sc.best, sc.label, sc.won], [0, 4, 3, 'X', false]);
  assert.deepEqual(r.state.log.map((l) => l.ok), [false, false, false]);
  // a loss after some progress is still X, never a birdie
  const late = play(P1, ['T004', 'T012', 'T017', 'T010']);
  assert.equal(late.status, 'lost');
  assert.equal(H.score(late).label, 'X');
});

test('game: rejected guesses cost nothing', () => {
  let s = play(P1, ['T004']);
  const before = JSON.stringify(s);
  const cases = [['nope', 'unknown'], ['T001', 'start'], ['T004', 'in-chain'], ['T003', 'end']];
  for (const [id, reason] of cases) {
    const r = H.guess(idx, s, id);
    assert.deepEqual(r.result, { kind: 'rejected', reason });
    assert.equal(JSON.stringify(r.state), before);
  }
});

test('game: no moves after game over', () => {
  const won = play(P1, ['T004', 'T007']);
  assert.deepEqual(H.guess(idx, won, 'T006').result, { kind: 'rejected', reason: 'over' });
  assert.deepEqual(H.undo(won), won);
  assert.equal(H.hint(idx, won).error, 'over');
  const lost = play(P1, ['T012', 'T017', 'T010']);
  assert.deepEqual(H.guess(idx, lost, 'T004').result, { kind: 'rejected', reason: 'over' });
  assert.deepEqual(H.undo(lost), lost);
  assert.equal(H.hint(idx, lost).error, 'over');
});

test('game: undo is a free no-op at the start', () => {
  const s = easy(P1);
  assert.deepEqual(H.undo(s), s);
  const g = play(P1, ['T004', 'u']);
  assert.deepEqual(g.chain, ['T001']);
  assert.equal(g.downs, 3);
  assert.deepEqual(g.log, [{ t: 'g', id: 'T004', ok: true }, { t: 'u' }]);
});

test('hint: reveals team, season and the position of the next player on the shortest path', () => {
  let r = H.hint(idx, easy(P1));
  // two optimal first steps exist: T004 (WR, fame 800) and T006 (TE, fame 700). The famous one wins.
  assert.equal(H.player(idx, 'T004').pos, 'WR');
  assert.equal(H.player(idx, 'T006').pos, 'TE');
  assert.equal(H.shortestPath(idx, 'T001', 'T003').path[1], 'T004');
  assert.deepEqual(r.hint, { team: 'DEN', season: 2015, pos: 'WR' });
  assert.equal(r.hint.pos, H.player(idx, H.shortestPath(idx, 'T001', 'T003').path[1]).pos);
  assert.equal(r.state.downs, 2);
  assert.equal(r.state.hints, 1);
  assert.deepEqual(r.state.hintAt, { T001: { team: 'DEN', season: 2015, pos: 'WR' } });
  // the log entry keeps team and season only: no position, never a name
  assert.deepEqual(r.state.log, [{ t: 'h', team: 'DEN', season: 2015 }]);
  assert.equal(Object.keys(r.hint).sort().join(), 'pos,season,team');
  assert.doesNotMatch(JSON.stringify(r.hint), /Tolliver|T004/);
});

test('hint: pos follows the current position (every step of the shortest path)', () => {
  // P1: after T004 the next player on the way is T007 (RB), via OAK 2017
  const at4 = play(P1, ['T004']);
  assert.deepEqual(H.hint(idx, at4).hint, { team: 'OAK', season: 2017, pos: 'RB' });
  // off the stored chain: from T006 (TE) the next player is also T007 (RB)
  assert.deepEqual(H.hint(idx, play(P1, ['T006'])).hint, { team: 'OAK', season: 2017, pos: 'RB' });
  // off the optimal route entirely: T015 (G) -> T006 -> T007, so the next player is T006 (TE) via DEN 2013
  const at15 = play(P1, ['T015']);
  assert.deepEqual(H.shortestPath(idx, 'T015', 'T003').path, ['T015', 'T006', 'T007', 'T003']);
  assert.deepEqual(H.hint(idx, at15).hint, { team: 'DEN', season: 2013, pos: 'TE' });
  // P2 through the trade: T005 (K) then T002 (QB)
  assert.deepEqual(H.hint(idx, easy(P2)).hint, { team: 'IND', season: 2010, pos: 'K' });
  assert.deepEqual(H.hint(idx, play(P2, ['T005'])).hint, { team: 'NYJ', season: 2010, pos: 'QB' });
  // P3
  assert.deepEqual(H.hint(idx, easy(P3)).hint, { team: 'OAK', season: 2017, pos: 'RB' });
  // for every position on the stored chains the hint is the next stored player's position (single optimal route puzzles)
  for (const p of [P2, P3]) {
    for (let i = 0; i < p.chain.length - 2; i++) {
      const s = play(p, p.chain.slice(1, i + 1));
      assert.equal(H.hint(idx, s).hint.pos, H.player(idx, p.chain[i + 1]).pos, `#${p.n} step ${i}`);
    }
  }
});

test('hint: costs a down, repeat is free and returns the same pos, follows the current position', () => {
  let r = H.hint(idx, easy(P1));
  const again = H.hint(idx, r.state);
  assert.deepEqual(again.hint, { team: 'DEN', season: 2015, pos: 'WR' });
  assert.equal(again.state.downs, 2);
  assert.equal(again.state.hints, 1);
  // move forward: new position, new hint
  const moved = H.guess(idx, r.state, 'T004').state;
  const h2 = H.hint(idx, moved);
  assert.deepEqual(h2.hint, { team: 'OAK', season: 2017, pos: 'RB' });
  assert.equal(h2.state.downs, 1);
  assert.equal(h2.state.hints, 2);
  assert.deepEqual(h2.state.log.filter((l) => l.t === 'h'), [{ t: 'h', team: 'DEN', season: 2015 }, { t: 'h', team: 'OAK', season: 2017 }]);
  assert.deepEqual(Object.keys(h2.state.hintAt).sort(), ['T001', 'T004']);
  // undo back to a hinted position: still free, still with pos
  const back = H.undo(moved);
  const free = H.hint(idx, back);
  assert.equal(free.state.downs, 2);
  assert.equal(free.hint.pos, 'WR');
  // hint is not a wrong guess
  assert.equal(r.state.inc, 0);
  // the returned hint is a copy: changing it can't corrupt the cache
  r.hint.pos = 'XX';
  assert.equal(H.hint(idx, r.state).hint.pos, 'WR');
});

test('hint: refused on the last down but a cached hint stays free', () => {
  const two = play(P1, ['T012', 'T017']);
  assert.equal(two.downs, 1);
  const r = H.hint(idx, two);
  assert.equal(r.error, 'last-down');
  assert.equal(r.hint, undefined);
  assert.equal(r.state.downs, 1);
  assert.equal(r.state.hints, 0);
  // hint (2 downs left), then an incompletion (1 down left): the cached hint is still readable
  const s = play(P1, ['h', 'T012']);
  assert.equal(s.downs, 1);
  assert.deepEqual(H.hint(idx, s).hint, { team: 'DEN', season: 2015, pos: 'WR' });
  // hint + 2 incompletions = lost, hints count toward downs
  const l = play(P1, ['h', 'T012', 'T017']);
  assert.equal(l.status, 'lost');
  assert.equal(l.hints, 1);
  assert.equal(l.inc, 2);
});

test('hint: works the same on older data without best, and tolerates a cached hint saved without pos', () => {
  assert.deepEqual(H.hint(idx, H.newGame(LEGACY3)).hint, { team: 'OAK', season: 2017, pos: 'RB' });
  const old = { ...easy(P1), hintAt: { T001: { team: 'DEN', season: 2015 } } }; // saved by an earlier version
  const r = H.hint(idx, old);
  assert.deepEqual(r.hint, { team: 'DEN', season: 2015 });
  assert.equal(r.state.downs, 3);
});

test('game: functions never mutate their inputs', () => {
  const s0 = deepFreeze(easy(P1));
  const s1 = deepFreeze(H.guess(idx, s0, 'T004').state);
  const s2 = deepFreeze(H.hint(idx, s1).state);
  deepFreeze(H.guess(idx, s2, 'T012').state);
  deepFreeze(H.guess(idx, s2, 'T003').state);
  deepFreeze(H.undo(s2));
  deepFreeze(H.hint(idx, s2).state);
  const done = deepFreeze(H.guess(idx, s1, 'T007').state);
  H.guess(idx, done, 'T006'); H.undo(done); H.hint(idx, done); H.score(done); H.shareText(P1, done);
  assert.deepEqual(s0.chain, ['T001']);
  assert.equal(s0.downs, 3);
  assert.notEqual(H.guess(idx, s0, 'T004').state, s0);
  assert.notEqual(H.undo(s0), s0);
  assert.equal(Object.isFrozen(deepFreeze(PUZZLES)), true); // puzzle data untouched by newGame
  H.newGame(PUZZLES.puzzles[0]);
});

test('score labels: golf names under par, +n over, X when lost', () => {
  const mk = (links, status, par, best) => ({ chain: new Array(links + 1).fill('x'), par, best, status });
  const sc = (links, par, best, status = 'won') => H.score(mk(links, status, par, best));
  // par = best + 1, as in real data
  assert.deepEqual(sc(3, 4, 3), { links: 3, par: 4, best: 3, over: -1, label: 'Birdie', won: true, mode: 'easy' });
  assert.deepEqual(sc(4, 4, 3), { links: 4, par: 4, best: 3, over: 0, label: 'Par', won: true, mode: 'easy' });
  assert.deepEqual(sc(5, 4, 3), { links: 5, par: 4, best: 3, over: 1, label: '+1', won: true, mode: 'easy' });
  assert.equal(sc(6, 4, 3).label, '+2');
  assert.equal(sc(7, 4, 3).label, '+3');
  assert.equal(sc(12, 4, 3).label, '+8');
  // wider gaps between par and best
  assert.deepEqual([sc(3, 5, 3).over, sc(3, 5, 3).label], [-2, 'Eagle']);
  assert.deepEqual([sc(3, 6, 3).over, sc(3, 6, 3).label], [-3, 'Albatross']);
  assert.deepEqual([sc(3, 7, 3).over, sc(3, 7, 3).label], [-4, '-4']);
  // shorter than best (a data refresh found a shorter path): over bottoms out at best - par
  assert.deepEqual([sc(2, 4, 3).links, sc(2, 4, 3).over, sc(2, 4, 3).label], [2, -1, 'Birdie']);
  assert.equal(sc(1, 5, 3).label, 'Eagle');
  // lost games are X, whatever the numbers say, and are not won
  assert.equal(sc(2, 4, 3, 'lost').label, 'X');
  assert.equal(sc(2, 4, 3, 'lost').won, false);
  assert.equal(sc(9, 4, 3, 'lost').label, 'X');
  // best is echoed
  assert.equal(sc(4, 4, 3).best, 3);
});

test('score labels: states without best (older data) use best = par', () => {
  const mk = (links, status, par = 3) => ({ chain: new Array(links + 1).fill('x'), par, status });
  assert.deepEqual(H.score(mk(3, 'won')), { links: 3, par: 3, best: 3, over: 0, label: 'Par', won: true, mode: 'easy' });
  assert.equal(H.score(mk(4, 'won')).label, '+1');
  assert.equal(H.score(mk(6, 'won')).label, '+3');
  assert.equal(H.score(mk(2, 'won')).label, 'Par'); // shorter than par: still no birdie
  assert.equal(H.score(mk(2, 'won')).over, 0);
  assert.equal(H.score(mk(2, 'lost')).label, 'X');
  assert.equal(H.score(mk(2, 'lost')).won, false);
  // a full game saved before modes existed: no mode (reads as easy), par = best + 1
  assert.deepEqual(H.score(play(P3, ['T007'], 'legacy')), { links: 2, par: 3, best: 2, over: -1, label: 'Birdie', won: true, mode: 'easy' });
  assert.deepEqual(H.score(play(P1, ['T004', 'T006', 'T007'], 'legacy')), { links: 4, par: 4, best: 3, over: 0, label: 'Par', won: true, mode: 'easy' });
});

test('shareText: birdie with 1 incompletion', () => {
  const s = play(P1, ['T012', 'T004', 'T007']);
  const text = H.shareText({ ...P1, n: 42 }, s);
  assert.equal(text, 'Chainmates #42 \u{1F3C8}\n\u{1F7E9}\u{1F7E9}\u{1F7E9} 3 links · Par 4 · Birdie \u{1F426}\n\u{1F7E5} 1 incompletion\ncev64.github.io/handoff/#42');
  assert.equal(text, 'Chainmates #42 🏈\n🟩🟩🟩 3 links · Par 4 · Birdie 🐦\n🟥 1 incompletion\ncev64.github.io/handoff/#42');
});

test('shareText: par win', () => {
  const s = play(P1, ['T004', 'T006', 'T007']);
  assert.equal(H.shareText(P1, s), 'Chainmates #1 🏈\n🟩🟩🟩🟩 4 links · Par 4 ⛳\ncev64.github.io/handoff/#1');
});

test('shareText: +1 win with a hint, +3 win', () => {
  const s = play(P1, ['T015', 'T006', 'T004', 'h', 'T007']);
  assert.equal(s.hints, 1);
  assert.equal(H.shareText(P1, s), 'Chainmates #1 🏈\n🟩🟩🟩🟩🟨 5 links · Par 4 (+1)\n💡 1 hint\ncev64.github.io/handoff/#1');
  // 7 links: four green squares (up to par), three yellow beyond it
  const far = { ...easy(P1), chain: ['T001', 'a', 'b', 'c', 'd', 'e', 'f', 'T003'], status: 'won', inc: 2 };
  assert.equal(H.shareText(P1, far), 'Chainmates #1 🏈\n🟩🟩🟩🟩🟨🟨🟨 7 links · Par 4 (+3)\n🟥 2 incompletions\ncev64.github.io/handoff/#1');
});

test('shareText: "link" is singular for one link, an Eagle-sized gap in an untagged (easy) state', () => {
  const eagle = { n: 5, best: 3, par: 4 };
  const es = { ...easy(eagle), par: 5, chain: ['a', 'b', 'c', 'd'], status: 'won' };
  assert.equal(H.shareText(eagle, es), 'Chainmates #5 🏈\n🟩🟩🟩 3 links · Par 5 · Eagle 🦅\ncev64.github.io/handoff/#5');
  const one = { n: 6, best: 1, par: 2 };
  const os = { ...easy(one), chain: ['a', 'b'], status: 'won' };
  assert.equal(H.shareText(one, os), 'Chainmates #6 🏈\n🟩 1 link · Par 2 · Birdie 🐦\ncev64.github.io/handoff/#6');
  assert.doesNotMatch(H.shareText(one, os), /1 links/);
  const onePar = { n: 7, best: 0, par: 1 };
  assert.match(H.shareText(onePar, { ...easy(onePar), par: 1, chain: ['a', 'b'], status: 'won' }), /🟩 1 link · Par 1 ⛳/u);
});

test('shareText: loss, plural lines, custom url/title/emoji', () => {
  const s = play(P1, ['h', 'h', 'T012', 'T017']); // hint (downs 2), repeat free, 2 incompletions -> lost
  assert.equal(s.status, 'lost');
  assert.equal(H.shareText(P1, s), 'Chainmates #1 🏈\n🏳️ Turnover on downs · Par 4\n🟥 2 incompletions\n💡 1 hint\ncev64.github.io/handoff/#1');
  const t = H.shareText(P1, s, { url: 'example.com/h/', title: 'Chainmates NBA', emoji: '🏀' });
  assert.equal(t, 'Chainmates NBA #1 🏀\n🏳️ Turnover on downs · Par 4\n🟥 2 incompletions\n💡 1 hint\nexample.com/h/#1');
  const clean = play(P1, ['T004', 'T007']);
  assert.equal(H.shareText(P1, clean), 'Chainmates #1 🏈\n🟩🟩🟩 3 links · Par 4 · Birdie 🐦\ncev64.github.io/handoff/#1');
  // never leaks names
  assert.doesNotMatch(H.shareText(P1, clean), /Marlow|Tolliver|Broncos|DEN/);
  const multi = play(P1, ['h', 'T004', 'h', 'T007']);
  assert.match(H.shareText(P1, multi), /\u{1F4A1} 2 hints/u);
  // a lost game shows no score label, whatever progress was made
  const late = play(P1, ['T004', 'T012', 'T017', 'T010']);
  assert.equal(H.shareText(P1, late), 'Chainmates #1 🏈\n🏳️ Turnover on downs · Par 4\n🟥 3 incompletions\ncev64.github.io/handoff/#1');
});

test('shareText: custom miss / lost words replace the football defaults', () => {
  const opts = { miss: 'strike', lost: 'Out of strikes' };
  const lost = play(P1, ['T012', 'T017', 'T010']);
  const lt = H.shareText(P1, lost, opts);
  assert.equal(lt, 'Chainmates #1 🏈\n🏳️ Out of strikes · Par 4\n🟥 3 strikes\ncev64.github.io/handoff/#1');
  assert.doesNotMatch(lt, /incompletion|Turnover|downs/);
  // singular and plural on a win
  const one = play(P1, ['T012', 'T004', 'T007']);
  assert.equal(H.shareText(P1, one, opts), 'Chainmates #1 🏈\n🟩🟩🟩 3 links · Par 4 · Birdie 🐦\n🟥 1 strike\ncev64.github.io/handoff/#1');
  const two = play(P1, ['T012', 'T017', 'T004', 'T007']);
  assert.match(H.shareText(P1, two, opts), /\n🟥 2 strikes\n/u);
  // zero misses: no line at all, and `lost` is unused on a win
  assert.doesNotMatch(H.shareText(P1, play(P1, ['T004', 'T007']), opts), /strike|Out of/);
  // only one of the two given: the other keeps its default
  assert.match(H.shareText(P1, lost, { miss: 'miss' }), /Turnover on downs · Par 4\n🟥 3 miss[^e]|Turnover on downs · Par 4\n🟥 3 miss/u);
  assert.match(H.shareText(P1, lost, { lost: 'Fouled out' }), /🏳️ Fouled out · Par 4\n🟥 3 incompletions/u);
  // empty strings fall back to the defaults
  assert.match(H.shareText(P1, lost, { miss: '', lost: '' }), /Turnover on downs · Par 4\n🟥 3 incompletions/u);
});

test('shareText: states saved before modes existed read as before (no tag, own par)', () => {
  const birdie = play(P3, ['T007'], 'legacy');
  assert.equal(birdie.mode, undefined);
  assert.equal(H.shareText({ ...P3, n: 3 }, birdie), 'Chainmates #3 🏈\n🟩🟩 2 links · Par 3 · Birdie 🐦\ncev64.github.io/handoff/#3');
  const over = play(P1, ['T004', 'T006', 'T007', 'T003'].slice(0, 3), 'legacy');
  assert.equal(H.shareText(P1, over), 'Chainmates #1 🏈\n🟩🟩🟩🟩 4 links · Par 4 ⛳\ncev64.github.io/handoff/#1');
  // a state with no par at all falls back to parFor(puzzle, mode); no mode on the state reads as easy
  const bare = { chain: ['a', 'b', 'c', 'd'], status: 'won', inc: 0, hints: 0 };
  assert.equal(H.shareText(P1, bare), 'Chainmates #1 🏈\n🟩🟩🟩 3 links · Par 4 · Birdie 🐦\ncev64.github.io/handoff/#1');
  assert.equal(H.shareText(P1, { ...bare, mode: 'hard' }), 'Chainmates #1 🏈 · Hard\n🟩🟩🟩 3 links · Par 5 · Eagle 🦅\ncev64.github.io/handoff/#1');
  assert.equal(H.shareText(P1, { ...bare, mode: 'easy' }), H.shareText(P1, bare));
  // the state's par wins over the puzzle's (puzzles.json par is the easy par)
  assert.match(H.shareText(P1, { ...bare, best: 3, par: 5, mode: 'hard' }), /Par 5 · Eagle/);
});

test('stats: newStats has the -2 and -1 buckets', () => {
  assert.deepEqual(H.newStats(), { v: 1, played: 0, won: 0, cur: 0, max: 0, parCur: 0, parMax: 0, last: 0, lastWon: 0, hist: { '-2': 0, '-1': 0, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 }, results: {} });
  assert.deepEqual(Object.keys(H.newStats().hist).sort(), ['-1', '-2', '0', '1', '2', '3', 'X']);
});

test('stats: consecutive win streak, gap resets, duplicate no-op, par-or-better streak', () => {
  const birdie = play(P1, ['T004', 'T007']);
  const par = play(P1, ['T004', 'T006', 'T007']);
  const over = play(P1, ['T015', 'T006', 'T004', 'T007']);
  const lost = play(P1, ['T012', 'T017', 'T010']);
  let st = H.newStats();

  const frozen = deepFreeze(H.newStats());
  st = H.recordResult(frozen, 10, birdie); // does not mutate
  assert.equal(frozen.played, 0);
  assert.equal(frozen.hist['-1'], 0);
  assert.equal(frozen.hist['-2'], 0);
  assert.deepEqual([st.played, st.won, st.cur, st.parCur, st.last, st.lastWon], [1, 1, 1, 1, 10, 10]);
  assert.deepEqual(st.results[10], { links: 3, par: 4, inc: 0, hints: 0, won: true, mode: 'easy' });
  assert.deepEqual(st.hist, { '-2': 0, '-1': 1, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 });

  st = H.recordResult(st, 11, par);
  assert.deepEqual([st.cur, st.max, st.parCur, st.parMax], [2, 2, 2, 2]);
  const dup = H.recordResult(st, 11, over);
  assert.deepEqual(dup, st);
  assert.equal(dup.played, 2);

  st = H.recordResult(st, 12, over); // win over par: cur continues, par streak resets
  assert.deepEqual([st.cur, st.max, st.parCur, st.parMax], [3, 3, 0, 2]);
  assert.deepEqual(st.hist, { '-2': 0, '-1': 1, 0: 1, 1: 1, 2: 0, 3: 0, X: 0 });

  st = H.recordResult(st, 14, birdie); // gap (13 missed): win streak restarts, par streak restarts
  assert.deepEqual([st.cur, st.max, st.parCur, st.parMax], [1, 3, 1, 2]);

  st = H.recordResult(st, 15, lost);
  assert.deepEqual([st.cur, st.max, st.parCur, st.played, st.won, st.last, st.lastWon], [0, 3, 0, 5, 4, 15, 14]);
  assert.equal(st.hist.X, 1);
  assert.deepEqual(st.results[15], { links: 0, par: 4, inc: 3, hints: 0, won: false, mode: 'easy' });

  st = H.recordResult(st, 16, par); // after a loss the streak starts over at 1
  assert.deepEqual([st.cur, st.parCur], [1, 1]);
  assert.deepEqual(st.hist, { '-2': 0, '-1': 2, 0: 2, 1: 1, 2: 0, 3: 0, X: 1 });

  // unfinished games are ignored
  assert.equal(H.recordResult(H.newStats(), 1, easy(P1)).played, 0);
});

test('stats: hist buckets -2, -1, 0, +1, +2, +3 and beyond', () => {
  const rec = (links, par = 4, best = 3) => H.recordResult(H.newStats(), 1, { chain: new Array(links + 1).fill('x'), par, best, status: 'won', inc: 0, hints: 0 }).hist;
  assert.deepEqual(rec(3), { '-2': 0, '-1': 1, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 });
  assert.deepEqual(rec(4), { '-2': 0, '-1': 0, 0: 1, 1: 0, 2: 0, 3: 0, X: 0 });
  assert.deepEqual(rec(5), { '-2': 0, '-1': 0, 0: 0, 1: 1, 2: 0, 3: 0, X: 0 });
  assert.deepEqual(rec(6), { '-2': 0, '-1': 0, 0: 0, 1: 0, 2: 1, 3: 0, X: 0 });
  assert.deepEqual(rec(7), { '-2': 0, '-1': 0, 0: 0, 1: 0, 2: 0, 3: 1, X: 0 });
  assert.deepEqual(rec(12), { '-2': 0, '-1': 0, 0: 0, 1: 0, 2: 0, 3: 1, X: 0 }); // +3 or more bucket together
  // eagle (hard mode) is its own bucket; albatross and beyond collapse into it
  assert.deepEqual(rec(3, 5), { '-2': 1, '-1': 0, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 });
  assert.deepEqual(rec(3, 6), { '-2': 1, '-1': 0, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 });
  assert.deepEqual(rec(3, 7), { '-2': 1, '-1': 0, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 });
  assert.deepEqual(rec(4, 5), { '-2': 0, '-1': 1, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 }); // best + 1 in hard is a birdie
  assert.deepEqual(rec(5, 5), { '-2': 0, '-1': 0, 0: 1, 1: 0, 2: 0, 3: 0, X: 0 });
  // shorter than best after a data refresh still lands in -1 (over = best - par)
  assert.deepEqual(rec(2), { '-2': 0, '-1': 1, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 });
  // a loss goes to X only
  const l = H.recordResult(H.newStats(), 1, { chain: ['x'], par: 4, best: 3, status: 'lost', inc: 3, hints: 0 }).hist;
  assert.deepEqual(l, { '-2': 0, '-1': 0, 0: 0, 1: 0, 2: 0, 3: 0, X: 1 });
});

test('stats: par streak counts par or better, resets on +1 or a loss', () => {
  const g = (links, status = 'won') => ({ chain: new Array(links + 1).fill('x'), par: 4, best: 3, status, inc: 0, hints: 0 });
  let st = H.newStats();
  st = H.recordResult(st, 1, g(3)); // birdie
  st = H.recordResult(st, 2, g(4)); // par
  st = H.recordResult(st, 3, g(3)); // birdie
  assert.deepEqual([st.parCur, st.parMax, st.cur, st.max], [3, 3, 3, 3]);
  st = H.recordResult(st, 4, g(5)); // +1
  assert.deepEqual([st.parCur, st.parMax, st.cur, st.max], [0, 3, 4, 4]);
  st = H.recordResult(st, 5, g(3)); // birdie restarts at 1
  assert.deepEqual([st.parCur, st.parMax, st.cur], [1, 3, 5]);
  st = H.recordResult(st, 6, g(1, 'lost'));
  assert.deepEqual([st.parCur, st.parMax, st.cur], [0, 3, 0]);
  // all birdies
  let b = H.newStats();
  for (let n = 20; n < 25; n++) b = H.recordResult(b, n, g(3));
  assert.deepEqual([b.parCur, b.parMax, b.hist['-1'], b.hist[0]], [5, 5, 5, 0]);
  // a skipped day breaks the par streak even when both days were birdies
  let gap = H.recordResult(H.newStats(), 1, g(3));
  gap = H.recordResult(gap, 3, g(3));
  assert.deepEqual([gap.parCur, gap.parMax], [1, 1]);
});

test('stats: older saved stats without the -1 bucket keep working', () => {
  const saved = { v: 1, played: 2, won: 2, cur: 2, max: 2, parCur: 2, parMax: 2, last: 6, lastWon: 6,
    hist: { 0: 2, 1: 0, 2: 0, 3: 0, X: 0 }, results: { 5: { links: 3, par: 3, inc: 0, hints: 0, won: true }, 6: { links: 3, par: 3, inc: 0, hints: 0, won: true } } };
  const birdie = { chain: new Array(4).fill('x'), par: 4, best: 3, status: 'won', inc: 0, hints: 0 };
  const st = H.recordResult(deepFreeze(saved), 7, birdie);
  assert.equal(st.hist['-1'], 1);
  assert.equal(st.hist[0], 2);
  assert.equal(Number.isNaN(st.hist['-1']), false);
  assert.deepEqual([st.parCur, st.parMax, st.cur, st.won], [3, 3, 3, 3]);
  // a state with no best (older data) records like before
  const legacy = { chain: new Array(4).fill('x'), par: 3, status: 'won', inc: 0, hints: 0 };
  assert.equal(H.recordResult(H.newStats(), 1, legacy).hist[0], 1);
  assert.deepEqual(H.recordResult(H.newStats(), 1, legacy).results[1], { links: 3, par: 3, inc: 0, hints: 0, won: true, mode: 'easy' });
});

test('stats: displayStreaks goes stale after a missed day', () => {
  let st = H.newStats();
  st = H.recordResult(st, 10, play(P1, ['T004', 'T007'])); // birdie
  st = H.recordResult(st, 11, play(P1, ['T004', 'T006', 'T007'])); // par
  assert.deepEqual(H.displayStreaks(st, 11), { cur: 2, max: 2, parCur: 2, parMax: 2 });
  assert.deepEqual(H.displayStreaks(st, 12), { cur: 2, max: 2, parCur: 2, parMax: 2 }); // today not yet played
  assert.deepEqual(H.displayStreaks(st, 13), { cur: 0, max: 2, parCur: 0, parMax: 2 });
  // par streak and win streak go stale independently
  st = H.recordResult(st, 12, play(P1, ['T015', 'T006', 'T004', 'T007'])); // +1
  assert.deepEqual(H.displayStreaks(st, 13), { cur: 3, max: 3, parCur: 0, parMax: 2 });
  assert.deepEqual(H.displayStreaks(st, 14), { cur: 0, max: 3, parCur: 0, parMax: 2 });
});

test('modes: hard par is best + 2, so the optimal chain is an Eagle and best + 1 a Birdie', () => {
  const eagle = play(P1, ['T004', 'T007'], 'hard');
  assert.deepEqual(H.score(eagle), { links: 3, par: 5, best: 3, over: -2, label: 'Eagle', won: true, mode: 'hard' });
  const birdie = play(P1, ['T004', 'T006', 'T007'], 'hard');
  assert.deepEqual(H.score(birdie), { links: 4, par: 5, best: 3, over: -1, label: 'Birdie', won: true, mode: 'hard' });
  const par = play(P1, ['T015', 'T006', 'T004', 'T007'], 'hard');
  assert.deepEqual(H.score(par), { links: 5, par: 5, best: 3, over: 0, label: 'Par', won: true, mode: 'hard' });
  const plus1 = { ...hard(P1), chain: ['T001', 'a', 'b', 'c', 'd', 'e', 'T003'], status: 'won' };
  assert.deepEqual([H.score(plus1).over, H.score(plus1).label], [1, '+1']);
  // two-link puzzle
  assert.deepEqual([H.score(play(P3, ['T007'], 'hard')).label, H.score(play(P3, ['T007'], 'hard')).over], ['Eagle', -2]);
  // the trade puzzle
  assert.equal(H.score(play(P2, ['T005', 'T002'], 'hard')).label, 'Eagle');
  assert.equal(H.score(play(P2, ['T005', 'T002'], 'easy')).label, 'Birdie');
  // a lost hard game is still X
  assert.equal(H.score(play(P1, ['T012', 'T017', 'T010'], 'hard')).label, 'X');
});

test('modes: an Eagle is impossible in easy mode, whatever the chain length', () => {
  for (const p of PUZZLES.puzzles) {
    for (let links = 0; links <= p.best + 6; links++) {
      const s = { ...easy(p), chain: new Array(links + 1).fill('x'), status: 'won' };
      assert.ok(H.score(s).over >= -1, `#${p.n} ${links} links`);
      assert.notEqual(H.score(s).label, 'Eagle');
    }
    // while hard can get there
    assert.equal(H.score({ ...hard(p), chain: new Array(p.best + 1).fill('x'), status: 'won' }).label, 'Eagle');
  }
  // the optimal route in easy, by playing it
  assert.equal(H.score(play(P1, ['T004', 'T007'], 'easy')).label, 'Birdie');
  assert.equal(H.score(play(P3, ['T007'], 'easy')).over, -1);
  // switching hard -> easy mid-game can never leave an Eagle behind either
  let s = hard(P1);
  s = H.setMode(s, 'easy').state;
  s = H.guess(idx, s, 'T004').state;
  s = H.guess(idx, s, 'T007').state;
  assert.deepEqual([s.status, H.score(s).label, H.score(s).mode], ['won', 'Birdie', 'easy']);
});

test('setMode: hard -> easy any time while playing, logged, par recomputed', () => {
  const fresh = deepFreeze(hard(P1));
  const r = H.setMode(fresh, 'easy');
  assert.equal(r.ok, true);
  assert.equal(r.reason, undefined);
  assert.deepEqual(r.state, { ...easy(P1), log: [{ t: 'm', mode: 'easy' }] });
  assert.deepEqual([r.state.mode, r.state.par, r.state.best], ['easy', 4, 3]);
  assert.equal(fresh.mode, 'hard'); // input untouched
  assert.equal(fresh.par, 5);
  assert.notEqual(r.state, fresh);
  // mid-game: chain, downs, hints, incompletions and the earlier log all survive
  let s = play(P1, ['T012', 'h', 'T004'], 'hard');
  assert.deepEqual([s.chain, s.downs, s.inc, s.hints], [['T001', 'T004'], 1, 1, 1]);
  const m = H.setMode(deepFreeze(s), 'easy');
  assert.equal(m.ok, true);
  assert.deepEqual([m.state.mode, m.state.par, m.state.best], ['easy', 4, 3]);
  assert.deepEqual([m.state.chain, m.state.downs, m.state.inc, m.state.hints, m.state.status], [s.chain, 1, 1, 1, 'playing']);
  assert.deepEqual(m.state.hintAt, s.hintAt);
  assert.deepEqual(m.state.log, [...s.log, { t: 'm', mode: 'easy' }]);
  // and the game plays on under the new par
  const done = H.guess(idx, m.state, 'T007').state;
  assert.deepEqual(H.score(done), { links: 3, par: 4, best: 3, over: -1, label: 'Birdie', won: true, mode: 'easy' });
  // after an undo, too
  assert.equal(H.setMode(play(P1, ['T004', 'u'], 'hard'), 'easy').ok, true);
  // survives a JSON round trip
  assert.deepEqual(JSON.parse(JSON.stringify(m.state)), m.state);
});

test('setMode: easy -> hard only before any move', () => {
  const fresh = deepFreeze(easy(P1));
  const r = H.setMode(fresh, 'hard');
  assert.equal(r.ok, true);
  assert.deepEqual(r.state, hard(P1)); // identical to a fresh hard game, log still empty
  assert.deepEqual([r.state.mode, r.state.par, r.state.log], ['hard', 5, []]);
  assert.equal(fresh.mode, 'easy');
  // the easy -> hard switch itself is not logged, so a pristine easy game stays pristine
  assert.deepEqual(H.setMode(H.setMode(r.state, 'hard').state, 'hard').state, r.state);
  // refused with 'started' after a guess (right or wrong), a hint, or a guess that was undone
  for (const moves of [['T004'], ['T012'], ['h'], ['T004', 'u'], ['T006', 'T015', 'u', 'u']]) {
    const s = play(P1, moves, 'easy');
    const x = H.setMode(deepFreeze(s), 'hard');
    assert.deepEqual([x.ok, x.reason], [false, 'started'], moves.join());
    assert.deepEqual(x.state, s, moves.join()); // returned unchanged (a copy)
    assert.equal(x.state.mode, 'easy');
    assert.equal(x.state.par, 4);
  }
  // hard -> easy -> hard is refused: the switch itself is a logged move
  const sw = H.setMode(hard(P1), 'easy').state;
  const again = H.setMode(sw, 'hard');
  assert.deepEqual([again.ok, again.reason], [false, 'started']);
  assert.equal(again.state.mode, 'easy');
});

test('setMode: finished games refuse with "over"; the same mode is a no-op', () => {
  const won = play(P1, ['T004', 'T007'], 'hard');
  const lost = play(P1, ['T012', 'T017', 'T010'], 'easy');
  const wonEasy = play(P1, ['T004', 'T007'], 'easy');
  for (const [s, to] of [[won, 'easy'], [lost, 'hard'], [wonEasy, 'hard'], [play(P1, ['T012', 'T017', 'T010'], 'hard'), 'easy']]) {
    const r = H.setMode(deepFreeze(s), to);
    assert.deepEqual([r.ok, r.reason], [false, 'over']);
    assert.deepEqual(r.state, s);
  }
  // same mode: ok, unchanged, nothing logged (also on a started or finished game)
  for (const [s, mode] of [[hard(P1), 'hard'], [easy(P1), 'easy'], [play(P1, ['T004'], 'hard'), 'hard'], [play(P1, ['T004'], 'easy'), 'easy'], [won, 'hard'], [lost, 'easy']]) {
    const r = H.setMode(deepFreeze(s), mode);
    assert.equal(r.ok, true);
    assert.equal(r.reason, undefined);
    assert.deepEqual(r.state, s);
    assert.notEqual(r.state, s);
  }
  // an unknown mode means hard, like everywhere else
  assert.equal(H.setMode(easy(P1), 'zzz').state.mode, 'hard');
  assert.equal(H.setMode(hard(P1), 'zzz').ok, true);
  assert.equal(H.setMode(hard(P1), 'zzz').state.log.length, 0);
});

test('setMode: states saved before modes existed count as easy', () => {
  const fresh = play(P1, [], 'legacy');
  assert.equal(fresh.mode, undefined);
  assert.equal(fresh.par, 4);
  // same (easy) mode: no-op, the state is left exactly as saved
  const same = H.setMode(fresh, 'easy');
  assert.deepEqual([same.ok, same.state], [true, fresh]);
  // easy -> hard before any move works, and then there is a mode
  const up = H.setMode(fresh, 'hard');
  assert.equal(up.ok, true);
  assert.deepEqual([up.state.mode, up.state.par], ['hard', 5]);
  // after a move it is refused
  const moved = play(P1, ['T004'], 'legacy');
  assert.deepEqual([H.setMode(moved, 'hard').ok, H.setMode(moved, 'hard').reason], [false, 'started']);
  // a legacy game finished: over
  assert.equal(H.setMode(play(P1, ['T004', 'T007'], 'legacy'), 'hard').reason, 'over');
  // a legacy state without best uses best = par
  const noBest = { ...fresh, par: 3 }; delete noBest.best;
  assert.equal(H.setMode(noBest, 'hard').state.par, 5);
  // scoring a legacy state keeps working and reports easy
  const sc = H.score(play(P1, ['T004', 'T007'], 'legacy'));
  assert.deepEqual([sc.over, sc.label, sc.mode], [-1, 'Birdie', 'easy']);
  // a legacy state can still be played on: guess, undo, hint
  const g = H.guess(idx, fresh, 'T004').state;
  assert.equal(g.mode, undefined);
  assert.equal(H.hint(idx, g).hint.team, 'OAK');
});

test('shareText: hard games carry a mode tag, easy and saved-before-modes ones do not', () => {
  const T = 'cev64.github.io/handoff/#1';
  // hard eagle (optimal chain)
  assert.equal(H.shareText(P1, play(P1, ['T004', 'T007'], 'hard')), `Chainmates #1 🏈 · Hard\n🟩🟩🟩 3 links · Par 5 · Eagle 🦅\n${T}`);
  // hard birdie (best + 1)
  assert.equal(H.shareText(P1, play(P1, ['T004', 'T006', 'T007'], 'hard')), `Chainmates #1 🏈 · Hard\n🟩🟩🟩🟩 4 links · Par 5 · Birdie 🐦\n${T}`);
  // hard par (best + 2)
  assert.equal(H.shareText(P1, play(P1, ['T015', 'T006', 'T004', 'T007'], 'hard')), `Chainmates #1 🏈 · Hard\n🟩🟩🟩🟩🟩 5 links · Par 5 ⛳\n${T}`);
  // hard +1, with an incompletion and a hint
  const over = { ...play(P1, ['T012', 'h'], 'hard'), chain: ['T001', 'a', 'b', 'c', 'd', 'e', 'T003'], status: 'won' };
  assert.equal(H.shareText(P1, over), `Chainmates #1 🏈 · Hard\n🟩🟩🟩🟩🟩🟨 6 links · Par 5 (+1)\n🟥 1 incompletion\n💡 1 hint\n${T}`);
  // easy birdie: no tag, par 4
  assert.equal(H.shareText(P1, play(P1, ['T004', 'T007'], 'easy')), `Chainmates #1 🏈\n🟩🟩🟩 3 links · Par 4 · Birdie 🐦\n${T}`);
  // easy par
  assert.equal(H.shareText(P1, play(P1, ['T004', 'T006', 'T007'], 'easy')), `Chainmates #1 🏈\n🟩🟩🟩🟩 4 links · Par 4 ⛳\n${T}`);
  // lost in hard keeps the tag and the hard par; lost in easy has none
  assert.equal(H.shareText(P1, play(P1, ['T012', 'T017', 'T010'], 'hard')), `Chainmates #1 🏈 · Hard\n🏳️ Turnover on downs · Par 5\n🟥 3 incompletions\n${T}`);
  assert.equal(H.shareText(P1, play(P1, ['T012', 'T017', 'T010'], 'easy')), `Chainmates #1 🏈\n🏳️ Turnover on downs · Par 4\n🟥 3 incompletions\n${T}`);
  // hard -> easy mid-game: shared as the final mode (easy), with the easy par
  const sw = H.setMode(play(P1, ['T004'], 'hard'), 'easy').state;
  assert.equal(H.shareText(P1, H.guess(idx, sw, 'T007').state), `Chainmates #1 🏈\n🟩🟩🟩 3 links · Par 4 · Birdie 🐦\n${T}`);
  // uses state.par, not puzzle.par: the fixture puzzle's own par (4) is the easy par
  assert.equal(P1.par, 4);
  assert.match(H.shareText(P1, play(P1, ['T004', 'T007'], 'hard')), /Par 5/);
  // a custom title and emoji keep the tag after the emoji
  assert.equal(H.shareText(P1, play(P1, ['T004', 'T007'], 'hard'), { title: 'Chainmates NBA', emoji: '🏀' }),
    `Chainmates NBA #1 🏀 · Hard\n🟩🟩🟩 3 links · Par 5 · Eagle 🦅\n${T}`);
  // hardLabel replaces the word; it never touches easy games
  assert.equal(H.shareText(P1, play(P1, ['T004', 'T007'], 'hard'), { hardLabel: 'Pro' }).split('\n')[0], 'Chainmates #1 🏈 · Pro');
  assert.equal(H.shareText(P1, play(P1, ['T004', 'T007'], 'easy'), { hardLabel: 'Pro' }).split('\n')[0], 'Chainmates #1 🏈');
  assert.equal(H.shareText(P1, play(P1, ['T004', 'T007'], 'hard'), { hardLabel: '' }).split('\n')[0], 'Chainmates #1 🏈 · Hard');
  // never leaks names
  assert.doesNotMatch(H.shareText(P1, play(P1, ['T004', 'T007'], 'hard')), /Marlow|Tolliver|Broncos|DEN/);
});

test('stats: hard-mode Eagle lands in the -2 bucket, results store the mode', () => {
  const eagle = play(P1, ['T004', 'T007'], 'hard');
  const hBirdie = play(P1, ['T004', 'T006', 'T007'], 'hard');
  const hPar = play(P1, ['T015', 'T006', 'T004', 'T007'], 'hard');
  const eBirdie = play(P1, ['T004', 'T007'], 'easy');
  const lost = play(P1, ['T012', 'T017', 'T010'], 'hard');
  let st = H.newStats();
  st = H.recordResult(st, 1, eagle);
  assert.deepEqual(st.hist, { '-2': 1, '-1': 0, 0: 0, 1: 0, 2: 0, 3: 0, X: 0 });
  assert.deepEqual(st.results[1], { links: 3, par: 5, inc: 0, hints: 0, won: true, mode: 'hard' });
  st = H.recordResult(st, 2, hBirdie);
  st = H.recordResult(st, 3, hPar);
  st = H.recordResult(st, 4, eBirdie);
  assert.deepEqual(st.hist, { '-2': 1, '-1': 2, 0: 1, 1: 0, 2: 0, 3: 0, X: 0 });
  assert.deepEqual(st.results[2], { links: 4, par: 5, inc: 0, hints: 0, won: true, mode: 'hard' });
  assert.deepEqual(st.results[4], { links: 3, par: 4, inc: 0, hints: 0, won: true, mode: 'easy' });
  // streaks are unchanged: every one of these is par or better
  assert.deepEqual([st.cur, st.max, st.parCur, st.parMax], [4, 4, 4, 4]);
  // an over-par hard result (+1) ends the par streak but not the win streak
  st = H.recordResult(st, 5, { ...hard(P1), chain: ['T001', 'a', 'b', 'c', 'd', 'e', 'T003'], status: 'won', inc: 0, hints: 0 });
  assert.deepEqual([st.cur, st.parCur, st.parMax, st.hist[1]], [5, 0, 4, 1]);
  st = H.recordResult(st, 6, lost);
  assert.deepEqual([st.cur, st.hist.X, st.results[6].mode, st.results[6].won], [0, 1, 'hard', false]);
  // a game that switched mode records its final mode
  const sw = H.guess(idx, H.guess(idx, H.setMode(hard(P1), 'easy').state, 'T004').state, 'T007').state;
  assert.equal(H.recordResult(H.newStats(), 9, sw).results[9].mode, 'easy');
  // a state saved before modes existed records as easy
  assert.equal(H.recordResult(H.newStats(), 9, play(P1, ['T004', 'T007'], 'legacy')).results[9].mode, 'easy');
});

test('stats: saved stats without the -2 bucket keep working', () => {
  const saved = { v: 1, played: 2, won: 2, cur: 2, max: 2, parCur: 2, parMax: 2, last: 6, lastWon: 6,
    hist: { '-1': 1, 0: 1, 1: 0, 2: 0, 3: 0, X: 0 }, results: { 5: { links: 3, par: 4, inc: 0, hints: 0, won: true }, 6: { links: 4, par: 4, inc: 0, hints: 0, won: true } } };
  const st = H.recordResult(deepFreeze(saved), 7, play(P1, ['T004', 'T007'], 'hard'));
  assert.equal(st.hist['-2'], 1);
  assert.equal(st.hist['-1'], 1);
  assert.equal(Number.isNaN(st.hist['-2']), false);
  assert.deepEqual([st.parCur, st.parMax, st.cur, st.won], [3, 3, 3, 3]);
  assert.equal(saved.hist['-2'], undefined);
  // results saved without a mode are left alone
  assert.equal(st.results[5].mode, undefined);
  // a loss on stats that never had either bucket
  const bare = { v: 1, played: 0, won: 0, cur: 0, max: 0, parCur: 0, parMax: 0, last: 0, lastWon: 0, hist: { 0: 0, 1: 0, 2: 0, 3: 0, X: 0 }, results: {} };
  assert.equal(H.recordResult(bare, 1, play(P1, ['T012', 'T017', 'T010'], 'hard')).hist.X, 1);
});

test('stintRanges: merges consecutive seasons, keeps gaps and trades apart', () => {
  const r = (id) => H.stintRanges(idx, id);
  // gap between two different teams: chronological
  assert.deepEqual(r('T001'), [{ team: 'IND', from: 2002, to: 2010 }, { team: 'DEN', from: 2012, to: 2015 }]);
  assert.deepEqual(r('T004'), [{ team: 'DEN', from: 2014, to: 2015 }, { team: 'OAK', from: 2016, to: 2017 }]);
  // one season with one team
  assert.deepEqual(r('T006'), [{ team: 'DEN', from: 2013, to: 2013 }, { team: 'OAK', from: 2017, to: 2017 }]);
  // one team only
  assert.deepEqual(r('T003'), [{ team: 'LV', from: 2020, to: 2022 }]);
  // a mid-season trade: separate entries for the same season, ordered by team
  assert.deepEqual(r('T002'), [{ team: 'MIN', from: 2010, to: 2010 }, { team: 'NYJ', from: 2010, to: 2010 }]);
  assert.deepEqual(r('T005'), [{ team: 'IND', from: 2010, to: 2010 }, { team: 'NYJ', from: 2010, to: 2010 }]);
  // a gap with the same team splits it
  assert.deepEqual(r('T018'), [{ team: 'WAS', from: 2019, to: 2019 }, { team: 'WAS', from: 2022, to: 2022 }]);
  // an abbreviation change is a different team: OAK 2019 and LV 2020 do not merge
  assert.deepEqual(r('T007'), [{ team: 'OAK', from: 2017, to: 2017 }, { team: 'LV', from: 2020, to: 2021 }]);
  assert.deepEqual(r('T008'), [{ team: 'GB', from: 2018, to: 2021 }, { team: 'LV', from: 2022, to: 2022 }]);
  assert.deepEqual(r('nope'), []);
  // the result is plain data, and a fresh array every time
  assert.deepEqual(JSON.parse(JSON.stringify(r('T001'))), r('T001'));
  assert.notEqual(r('T001'), r('T001'));
  r('T001').push({ team: 'X', from: 1, to: 1 });
  assert.equal(r('T001').length, 2);
});

test('stintRanges: odd stint strings (unsorted, duplicate, returns to a team, trade in the middle)', () => {
  const mk = (stints) => H.buildIndex({ v: 1, sport: 'nfl', teams: {}, players: [['p', 'P', 'QB', 1, stints]] });
  const sr = (stints) => H.stintRanges(mk(stints), 'p');
  // out of order input comes back chronological, runs merge across separate range entries
  assert.deepEqual(sr('DEN:2014-2015;DEN:2012-2013'), [{ team: 'DEN', from: 2012, to: 2015 }]);
  assert.deepEqual(sr('DEN:2013;DEN:2012;DEN:2014'), [{ team: 'DEN', from: 2012, to: 2014 }]);
  // duplicate seasons collapse
  assert.deepEqual(sr('DEN:2012-2013;DEN:2013'), [{ team: 'DEN', from: 2012, to: 2013 }]);
  // leaving a team and coming back later
  assert.deepEqual(sr('DEN:2010-2011;IND:2012-2014;DEN:2015'), [
    { team: 'DEN', from: 2010, to: 2011 }, { team: 'IND', from: 2012, to: 2014 }, { team: 'DEN', from: 2015, to: 2015 }]);
  // same start season: ordered by team code
  assert.deepEqual(sr('NE:2010-2012;DEN:2010-2011'), [{ team: 'DEN', from: 2010, to: 2011 }, { team: 'NE', from: 2010, to: 2012 }]);
  // a trade in the middle of a long stay keeps the long stay whole
  assert.deepEqual(sr('DEN:2012-2014;IND:2013'), [{ team: 'DEN', from: 2012, to: 2014 }, { team: 'IND', from: 2013, to: 2013 }]);
  assert.deepEqual(sr(''), []);
});

test('puzzle 2 full run through the trade is a birdie', () => {
  const s = play(P2, ['T005', 'T002']);
  assert.equal(s.status, 'won');
  assert.deepEqual(H.score(s), { links: 3, par: 4, best: 3, over: -1, label: 'Birdie', won: true, mode: 'easy' });
  assert.equal(H.validateChain(idx, s.chain).ok, true);
  assert.equal(H.shareText(P2, s), 'Chainmates #2 🏈\n🟩🟩🟩 3 links · Par 4 · Birdie 🐦\ncev64.github.io/handoff/#2');
});
