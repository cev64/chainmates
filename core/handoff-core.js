/*! Chainmates core: pure, sport-agnostic game logic for the daily teammate-chain puzzle (all team data comes from players.json `teams`).
 *  ES2018, no dependencies, no DOM/fetch/timers. UMD: Node (require), browser (globalThis.HandoffCore), JavaScriptCore.
 *  Contract: docs/spec.md */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.HandoffCore = factory();
})(typeof globalThis !== 'undefined' ? globalThis : typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const DOWNS = 3;
  const DAY = 86400000;

  // ---------------------------------------------------------------- stints / index

  /** "DEN:2012-2015;IND:2010" -> [{team,season}, ...] (one entry per season, in string order) */
  function parseStints(str) {
    const out = [];
    if (!str) return out;
    for (const part of String(str).split(';')) {
      const c = part.indexOf(':');
      if (c < 1) continue;
      const team = part.slice(0, c).trim();
      const range = part.slice(c + 1);
      const d = range.indexOf('-');
      const a = parseInt(d < 0 ? range : range.slice(0, d), 10);
      const b = d < 0 ? a : parseInt(range.slice(d + 1), 10);
      if (!(a <= b)) continue; // also rejects NaN
      for (let s = a; s <= b; s++) out.push({ team, season: s });
    }
    return out;
  }

  /** Lowercase, strip accents; apostrophes and periods vanish, every other non-alphanumeric run becomes one space. */
  function normalize(str) {
    return String(str == null ? '' : str)
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .toLowerCase().replace(/\u00f8/g, 'o').replace(/\u0142/g, 'l')
      .replace(/['\u2018\u2019\u02bc`.]/g, '')
      .replace(/[^a-z0-9]+/g, ' ').trim();
  }

  /**
   * Index layout (treat as opaque outside this file). Players are addressed by integer position `i`
   * (file order = fame order). Team-seasons ("DEN|2012") are interned to integer ids `t`.
   */
  function buildIndex(json) {
    const rows = json.players || [];
    const n = rows.length;
    const idx = {
      teams: json.teams || {},
      sport: json.sport || null,
      meta: { v: json.v, built: json.built, seasons: json.seasons, source: json.source },
      n,
      ids: new Array(n), names: new Array(n), pos: new Array(n), fame: new Array(n),
      stints: new Array(n), first: new Array(n), last: new Array(n), norm: new Array(n), flat: new Array(n),
      playerTs: new Array(n),           // i -> [t]  (team-season ids)
      byId: new Map(),                  // player id -> i
      tsId: new Map(),                  // "TEAM|season" -> t
      tsKeys: [], tsTeam: [], tsSeason: [],
      tsMembers: [],                    // t -> [i] ascending
      cache: new Array(n),              // lazily built public player objects
    };
    for (let i = 0; i < n; i++) {
      const r = rows[i];
      const st = parseStints(r[4]);
      const mine = [];
      let first = null, last = null;
      for (const s of st) {
        const key = s.team + '|' + s.season;
        let t = idx.tsId.get(key);
        if (t === undefined) {
          t = idx.tsKeys.length;
          idx.tsId.set(key, t);
          idx.tsKeys.push(key); idx.tsTeam.push(s.team); idx.tsSeason.push(s.season);
          idx.tsMembers.push([]);
        }
        if (mine.indexOf(t) < 0) { mine.push(t); idx.tsMembers[t].push(i); }
        if (first === null || s.season < first) first = s.season;
        if (last === null || s.season > last) last = s.season;
      }
      idx.ids[i] = r[0]; idx.names[i] = r[1]; idx.pos[i] = r[2]; idx.fame[i] = r[3];
      idx.stints[i] = st; idx.first[i] = first; idx.last[i] = last;
      idx.norm[i] = normalize(r[1]);
      idx.flat[i] = idx.norm[i].replace(/ /g, '');
      idx.playerTs[i] = mine;
      idx.byId.set(r[0], i);
    }
    return idx;
  }

  function player(idx, id) {
    const i = idx.byId.get(id);
    if (i === undefined) return null;
    return idx.cache[i] || (idx.cache[i] = {
      id, name: idx.names[i], pos: idx.pos[i], fame: idx.fame[i],
      stints: idx.stints[i], first: idx.first[i], last: idx.last[i],
    });
  }

  function teamName(idx, team, season) {
    const t = idx.teams[team];
    if (!t) return null;
    if (t.names) for (const [from, to, nm] of t.names) if (season >= from && season <= to) return nm;
    return t.name;
  }
  function teamLabel(idx, team, season) {
    return season + ' ' + (teamName(idx, team, season) || team);
  }
  function teamFullName(idx, team, season) {
    const nm = teamName(idx, team, season);
    if (!nm) return team;
    const city = idx.teams[team].city;
    return !city || nm.indexOf(city) === 0 ? nm : city + ' ' + nm;
  }

  // ---------------------------------------------------------------- graph

  const tsObj = (idx, t) => ({ team: idx.tsTeam[t], season: idx.tsSeason[t] });
  const bySeasonDescTeam = (a, b) => b.season - a.season || (a.team < b.team ? -1 : a.team > b.team ? 1 : 0);

  function sharedIdx(idx, i, j) {
    if (i === undefined || j === undefined || i === j) return [];
    const B = idx.playerTs[j];
    const out = [];
    for (const t of idx.playerTs[i]) if (B.indexOf(t) >= 0) out.push(tsObj(idx, t));
    return out.sort(bySeasonDescTeam);
  }
  function sharedTeams(idx, a, b) { return sharedIdx(idx, idx.byId.get(a), idx.byId.get(b)); }
  function areTeammates(idx, a, b) { return sharedTeams(idx, a, b).length > 0; }

  /**
   * BFS over the bipartite player <-> team-season graph from player src, each team-season expanded once.
   * Fills dist (hops between players, -1 = unseen) and returns dist[dst] (stopping as soon as dst is seen,
   * so every layer below dist[dst] is complete) or -1.
   */
  function bfs(idx, src, dst, dist) {
    const seen = new Uint8Array(idx.tsKeys.length);
    dist.fill(-1);
    dist[src] = 0;
    if (src === dst) return 0;
    let layer = [src];
    for (let d = 0; layer.length; d++) {
      const next = [];
      for (const p of layer) {
        for (const t of idx.playerTs[p]) {
          if (seen[t]) continue;
          seen[t] = 1;
          for (const q of idx.tsMembers[t]) {
            if (dist[q] >= 0) continue;
            dist[q] = d + 1;
            if (q === dst) return d + 1;
            next.push(q);
          }
        }
      }
      layer = next;
    }
    return -1;
  }

  /** Visit neighbours (teammates) of p that sit on a shortest a->b path at layer d+1. */
  function eachOnPathNeighbor(idx, p, d, D, dA, dB, fn) {
    for (const t of idx.playerTs[p]) for (const q of idx.tsMembers[t]) if (dA[q] === d + 1 && dB[q] === D - d - 1) fn(q);
  }

  /**
   * {dist, path, links, count} or null. count = number of distinct shortest player sequences (two players sharing
   * several team-seasons are ONE edge). The returned path is deterministic: at each step the lowest player index
   * (= highest fame in players.json order) among on-path teammates; links[k] = sharedTeams(path[k], path[k+1])[0].
   */
  function shortestPath(idx, a, b) {
    const s = idx.byId.get(a), e = idx.byId.get(b);
    if (s === undefined || e === undefined) return null;
    if (s === e) return { dist: 0, path: [a], links: [], count: 1 };
    const dA = new Int32Array(idx.n), dB = new Int32Array(idx.n);
    const D = bfs(idx, s, e, dA);
    if (D < 0) return null;
    bfs(idx, e, s, dB);
    // Count sequences layer by layer through the shortest-path DAG (players with dA + dB == D).
    const cnt = new Float64Array(idx.n), stamp = new Int32Array(idx.n).fill(-1);
    cnt[s] = 1;
    let layer = [s];
    for (let d = 0; d < D; d++) {
      const next = [];
      for (const p of layer) {
        eachOnPathNeighbor(idx, p, d, D, dA, dB, (q) => {
          if (stamp[q] === p) return;       // already counted via another shared team-season
          stamp[q] = p;
          if (cnt[q] === 0) next.push(q);
          cnt[q] += cnt[p];
        });
      }
      layer = next;
    }
    const pathIdx = [s];
    for (let d = 0, cur = s; d < D; d++) {
      let best = -1;
      eachOnPathNeighbor(idx, cur, d, D, dA, dB, (q) => { if (best < 0 || q < best) best = q; });
      pathIdx.push(best); cur = best;
    }
    const links = [];
    for (let k = 0; k < D; k++) links.push(sharedIdx(idx, pathIdx[k], pathIdx[k + 1])[0]);
    return { dist: D, path: pathIdx.map((i) => idx.ids[i]), links, count: cnt[e] };
  }

  function validateChain(idx, ids) {
    if (!Array.isArray(ids) || ids.length < 2) return { ok: false, at: 0, reason: 'too-short' };
    const seen = new Set(), links = [];
    for (let i = 0; i < ids.length; i++) {
      if (!idx.byId.has(ids[i])) return { ok: false, at: i, reason: 'unknown' };
      if (seen.has(ids[i])) return { ok: false, at: i, reason: 'duplicate' };
      seen.add(ids[i]);
      if (i > 0) {
        const sh = sharedTeams(idx, ids[i - 1], ids[i]);
        if (!sh.length) return { ok: false, at: i, reason: 'not-teammates' };
        links.push(sh[0]);
      }
    }
    return { ok: true, links };
  }

  // ---------------------------------------------------------------- search

  /** Ranked autocomplete: 0 full-name prefix, 1 word prefix (or every query token prefixes some word), 2 substring. */
  function search(idx, query, opts) {
    const limit = opts && opts.limit > 0 ? opts.limit : 8;
    const ex = new Set((opts && opts.exclude) || []);
    const q = normalize(query);
    if (!q) return [];
    const toks = q.split(' ');
    // Space-free form, so "le veon" finds Le'Veon (normalized "leveon") and "jamarr" finds Ja Marr.
    const qf = q.replace(/ /g, '');
    const hits = [];
    for (let i = 0; i < idx.n; i++) {
      if (ex.size && ex.has(idx.ids[i])) continue;
      const nm = idx.norm[i];
      let rank;
      if (nm.startsWith(q)) rank = 0;
      else {
        const sp = ' ' + nm;
        if (sp.includes(' ' + q) || (toks.length > 1 && toks.every((t) => sp.includes(' ' + t)))) rank = 1;
        else if (nm.includes(q)) rank = 2;
        else if (qf.length >= 3 && idx.flat[i].startsWith(qf)) rank = 1;
        else if (qf.length >= 3 && idx.flat[i].includes(qf)) rank = 2;
        else continue;
      }
      hits.push([rank, idx.fame[i], i]);
    }
    hits.sort((x, y) => x[0] - y[0] || y[1] - x[1] || x[2] - y[2]);
    return hits.slice(0, limit).map((h) => player(idx, idx.ids[h[2]]));
  }

  // ---------------------------------------------------------------- dates / puzzles

  const pad2 = (n) => (n < 10 ? '0' : '') + n;
  const ymdUTC = (d) => d.getUTCFullYear() + '-' + pad2(d.getUTCMonth() + 1) + '-' + pad2(d.getUTCDate());
  const nthSunday = (y, month, n) => 1 + ((7 - new Date(Date.UTC(y, month, 1)).getUTCDay()) % 7) + 7 * (n - 1);

  /** Manual US rule (2007+): DST from 2nd Sunday of March 2:00 EST (07:00Z) to 1st Sunday of Nov 2:00 EDT (06:00Z). */
  function easternDateFallback(date) {
    const t = date.getTime();
    const y = new Date(t).getUTCFullYear();
    const start = Date.UTC(y, 2, nthSunday(y, 2, 2), 7);
    const end = Date.UTC(y, 10, nthSunday(y, 10, 1), 6);
    const offsetHours = t >= start && t < end ? -4 : -5;
    return ymdUTC(new Date(t + offsetHours * 3600000));
  }

  let eastern = null;
  function easternDate(date) {
    const d = date === undefined ? new Date() : date instanceof Date ? date : new Date(date);
    try {
      if (typeof Intl === 'object' && Intl.DateTimeFormat) {
        eastern = eastern || new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit' });
        const p = {};
        for (const x of eastern.formatToParts(d)) p[x.type] = x.value;
        if (p.year && p.month && p.day) return p.year + '-' + p.month + '-' + p.day;
      }
    } catch (err) { /* no Intl / no tz data: fall through */ }
    return easternDateFallback(d);
  }

  const dayNumber = (ymd) => { const [y, m, d] = String(ymd).split('-').map(Number); return Math.round(Date.UTC(y, m - 1, d) / DAY); };
  function puzzleNumberForDate(pj, ymd) { return dayNumber(ymd) - dayNumber(pj.epoch) + 1; }
  function puzzleByNumber(pj, n) {
    if (!Number.isInteger(n)) return null;
    const p = pj.puzzles[n - 1];
    return p && p.n === n ? p : pj.puzzles.find((x) => x.n === n) || null;
  }
  function puzzleForDate(pj, ymd) { return puzzleByNumber(pj, puzzleNumberForDate(pj, ymd)); }

  // ---------------------------------------------------------------- game

  const clone = (s) => Object.assign({}, s, { chain: s.chain.slice(), hintAt: Object.assign({}, s.hintAt), log: s.log.slice() });
  const lastOf = (s) => s.chain[s.chain.length - 1];

  function newGame(puzzle, opts) {
    return {
      n: puzzle.n, start: puzzle.start, end: puzzle.end, par: puzzle.par,
      chain: [puzzle.start], downs: opts && opts.downs > 0 ? opts.downs : DOWNS,
      inc: 0, hints: 0, hintAt: {}, status: 'playing', log: [],
    };
  }

  /** Rejected guesses (unknown/in-chain/start/end/over) cost nothing and are not logged. */
  function guess(idx, state, id) {
    const s = clone(state);
    const reject = (reason) => ({ state: s, result: { kind: 'rejected', reason } });
    if (s.status !== 'playing') return reject('over');
    if (!idx.byId.has(id)) return reject('unknown');
    if (id === s.start) return reject('start');
    if (s.chain.indexOf(id) >= 0) return reject('in-chain');
    if (id === s.end) return reject('end');
    const links = sharedTeams(idx, lastOf(s), id);
    if (!links.length) {
      s.inc++; s.downs--;
      s.log.push({ t: 'g', id, ok: false });
      if (s.downs <= 0) { s.status = 'lost'; return { state: s, result: { kind: 'lost', downsLeft: 0 } }; }
      return { state: s, result: { kind: 'incompletion', downsLeft: s.downs } };
    }
    s.chain.push(id);
    s.log.push({ t: 'g', id, ok: true });
    const final = sharedTeams(idx, id, s.end);
    if (final.length) {
      s.chain.push(s.end);
      s.status = 'won';
      return { state: s, result: { kind: 'solved', links, final } };
    }
    return { state: s, result: { kind: 'link', links } };
  }

  function undo(state) {
    const s = clone(state);
    if (s.status !== 'playing' || s.chain.length < 2) return s;
    s.chain.pop();
    s.log.push({ t: 'u' });
    return s;
  }

  /** Costs a down (refused on the last one). Cached per last player, so repeating at the same position is free. */
  function hint(idx, state) {
    const s = clone(state);
    if (s.status !== 'playing') return { state: s, error: 'over' };
    const last = lastOf(s);
    const cached = s.hintAt[last];
    if (cached) return { state: s, hint: Object.assign({}, cached) };
    if (s.downs <= 1) return { state: s, error: 'last-down' };
    const sp = shortestPath(idx, last, s.end);
    if (!sp || sp.dist < 1) return { state: s, error: 'none' };
    const h = { team: sp.links[0].team, season: sp.links[0].season };
    s.hintAt[last] = h;
    s.hints++; s.downs--;
    s.log.push({ t: 'h', team: h.team, season: h.season });
    return { state: s, hint: Object.assign({}, h) };
  }

  function score(state) {
    const links = state.chain.length - 1;
    const won = state.status === 'won';
    const over = Math.max(0, links - state.par);
    const label = state.status === 'lost' ? 'X' : over === 0 ? 'Par' : '+' + over;
    return { links, par: state.par, over, label, won };
  }

  function shareText(puzzle, state, opts) {
    const url = (opts && opts.url) || 'cev64.github.io/handoff/';
    const sc = score(state), par = puzzle.par, over = Math.max(0, sc.links - par);
    const title = (opts && opts.title) || 'Chainmates';
    const emoji = (opts && opts.emoji) || '\u{1F3C8}';
    const lines = [title + ' #' + puzzle.n + ' ' + emoji];
    if (sc.won) {
      const squares = '\u{1F7E9}'.repeat(Math.min(sc.links, par)) + '\u{1F7E8}'.repeat(Math.max(0, sc.links - par));
      lines.push(squares + ' ' + sc.links + ' links \u00b7 Par ' + par + (over === 0 ? ' \u26f3' : ' (+' + over + ')'));
    } else {
      lines.push('\u{1F3F3}\ufe0f Turnover on downs \u00b7 Par ' + par);
    }
    if (state.inc > 0) lines.push('\u{1F7E5} ' + state.inc + ' incompletion' + (state.inc === 1 ? '' : 's'));
    if (state.hints > 0) lines.push('\u{1F4A1} ' + state.hints + ' hint' + (state.hints === 1 ? '' : 's'));
    lines.push(url + '#' + puzzle.n);
    return lines.join('\n');
  }

  // ---------------------------------------------------------------- stats

  function newStats() {
    return { v: 1, played: 0, won: 0, cur: 0, max: 0, parCur: 0, parMax: 0, last: 0, lastWon: 0,
      hist: { 0: 0, 1: 0, 2: 0, 3: 0, X: 0 }, results: {} };
  }

  /** Record a finished DAILY game (callers must not record archive/practice plays). No-op if already recorded or unfinished. */
  function recordResult(stats, n, state) {
    if (state.status === 'playing' || stats.results[n]) return stats;
    const st = Object.assign({}, stats, { hist: Object.assign({}, stats.hist), results: Object.assign({}, stats.results) });
    const sc = score(state);
    st.played++;
    st.results[n] = { links: sc.links, par: sc.par, inc: state.inc, hints: state.hints, won: sc.won };
    if (sc.won) {
      st.won++;
      st.hist[Math.min(3, sc.over)]++;
      st.cur = stats.cur > 0 && stats.lastWon === n - 1 ? stats.cur + 1 : 1;
      st.lastWon = Math.max(stats.lastWon, n);
      // parCur > 0 means the previous daily result was a par finish, so `last` is that puzzle number.
      st.parCur = sc.over === 0 ? (stats.parCur > 0 && stats.last === n - 1 ? stats.parCur + 1 : 1) : 0;
    } else {
      st.hist.X++;
      st.cur = 0;
      st.parCur = 0;
    }
    st.last = Math.max(stats.last, n);
    st.max = Math.max(st.max, st.cur);
    st.parMax = Math.max(st.parMax, st.parCur);
    return st;
  }

  /** Streaks as shown on day todayN: a streak whose last entry is older than yesterday's puzzle shows 0. */
  function displayStreaks(stats, todayN) {
    return {
      cur: stats.lastWon >= todayN - 1 ? stats.cur : 0,
      max: stats.max,
      parCur: stats.last >= todayN - 1 ? stats.parCur : 0,
      parMax: stats.parMax,
    };
  }

  return {
    DOWNS, parseStints, buildIndex, player, teamLabel, teamFullName, sharedTeams, areTeammates, shortestPath,
    validateChain, normalize, search, easternDate, puzzleNumberForDate, puzzleForDate, puzzleByNumber,
    newGame, guess, undo, hint, score, shareText, newStats, recordResult, displayStreaks,
    _easternDateFallback: easternDateFallback,
  };
});
