/* Chainmates web client. Vanilla JS, no build step.
 * Every game rule (guessing, downs, hints, undo, scoring, dates, search, share text, stats) comes from
 * core/handoff-core.js (globalThis.HandoffCore). This file only renders, routes, animates and stores. */
(function () {
  'use strict';

  const H = window.HandoffCore;
  const SPORTS = window.CHAINMATES_SPORTS || {};

  /* ------------------------------------------------------------ config */
  const CONFIG = {
    shareUrl: 'cev64.github.io/handoff/', // base URL in the share text; the core appends "#n"
    searchLimit: 8,
    debounceMs: 100,
    toastMs: 3400,
  };
  const THEME_KEY = 'chainmates.theme';

  /* ------------------------------------------------------------ sport */
  const sportKeys = Object.keys(SPORTS);
  const sportKey = (() => {
    let want = null;
    try { want = new URLSearchParams(location.search).get('sport'); } catch (e) { /* old browser */ }
    if (want && SPORTS[want]) return want;
    return SPORTS[window.CHAINMATES_DEFAULT_SPORT] ? window.CHAINMATES_DEFAULT_SPORT : sportKeys[0];
  })();
  const S = SPORTS[sportKey];
  const KEY = (k) => 'chainmates.' + sportKey + '.' + k;
  const LIFE = S.life || 'down', LIVES = S.lives || 'downs';
  document.documentElement.setAttribute('data-sport', sportKey);
  if (S.texture) document.documentElement.setAttribute('data-texture', S.texture);

  /* ------------------------------------------------------------ helpers */
  const $ = (sel, root) => (root || document).querySelector(sel);
  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ESC[c]);
  const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
  const plural = (n, one, many) => n + ' ' + (n === 1 ? one : many || one + 's');
  const downsLeft = (n) => plural(n, LIFE, LIVES) + ' left';
  const REDUCE = window.matchMedia('(prefers-reduced-motion: reduce)');
  const PHONE = window.matchMedia('(max-width: 760px)');
  const COARSE = window.matchMedia('(pointer: coarse)');
  const reflow = (el) => void el.offsetWidth;
  /** A motion token from app.css, in ms (reduced motion sets them to ~0, so every JS delay collapses too). */
  function tok(name) {
    const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    const n = parseFloat(v);
    if (!isFinite(n)) return 0;
    return /ms$/.test(v) ? n : /s$/.test(v) ? n * 1000 : n;
  }

  const store = {
    get(k, def) { try { const v = localStorage.getItem(k); return v == null ? def : JSON.parse(v); } catch (e) { return def; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private mode / full */ } },
    raw(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    rawSet(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* ignore */ } },
  };

  const HAPTIC = { link: 8, solve: [10, 40, 10, 40, 30], miss: [28, 40, 28], tap: 5 };
  function haptic(kind) {
    if (!COARSE.matches || !navigator.vibrate) return;
    try { navigator.vibrate(HAPTIC[kind] || kind); } catch (e) { /* not allowed yet */ }
  }

  const LINK_SVG = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.6" aria-hidden="true"><g transform="rotate(-35 12 12)"><rect x="2.5" y="8" width="11" height="8" rx="4"/><rect x="10.5" y="8" width="11" height="8" rx="4"/></g></svg>';
  const X_SVG = '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  const BULB_SVG = '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-3.6 10.8c.7.5 1.1 1.3 1.1 2.2h5c0-.9.4-1.7 1.1-2.2A6 6 0 0 0 12 3Z"/></svg>';
  const CLOSE_SVG = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>';
  const ART_SVG = '<svg class="status-art" viewBox="0 0 80 40" width="64" height="32" aria-hidden="true" fill="none" stroke-width="4.5"><rect x="6" y="8" width="38" height="24" rx="12" stroke="var(--ink)"/><rect x="36" y="8" width="38" height="24" rx="12" stroke="var(--accent)"/></svg>';

  /* ------------------------------------------------------------ theme */
  const btnTheme = $('#btnTheme');
  function currentTheme() { const t = store.raw(THEME_KEY); return t === 'light' || t === 'dark' ? t : 'auto'; }
  function applyTheme(mode) {
    if (mode === 'auto') document.documentElement.removeAttribute('data-theme');
    else document.documentElement.setAttribute('data-theme', mode);
    btnTheme.dataset.mode = mode;
    const label = { auto: 'Theme: automatic (follows your device)', light: 'Theme: light', dark: 'Theme: dark' }[mode];
    btnTheme.setAttribute('aria-label', label + '. Change theme');
    btnTheme.title = label;
  }
  btnTheme.addEventListener('click', () => {
    const next = { auto: 'light', light: 'dark', dark: 'auto' }[currentTheme()];
    store.rawSet(THEME_KEY, next === 'auto' ? null : next);
    const swap = () => applyTheme(next);
    if (document.startViewTransition && !REDUCE.matches) document.startViewTransition(swap); else swap();
    toast(next === 'auto' ? 'Theme follows your device' : cap(next) + ' theme');
  });
  applyTheme(currentTheme());

  /* ------------------------------------------------------------ static copy from the registry */
  (function brand() {
    const t = S.title || 'Chainmates', want = S.accent || 'mates';
    const a = t.length > want.length && t.toLowerCase().endsWith(want) ? want : '';
    const head = t.slice(0, t.length - a.length).toLowerCase();
    $('#brandTitle').innerHTML = esc(head) + (a ? '<span class="brand-accent">' + esc(a) + '</span>' : '');
    $('#brandMode').textContent = S.mode || '';
    $('#brandMode').hidden = !S.mode;
    $('#brand').setAttribute('aria-label', t + (S.mode ? ' ' + S.mode : '') + ", today's puzzle");
    if (S.disclaimer) $('#footDisclaimer').textContent = S.disclaimer;
    if (S.attribution) { const el = $('#footAttribution'); el.textContent = S.attribution.text; el.href = S.attribution.href; }
    document.title = t + (S.mode ? ' ' + S.mode : '') + ' · Daily teammate chain';
    if (sportKeys.length > 1) {
      const box = $('#sportPick');
      box.hidden = false;
      box.innerHTML = '<label class="sr-only" for="sportSel">Mode</label><select id="sportSel">' +
        sportKeys.map((k) => '<option value="' + esc(k) + '"' + (k === sportKey ? ' selected' : '') + '>' + esc(SPORTS[k].mode || SPORTS[k].title) + '</option>').join('') + '</select>';
      $('#sportSel').addEventListener('change', (e) => { location.search = '?sport=' + encodeURIComponent(e.target.value); });
    }
  })();

  /* ------------------------------------------------------------ data */
  let index = null, playersJson = null, puzzlesJson = null, TEAMS = {};
  let today = '', todayN = 0;
  let viewDay = '';         // the Eastern date the current view was routed for (to spot a midnight rollover)
  let game = null;          // { puzzle, mode: 'daily'|'practice', key, state, shownDowns }
  let currentView = null;
  let busy = false;         // an animation that must finish before the next move (undo retract, solve lock-up)

  function fetchJSON(url) {
    return fetch(url, { cache: 'no-cache' }).then((r) => {
      if (!r.ok) throw new Error(url + ' answered HTTP ' + r.status);
      return r.json();
    });
  }
  function refreshToday() {
    today = H.easternDate();
    todayN = puzzlesJson ? H.puzzleNumberForDate(puzzlesJson, today) : 0;
  }
  function load() {
    showStatus('loading');
    Promise.all([fetchJSON(S.data + 'players.json'), fetchJSON(S.data + 'puzzles.json')])
      .then(([pj, zj]) => {
        if (!pj || !Array.isArray(pj.players) || !zj || !Array.isArray(zj.puzzles)) throw new Error('The data files are not in the expected format.');
        if (pj.sport && pj.sport !== sportKey) console.warn('players.json is for', pj.sport, 'but the registry key is', sportKey);
        playersJson = pj; puzzlesJson = zj; TEAMS = pj.teams || {};
        index = H.buildIndex(pj);
        refreshToday();
        route();
        scheduleRollover();
        maybeFirstVisitHelp();
      })
      .catch((err) => { console.error(err); showStatus('error', err); });
  }

  /* ------------------------------------------------------------ formatting */
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  function fmtDate(ymd, long) {
    const [y, m, d] = String(ymd).split('-').map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d));
    return DAYS[dt.getUTCDay()] + ', ' + MONTHS[m - 1] + ' ' + d + (long ? ', ' + y : '');
  }
  const FULL_DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const FULL_MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  function fmtDateLong(ymd) {
    const [y, m, d] = String(ymd).split('-').map(Number);
    return FULL_DAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()] + ', ' + FULL_MONTHS[m - 1] + ' ' + d;
  }
  const years = (p) => (p.first == null ? '' : p.first === p.last ? String(p.first) : p.first + '–' + p.last);
  const metaLine = (p) => [p.pos, years(p)].filter(Boolean).join(' · ');
  const seasonsRange = () => (playersJson && playersJson.seasons ? playersJson.seasons.join('–') : '');

  /** Chip text colour: whichever of white / near-black has the higher WCAG contrast on the team colour (orange and cyan chips need dark ink). */
  function inkFor(hex) {
    const n = parseInt(String(hex).replace('#', ''), 16);
    if (!isFinite(n)) return '#ffffff';
    const lin = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
    const L = 0.2126 * lin((n >> 16) & 255) + 0.7152 * lin((n >> 8) & 255) + 0.0722 * lin(n & 255);
    return 1.05 / (L + 0.05) >= (L + 0.05) / 0.0582 ? '#ffffff' : '#0b1726';
  }
  /** ClubChip: the team code on its primary colour with a thin secondary stripe; ink picked by luminance. */
  function chip(team, season) {
    const t = TEAMS[team] || {};
    const c1 = t.c1 || '#8A94A1', c2 = t.c2 || c1;
    const title = season != null ? H.teamFullName(index, team, season) + ' (' + season + ')' : (t.city ? t.city + ' ' : '') + (t.name || team);
    return '<span class="club" style="--c1:' + esc(c1) + ';--c2:' + esc(c2) + ';--ci:' + inkFor(c1) + '" title="' + esc(title) + '">' + esc(team) + '</span>';
  }
  /** Most recent distinct franchises a player played for, newest first (display only). */
  function recentTeams(p, k) {
    const seen = new Set(), out = [];
    for (const s of p.stints.slice().sort((a, b) => b.season - a.season)) {
      const f = (TEAMS[s.team] && TEAMS[s.team].franchise) || s.team;
      if (seen.has(f)) continue;
      seen.add(f); out.push(s);
      if (out.length >= k) break;
    }
    return out;
  }
  const chipsFor = (p, k) => recentTeams(p, k).map((s) => chip(s.team, s.season)).join('');
  const posAbbr = (p) => esc((p.pos || '').slice(0, 3) || '•');

  /* ------------------------------------------------------------ scoring display (the numbers all come from H.score) */
  /** Fewest links possible for a puzzle, as the core reads it (older data has no `best`: par was the fewest then). */
  const bestOf = (p) => H.newGame(p).best;
  const UNDER_WORDS = ['', 'one', 'two', 'three'];
  /** Display tier of a finished game: birdie (under par, brass), par (solid ink), over, x. */
  const tierOf = (sc) => (!sc.won ? 'x' : sc.over < 0 ? 'birdie' : sc.over === 0 ? 'par' : 'over');
  const underText = (over) => (UNDER_WORDS[-over] || String(-over)) + ' under par';
  const shareOpts = () => ({ url: CONFIG.shareUrl, title: S.title, emoji: S.emoji, miss: S.miss, lost: S.lost });

  /* ------------------------------------------------------------ hints (copy from the sport registry, picked deterministically) */
  /** FNV-1a over "puzzle.position": the same puzzle and chain spot always pick the same line, on any device. */
  function hashPick(n, len, size) {
    let h = 2166136261;
    const key = n + '.' + len;
    for (let i = 0; i < key.length; i++) { h ^= key.charCodeAt(i); h = Math.imul(h, 16777619); }
    return (h >>> 0) % size;
  }
  /** The hint sentence split around its team: { before, after } (old saved hints without `pos` use the `any` line). */
  function hintCopy(h, n, len) {
    const map = S.positions || {}, lines = S.hints || {};
    const group = (h.pos && map[String(h.pos).toUpperCase()]) || 'any';
    const pool = (lines[group] && lines[group].length ? lines[group] : lines.any) || ['Try someone from the {team}.'];
    const t = pool[hashPick(n, len, pool.length)];
    const at = t.indexOf('{team}');
    return at < 0 ? { before: t + ' ', after: '' } : { before: t.slice(0, at), after: t.slice(at + 6) };
  }
  const hintPlain = (h, n, len) => { const c = hintCopy(h, n, len); return c.before + H.teamLabel(index, h.team, h.season) + c.after; };
  /** Words become spans so the reveal can slide them in one after another (transform/opacity only). */
  function hintHTML(h, n, len) {
    const c = hintCopy(h, n, len);
    let i = 0;
    const words = (txt) => txt.split(/(\s+)/).map((w) => (/^\s*$/.test(w) ? w : '<span class="hw" style="--w:' + (i++) + '">' + esc(w) + '</span>')).join('');
    const team = '<span class="hw hw-team" style="--w:' + (i++) + '">' + chip(h.team, h.season) + '<b>' + esc(H.teamLabel(index, h.team, h.season)) + '</b></span>';
    return words(c.before) + team + words(c.after);
  }

  /* ------------------------------------------------------------ views (View Transitions, crossfade fallback) */
  const views = { status: $('#viewStatus'), game: $('#viewGame'), archive: $('#viewArchive'), stats: $('#viewStats') };
  function showView(name) {
    const apply = () => {
      Object.keys(views).forEach((k) => { views[k].hidden = k !== name; });
      $('#btnArchive').toggleAttribute('aria-current', false);
      $('#btnStats').toggleAttribute('aria-current', false);
      if (name === 'archive') $('#btnArchive').setAttribute('aria-current', 'page');
      if (name === 'stats') $('#btnStats').setAttribute('aria-current', 'page');
    };
    const from = currentView;
    currentView = name;
    if (from === name || from === null) return apply();
    if (document.startViewTransition && !REDUCE.matches) { document.startViewTransition(apply); return; }
    apply();
    const v = views[name];
    v.classList.remove('view-in'); reflow(v); v.classList.add('view-in');
  }
  function setKicker(html) { $('#brandKicker').innerHTML = html; }
  const todayKicker = () => '<b>No. ' + todayN + '</b>';

  const skeletonHTML = $('#statusBody').innerHTML;
  function showStatus(kind, arg) {
    const body = $('#statusBody');
    closeAC();
    views.status.setAttribute('aria-busy', String(kind === 'loading'));
    if (kind === 'loading') {
      body.innerHTML = skeletonHTML;
    } else {
      let inner = '';
      if (kind === 'error') {
        inner = '<span class="status-big">Chain snapped</span><strong>We couldn\'t load the puzzle.</strong><span>Check your connection and try again.</span>' +
          (arg && arg.message ? '<code>' + esc(arg.message) + '</code>' : '') + '<button type="button" class="btn btn-ink" id="btnRetry">Try again</button>';
      } else if (kind === 'future') {
        const p = H.puzzleByNumber(puzzlesJson, arg);
        inner = '<span class="status-big">Not available yet</span><strong>Puzzle #' + esc(arg) + ' is still locked.</strong>' +
          '<span>' + (p ? 'It unlocks ' + esc(fmtDate(p.date, true)) + ' at midnight Eastern.' : 'Check back later.') + '</span><a class="btn btn-ink" href="#">Play today\'s puzzle</a>';
      } else if (kind === 'notfound') {
        inner = '<span class="status-big">No such puzzle</span><strong>There is no puzzle #' + esc(arg) + '.</strong><span>Pick one from the archive instead.</span><a class="btn btn-ink" href="#archive">Open the archive</a>';
      } else if (kind === 'nopuzzle') {
        inner = '<span class="status-big">Off day</span><strong>There\'s no puzzle for today.</strong><span>New puzzles are on the way. Older ones are in the archive.</span><a class="btn btn-ink" href="#archive">Open the archive</a>';
      }
      body.innerHTML = '<div class="wrap"><div class="status-card' + (kind === 'error' ? ' error' : '') + '">' + ART_SVG + inner + '</div></div>';
      const r = $('#btnRetry');
      if (r) r.addEventListener('click', load);
    }
    setKicker(todayN > 0 ? todayKicker() : 'Daily');
    showView('status');
  }

  /* ------------------------------------------------------------ routing */
  function parseHash() {
    let h = location.hash.replace(/^#\/?/, '');
    try { h = decodeURIComponent(h); } catch (e) { /* malformed escape like "#%": treat as unknown and show today */ }
    h = h.trim().toLowerCase();
    if (!h || h === 'today') return { view: 'game', n: todayN };
    if (h === 'archive') return { view: 'archive' };
    if (h === 'stats') return { view: 'stats' };
    if (/^\d{1,6}$/.test(h)) return { view: 'game', n: parseInt(h, 10) };
    if (/^p\d{1,6}$/.test(h)) return { view: 'game', n: parseInt(h.slice(1), 10), practice: true };   // "#p42": replay as practice
    return { view: 'game', n: todayN };
  }
  function route() {
    if (!index) return;
    refreshToday();
    viewDay = today;
    closeAC();
    closeAllDialogs();
    toasts.innerHTML = '';
    const r = parseHash();
    if (r.view === 'archive') { renderArchive(); window.scrollTo(0, 0); return; }
    if (r.view === 'stats') { renderStatsPage(); window.scrollTo(0, 0); return; }
    if (r.n > todayN) { showStatus('future', r.n); return; }   // never reveal a future puzzle
    const p = H.puzzleByNumber(puzzlesJson, r.n);
    if (!p) { showStatus(r.n === todayN ? 'nopuzzle' : 'notfound', r.n); return; }
    // A past puzzle you finished as the daily opens on that result; "#p<n>" replays it as practice.
    const daily = store.get(stateKey('daily', p.n), null);
    const finishedDaily = validState(daily, p) && daily.status !== 'playing';
    const mode = p.n === todayN || (finishedDaily && !r.practice) ? 'daily' : 'practice';
    const same = game && game.puzzle.n === p.n && game.mode === mode;
    if (!same) startGame(p, mode); else renderGame();
    showView('game');
    if (!same) window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', route);

  /* ------------------------------------------------------------ game state */
  function validState(st, p) {
    return !!st && typeof st === 'object' && Number.isInteger(st.downs) && st.downs >= 0 && Number.isInteger(st.inc) && Number.isInteger(st.hints) && st.n === p.n && st.start === p.start && st.end === p.end && st.par === p.par && (st.best == null || st.best === bestOf(p)) &&
      Array.isArray(st.chain) && st.chain[0] === p.start && st.chain.every((id) => !!H.player(index, id)) &&
      ['playing', 'won', 'lost'].indexOf(st.status) >= 0 && Array.isArray(st.log) && !!st.hintAt && typeof st.hintAt === 'object';
  }
  const stateKey = (mode, n) => KEY((mode === 'daily' ? 'daily.' : 'practice.') + n);

  function startGame(p, mode) {
    const key = stateKey(mode, p.n);
    let st = store.get(key, null);
    if (!validState(st, p)) st = H.newGame(p);
    game = { puzzle: p, mode, key, state: st, shownDowns: st.downs };
    busy = false;
    if (mode === 'daily' && st.status !== 'playing') recordDaily();
    clearGuess();
    renderHero();
    renderGame();
  }
  const save = () => store.set(game.key, game.state);
  function loadStats() {
    const s = store.get(KEY('stats'), null);
    if (!s || s.v !== 1 || !s.hist || !s.results) return H.newStats();
    return Object.assign(H.newStats(), s, { hist: Object.assign(H.newStats().hist, s.hist) });   // fill any missing counters
  }
  function recordDaily() {
    if (!game || game.mode !== 'daily' || game.state.status === 'playing') return;
    store.set(KEY('stats'), H.recordResult(loadStats(), game.puzzle.n, game.state));
  }
  const lastId = () => game.state.chain[game.state.chain.length - 1];

  /* ------------------------------------------------------------ hero */
  function heroCard(p, label, cls) {
    return '<div class="pcard ' + cls + '">' +
      '<span class="pcard-label">' + esc(label) + '</span>' +
      '<span class="pcard-name">' + esc(p.name) + '</span>' +
      '<span class="chips">' + chipsFor(p, 4) + '</span>' +
      '<span class="pcard-meta">' + esc(metaLine(p)) + '</span></div>';
  }
  /** "Par 3" over "birdie in 2": the badge itself says par can be beaten (old data, where par was the fewest, shows par alone). */
  function parBadge(pz) {
    const best = bestOf(pz), under = best < pz.par;
    return '<span class="par-badge' + (under ? ' has-best' : '') + '" role="img" aria-label="Par ' + pz.par + ' links' + (under ? '. Can be done in ' + best + ', a birdie' : '') + '">' +
      '<span class="pb-par">Par ' + pz.par + '</span>' + (under ? '<span class="pb-best">birdie in ' + best + '</span>' : '') + '</span>';
  }
  function renderHero() {
    const pz = game.puzzle, practice = game.mode === 'practice';
    const a = H.player(index, pz.start), b = H.player(index, pz.end), best = bestOf(pz);
    const hero = $('#hero');
    $('#heroInner').innerHTML =
      '<div class="hero-kicker">' +
        '<span><b>No. ' + pz.n + '</b> · ' + esc(fmtDateLong(pz.date)) + (pz.theme ? ' · ' + esc(pz.theme) : '') + '</span>' +
        '<span class="hero-status' + (practice ? ' practice' : '') + '">' + (practice ? 'Practice replay' : 'Daily puzzle') + '</span>' +
      '</div>' +
      '<div class="matchup">' +
        heroCard(a, 'Start', 'pcard-start') +
        '<div class="gap-link" aria-hidden="true"><span class="knot">' + LINK_SVG + '</span></div>' +
        heroCard(b, 'Finish', 'pcard-end') +
      '</div>' +
      '<div class="hero-foot">' + parBadge(pz) +
        '<h1 class="hero-title" id="heroTitle">' + esc(S.tagline || 'Connect two players through teammates.') + ' ' +
          (practice ? 'This replay doesn\'t count toward your stats.'
            : best < pz.par ? 'The shortest chain takes <b>' + plural(best, 'link') + '</b>. Par gives you one to spare.'
            : 'Fewest links possible: <b>' + pz.par + '</b>.') + '</h1>' +
      '</div>';
    hero.classList.remove('intro'); reflow(hero); hero.classList.add('intro');
    setKicker('<span class="k-word">' + (practice ? 'Practice, ' : '') + '</span><b>No. ' + pz.n + '</b>');
  }

  /* ------------------------------------------------------------ chain */
  function railHTML(k) { return '<span class="rail" aria-hidden="true"><span class="rail-line"></span><span class="rail-knot" style="--k:' + k + '">' + LINK_SVG + '</span></span>'; }
  function connHTML(shared, k, cls) {
    if (!shared || !shared.length) return '';
    const first = shared[0], more = shared.length - 1;
    return '<div class="conn ' + (cls || '') + '">' + railHTML(k) +
      '<span class="reason">' + chip(first.team, first.season) + '<span>Teammates on the <b>' + esc(H.teamLabel(index, first.team, first.season)) + '</b></span></span>' +
      (more > 0 ? '<button type="button" class="more-btn" aria-expanded="false" data-more>+' + more + ' more</button>' : '') +
      (more > 0 ? '<div class="more-list" hidden>' + shared.slice(1).map((s, i) => '<span style="--i:' + i + '">' + chip(s.team, s.season) + esc(H.teamLabel(index, s.team, s.season)) + '</span>').join('') + '</div>' : '') +
      '</div>';
  }
  function nodeHTML(p, kind, tag, k) {
    const dot = kind === 'target' ? '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17.5 19 7"/></svg>'
      : kind === 'ghost' ? '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 21V4M5 4h11l-2 4 2 4H5"/></svg>'
      : kind === 'lost' ? X_SVG
      : posAbbr(p);
    return '<div class="node node-' + kind + '" style="--k:' + k + '">' +
      '<span class="node-dot" aria-hidden="true">' + dot + '</span>' +
      '<span class="node-who"><strong>' + esc(p.name) + '</strong><small>' + (tag ? '<span class="node-tag">' + esc(tag) + '</span>' : '') + esc(metaLine(p)) + '</small></span>' +
      '<span class="chips">' + chipsFor(p, 3) + '</span></div>';
  }

  function renderGame(opts) {
    opts = opts || {};
    const st = game.state, ids = st.chain;
    const won = st.status === 'won', lost = st.status === 'lost', playing = st.status === 'playing';
    const body = won ? ids.slice(0, -1) : ids;
    const sc = H.score(st);

    $('#chain').innerHTML = body.map((id, i) => {
      const enter = opts.animate && i === body.length - 1 && i > 0 && !won ? ' enter' : '';
      return '<li class="step' + enter + '">' + (i > 0 ? connHTML(H.sharedTeams(index, ids[i - 1], id), i) : '') +
        nodeHTML(H.player(index, id), i === 0 ? 'start' : 'mid', i === 0 ? 'Start' : '', i) + '</li>';
    }).join('');
    if (opts.animate && won && body.length > 1) $('#chain').lastElementChild.classList.add('enter');

    $('#chainMeta').innerHTML = '<b>' + plural(sc.links, 'link') + '</b> · Par ' + st.par;

    // slot: the search while playing
    const last = H.player(index, lastId());
    $('#slot').hidden = !playing;
    $('#guess').disabled = !playing;
    if (playing) {
      $('#nextConn').innerHTML = railHTML(body.length) + '<span class="reason"><span>Next: a teammate of <b>' + esc(last.name) + '</b></span></span>';
    } else closeAC();

    // hint for the current position (kept visible while you stay there; the words slide in only when it is first revealed)
    const h = playing ? st.hintAt[lastId()] : null;
    const pill = $('#hintPill');
    pill.hidden = !h;
    if (h) {
      const key = st.n + ':' + lastId();
      if (pill.dataset.key !== key || opts.hintReveal) {
        pill.dataset.key = key;
        pill.classList.toggle('reveal', !!opts.hintReveal);
        pill.innerHTML = '<span class="hint-ic" aria-hidden="true">' + BULB_SVG + '</span>' +
          '<p class="hint-line"><span class="hint-k">Hint.</span> ' + hintHTML(h, st.n, ids.length) + '</p>';
        if (opts.hintReveal) { pill.style.animation = 'none'; reflow(pill); pill.style.animation = ''; }
      }
    } else pill.dataset.key = '';

    // target (the finish marker turns brass only for a birdie)
    $('#chainCard').classList.toggle('is-birdie', won && sc.over < 0);
    const end = H.player(index, st.end), tgt = $('#target');
    tgt.className = 'target' + (opts.animate && won ? ' enter' : '');
    tgt.innerHTML = won
      ? connHTML(H.sharedTeams(index, ids[ids.length - 2], st.end), body.length, 'conn-final') + nodeHTML(end, 'target', 'Finish', body.length)
      : '<div class="conn conn-pending" aria-hidden="true">' + railHTML(body.length) + '</div>' + nodeHTML(end, lost ? 'lost' : 'ghost', 'Finish', body.length);

    // result strip once the game is over
    const strip = $('#resultStrip');
    strip.hidden = playing;
    if (!playing) {
      const tier = tierOf(sc);
      const line = !won ? plural(st.inc, S.miss) + ' · Par ' + st.par
        : 'Solved in ' + plural(sc.links, 'link') + ' · Par ' + st.par + (sc.over < 0 ? ' · ' + underText(sc.over) : sc.links > sc.best ? ' · shortest is ' + sc.best : '');
      strip.innerHTML = '<div><div class="rs-score is-' + tier + '">' + esc(won ? sc.label : S.lost) + '</div>' +
        '<small>' + esc(line) + '</small></div>' +
        '<span class="rs-actions">' +
        (game.mode === 'daily' && game.puzzle.n !== todayN ? '<a class="btn" href="#p' + game.puzzle.n + '">Replay as practice</a>' : '') +
        '<button type="button" class="btn btn-ink" id="btnSeeResults">See results</button></span>';
      $('#btnSeeResults').addEventListener('click', () => openResults());
    }

    renderControls();
    $('#ruleNote').textContent = playing
      ? 'Teammates = ' + (S.rule || 'same team, same season') + ' (' + seasonsRange() + ').'
      : (game.mode === 'practice' ? 'Practice replay: not counted in your stats.' : '');
  }

  function renderControls() {
    const st = game.state, playing = st.status === 'playing', total = H.DOWNS;
    const was = game.shownDowns == null ? st.downs : game.shownDowns;
    let dots = '<span class="downs-label">' + esc(cap(LIVES)) + '</span>';
    for (let i = 0; i < total; i++) {
      const used = i >= st.downs, pop = used && i < was;
      dots += '<span class="down' + (used ? ' used' : '') + (pop ? ' pop' : '') + '"></span>';
    }
    game.shownDowns = st.downs;
    const d = $('#downs');
    d.innerHTML = dots;
    d.classList.toggle('last', playing && st.downs === 1);
    d.setAttribute('aria-label', downsLeft(st.downs) + ' of ' + total);
    $('#btnUndo').disabled = !playing || st.chain.length < 2;
    const cached = playing && !!st.hintAt[lastId()];
    const hb = $('#btnHint');
    hb.disabled = !playing || cached || st.downs <= 1;
    $('#btnHintLabel').textContent = cached ? 'Hint shown' : 'Hint';
    hb.title = !playing ? '' : cached ? 'The hint for this spot is shown under the search box' : st.downs <= 1 ? 'No hints on your last ' + LIFE : 'Costs one ' + LIFE;
  }

  // "+2 more" toggles
  $('#chainCard').addEventListener('click', (e) => {
    const b = e.target.closest('[data-more]');
    if (!b) return;
    const list = b.closest('.conn').querySelector('.more-list');
    const open = b.getAttribute('aria-expanded') !== 'true';
    b.setAttribute('aria-expanded', String(open));
    list.hidden = !open;
  });

  /* ------------------------------------------------------------ guessing */
  function rejectMessage(reason, p) {
    const last = H.player(index, lastId());
    switch (reason) {
      case 'in-chain': return ['Already in your chain', p.name + ' is already linked.'];
      case 'start': return ['That\'s your starting player', 'Pick a teammate of ' + last.name + '.'];
      case 'end': return ['Not yet', p.name + ' never played with ' + last.name + '. Find a link first. No ' + LIFE + ' lost.'];
      case 'unknown': return ['Pick a player from the list', ''];
      default: return ['This game is over', ''];
    }
  }

  function pick(id) {
    if (!game || game.state.status !== 'playing' || busy) return;
    const lastP = H.player(index, lastId());
    const p = H.player(index, id);
    const res = H.guess(index, game.state, id), r = res.result;
    if (r.kind === 'rejected') {
      const [msg, sub] = rejectMessage(r.reason, p || { name: 'That player' });
      toast(msg, 'warn', sub);
      clearGuess(true);
      return;
    }
    game.state = res.state;
    save();
    clearGuess(r.kind === 'link' || r.kind === 'incompletion');

    if (r.kind === 'incompletion' || r.kind === 'lost') {
      missFeedback(p.name);
      haptic('miss');
      const left = r.kind === 'lost' ? 0 : r.downsLeft;
      const msg = (r.kind === 'lost' ? S.lost : cap(S.miss)) + ' — ' + p.name + ' and ' + lastP.name + ' were never teammates';
      toast(msg, 'bad', r.kind === 'lost' ? 'Game over.' : downsLeft(left));   // #toasts is a live region, so no separate announce()
      if (r.kind === 'lost') {
        renderControls();
        busy = true;
        setTimeout(() => { busy = false; renderGame(); finish(false); }, Math.max(tok('--dur-l') * 2, 0));
      } else renderControls();
      return;
    }

    const sh = r.links[0];
    renderGame({ animate: true });
    if (r.kind === 'link') {
      haptic('link');
      announce(p.name + ' added. Teammates on the ' + H.teamLabel(index, sh.team, sh.season) + '. ' + plural(game.state.chain.length - 1, 'link') + ' so far.');
      keepInputInView();
    } else {
      const end = H.player(index, game.state.end), f = r.final[0];
      announce(p.name + ' added, and played with ' + end.name + ' on the ' + H.teamLabel(index, f.team, f.season) + '. Solved!');
      finish(true);
    }
  }

  /** Solve: wait for the final link to land, pulse the chain from start to end (a brass sweep for a birdie), then raise the sheet. */
  function finish(won) {
    recordDaily();
    $('#guess').blur();
    const card = $('#chainCard');
    if (!won) { setTimeout(() => openResults(), tok('--dur-l')); return; }
    haptic('solve');
    busy = true;
    const nodes = game.state.chain.length, step = tok('--lock-step');
    const birdie = H.score(game.state).over < 0;
    const landing = tok('--dur-l') + 140;
    setTimeout(() => {
      card.classList.remove('lock', 'birdie-shine'); reflow(card);
      card.style.setProperty('--shine-delay', Math.round(step * (nodes - 1) * 0.6) + 'ms');
      card.classList.add('lock');
      if (birdie) card.classList.add('birdie-shine');
    }, landing);
    const total = landing + step * nodes + tok('--dur-l') + (birdie ? 380 : 120);
    setTimeout(() => { busy = false; openResults(); }, total);
    setTimeout(() => card.classList.remove('lock', 'birdie-shine'), total + 1400);
  }

  /** Incompletion: the input shakes, a red link snaps off the chain and a down drains. */
  function missFeedback(name) {
    const f = $('#field');
    f.classList.remove('miss'); reflow(f); f.classList.add('miss');
    setTimeout(() => f.classList.remove('miss'), 950);
    const slot = $('#slot'), next = $('#nextConn');
    const old = slot.querySelector('.fail-stub');
    if (old) old.remove();
    const stub = document.createElement('div');
    stub.className = 'fail-stub';
    stub.setAttribute('aria-hidden', 'true');
    stub.innerHTML = '<span class="rail"><span class="rail-line"></span><span class="rail-knot">' + X_SVG + '</span></span><span class="fail-name">' + X_SVG + esc(name) + '</span>';
    stub.style.height = next.offsetHeight + 'px';
    slot.appendChild(stub);
    next.style.transition = 'opacity ' + tok('--dur-s') + 'ms';
    next.style.opacity = '0';
    setTimeout(() => { stub.remove(); next.style.opacity = ''; }, Math.max(1150, 0));
  }

  $('#btnUndo').addEventListener('click', () => {
    if (!game || busy) return;
    const next = H.undo(game.state);
    if (next.chain.length === game.state.chain.length) return;
    const removed = H.player(index, lastId());
    const apply = () => {
      game.state = next; save(); renderGame(); busy = false;
      announce('Removed ' + removed.name + '. Undo is free.');
    };
    const step = $('#chain').lastElementChild;
    if (!step || REDUCE.matches) return apply();
    busy = true;
    step.classList.add('retract');
    haptic('tap');
    setTimeout(apply, tok('--dur-m') + 100);
  });

  /* hint: confirm first (it costs a down), then show it and keep it visible */
  const dlgHint = $('#dlgHint');
  $('#btnHint').addEventListener('click', () => {
    if (!game || game.state.status !== 'playing' || busy) return;
    const st = game.state;
    if (st.hintAt[lastId()]) { $('#hintPill').scrollIntoView({ block: 'nearest', behavior: 'smooth' }); return; }
    if (st.downs <= 1) { toast('No hints on your last ' + LIFE, 'warn'); return; }
    $('#hintDesc').innerHTML = 'A hint reveals <b>a team and a position</b>: who to look for next on a shortest route from <b>' + esc(H.player(index, lastId()).name) +
      '</b>. It costs one ' + esc(LIFE) + ': you\'ll have ' + plural(st.downs - 1, LIFE, LIVES) + ' left.';
    returnFocus.set(dlgHint, $('#btnHint'));
    dlgHint.showModal();
  });
  dlgHint.addEventListener('close', () => {
    if (dlgHint.returnValue !== 'ok' || !game) return;
    const r = H.hint(index, game.state);
    if (r.error) {
      toast(r.error === 'last-down' ? 'No hints on your last ' + LIFE : r.error === 'none' ? 'No hint available here' : 'This game is over', 'warn');
      return;
    }
    game.state = r.state;
    save();
    renderGame({ hintReveal: true });
    toast('Hint revealed', 'good', downsLeft(game.state.downs));
    announce('Hint. ' + hintPlain(r.hint, game.state.n, game.state.chain.length));
  });

  /* ------------------------------------------------------------ autocomplete */
  const input = $('#guess'), acList = $('#acList'), clearBtn = $('#guessClear');
  // acChosen: the player moved the highlight themselves (arrows / mouse), so Enter means that row.
  let acItems = [], acActive = -1, acTimer = 0, acChosen = false;
  const acRows = () => acList.querySelectorAll('.ac-row');

  function clearGuess(keepFocus) {
    clearTimeout(acTimer); acTimer = 0;
    input.value = '';
    clearBtn.hidden = true;
    closeAC();
    if (keepFocus && document.activeElement !== input && !PHONE.matches) input.focus();
  }
  function closeAC() {
    acItems = []; acActive = -1; acChosen = false;
    acList.hidden = true; acList.innerHTML = '';
    input.setAttribute('aria-expanded', 'false');
    input.removeAttribute('aria-activedescendant');
  }
  function highlight(name, q) {
    const t = q.trim().toLowerCase(), i = name.toLowerCase().indexOf(t);
    if (!t || i < 0) return esc(name);
    return esc(name.slice(0, i)) + '<mark>' + esc(name.slice(i, i + t.length)) + '</mark>' + esc(name.slice(i + t.length));
  }
  function runSearch() {
    acTimer = 0;
    if (!game || game.state.status !== 'playing') return closeAC();
    const q = input.value;
    if (!q.trim()) return closeAC();
    acItems = H.search(index, q, { limit: CONFIG.searchLimit, exclude: game.state.chain });
    acActive = acItems.length ? 0 : -1;
    acChosen = false;
    renderAC(q);
  }
  function renderAC(q) {
    const wasOpen = !acList.hidden;
    if (!acItems.length) {
      // a name that only matches players already on the board gets its own explanation instead of "no player"
      const held = H.search(index, q, { limit: 1 })[0];
      const why = held && held.id === game.state.start ? held.name + ' is your starting player.'
        : held && game.state.chain.indexOf(held.id) >= 0 ? held.name + ' is already in your chain.'
        : 'No player by that name played ' + seasonsRange() + '.';
      acList.innerHTML = '<li class="ac-empty" role="option" aria-disabled="true" aria-selected="false">' + esc(why) + '</li>';
    } else {
      const endId = game.state.end;
      acList.innerHTML = '<li class="ac-hl" role="presentation" aria-hidden="true"></li>' + acItems.map((p, i) =>
        '<li class="ac-row" role="option" id="ac-' + i + '" data-id="' + esc(p.id) + '" aria-selected="' + (i === acActive) + '" style="--i:' + (wasOpen ? 0 : i) + '">' +
        '<span><strong>' + highlight(p.name, q) + (p.id === endId ? '<span class="ac-tag">Finish</span>' : '') + '</strong><small>' + esc(metaLine(p)) + '</small></span>' +
        '<span class="chips">' + chipsFor(p, 3) + '</span></li>').join('');
    }
    acList.hidden = false;
    input.setAttribute('aria-expanded', 'true');
    syncActive(true);
    sizeAC();
  }
  /** Move the single highlight to the active row (instant on a fresh list, gliding otherwise). */
  function syncActive(instant) {
    const rows = acRows();
    rows.forEach((el, i) => el.setAttribute('aria-selected', String(i === acActive)));
    const hl = acList.querySelector('.ac-hl'), row = rows[acActive];
    if (hl) {
      if (instant) hl.classList.remove('glide');
      if (row) {
        hl.style.height = row.offsetHeight + 'px';
        hl.style.transform = 'translateY(' + row.offsetTop + 'px)';
        hl.classList.add('on');
      } else hl.classList.remove('on');
      if (instant) { reflow(hl); hl.classList.add('glide'); }
    }
    if (row) {
      input.setAttribute('aria-activedescendant', row.id);
      const top = row.offsetTop, bottom = top + row.offsetHeight;
      if (top < acList.scrollTop) acList.scrollTop = top - 6;
      else if (bottom > acList.scrollTop + acList.clientHeight) acList.scrollTop = bottom - acList.clientHeight + 6;
    } else input.removeAttribute('aria-activedescendant');
  }
  /** Keep the dropdown inside the visible viewport (above an on-screen keyboard); it opens upward when there is more room above the field. */
  function sizeAC() {
    if (acList.hidden) return;
    const vv = window.visualViewport;
    const bottom = vv ? vv.height + vv.offsetTop : window.innerHeight;
    const r = input.getBoundingClientRect();
    const below = Math.floor(bottom - r.bottom - 20), above = Math.floor(r.top - $('#topbar').getBoundingClientRect().bottom - 16);
    const up = below < 180 && above > below;
    acList.classList.toggle('up', up);
    acList.style.maxHeight = Math.max(up ? 120 : 150, Math.min(420, up ? above : below)) + 'px';
  }
  function keepInputInView() {
    if (!PHONE.matches || document.activeElement !== input) return;
    const hb = $('#topbar').getBoundingClientRect().height;
    const y = $('#field').getBoundingClientRect().top + window.scrollY - hb - 12;
    if (Math.abs(window.scrollY - y) > 4) window.scrollTo({ top: y, behavior: REDUCE.matches ? 'auto' : 'smooth' });
    setTimeout(sizeAC, 380);
  }

  input.addEventListener('input', () => {
    clearBtn.hidden = !input.value;
    clearTimeout(acTimer);
    acTimer = setTimeout(runSearch, CONFIG.debounceMs);
  });
  input.addEventListener('focus', () => {
    if (PHONE.matches) setTimeout(keepInputInView, 280);
    if (input.value.trim() && acList.hidden) runSearch();
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (acTimer) { clearTimeout(acTimer); runSearch(); }
      if (!acItems.length) return;
      e.preventDefault();
      const n = acItems.length;
      acActive = e.key === 'ArrowDown' ? (acActive + 1) % n : (acActive - 1 + n) % n;
      acChosen = true;
      syncActive(false);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (acTimer) { clearTimeout(acTimer); runSearch(); }
      // A wrong guess costs a down, so Enter on a half-typed name doesn't guess the top row blindly:
      // it guesses only a row the player highlighted, the only match, or an exact name match.
      const top = acItems[acActive];
      const sure = top && (acChosen || acItems.length === 1 || H.normalize(top.name) === H.normalize(input.value));
      if (sure) pick(top.id);
      else if (top) toast('Tap a name to guess', 'warn');
      else if (input.value.trim()) toast('Pick a player from the list', 'warn');
    } else if (e.key === 'Escape') {
      if (!acList.hidden) { e.preventDefault(); closeAC(); } else if (input.value) { e.preventDefault(); clearGuess(); }
    } else if (e.key === 'Tab') closeAC();
  });
  acList.addEventListener('mousedown', (e) => e.preventDefault()); // keep focus (and the keyboard) on the input
  acList.addEventListener('click', (e) => { const row = e.target.closest('.ac-row'); if (row) pick(row.dataset.id); });
  acList.addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse') return;
    const row = e.target.closest('.ac-row');
    if (!row) return;
    const i = [...acRows()].indexOf(row);
    if (i !== acActive) { acActive = i; acChosen = true; syncActive(false); }
  });
  clearBtn.addEventListener('click', () => { clearGuess(); input.focus(); });
  document.addEventListener('pointerdown', (e) => { if (!e.target.closest('#finder')) closeAC(); });
  function onViewportResize() { sizeAC(); keepInputInView(); }   // the on-screen keyboard opening or closing
  if (window.visualViewport) window.visualViewport.addEventListener('resize', onViewportResize);
  window.addEventListener('resize', onViewportResize);
  document.addEventListener('keydown', (e) => { // "/" focuses the search
    if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.target.closest && e.target.closest('input, textarea, select, [contenteditable]')) return;
    if (document.querySelector('dialog[open]') || currentView !== 'game' || input.disabled) return;
    e.preventDefault();
    input.focus();
  });

  /* ------------------------------------------------------------ toasts / announcer */
  const toasts = $('#toasts');
  function toast(msg, kind, sub) {
    // a modal dialog sits in the top layer, so toasts move inside it while it is open
    const host = document.querySelector('dialog[open]') || document.body;
    if (toasts.parentNode !== host) host.appendChild(toasts);
    const el = document.createElement('div');
    el.className = 'toast ' + (kind || 'warn');
    const ic = kind === 'bad' ? '!' : kind === 'good' ? '✓' : 'i';
    el.innerHTML = '<span class="t-ic" aria-hidden="true">' + ic + '</span><span>' + esc(msg) + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span>';
    toasts.appendChild(el);
    while (toasts.children.length > 2) toasts.firstElementChild.remove();
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), tok('--dur-s') + 40); }, CONFIG.toastMs);
  }
  const announcer = $('#announcer');
  function announce(text) { announcer.textContent = ''; setTimeout(() => { announcer.textContent = text; }, 30); }

  /* ------------------------------------------------------------ sheets: open/close, drag to dismiss with velocity */
  const returnFocus = new WeakMap();
  function openSheet(dlg, from) {
    if (dlg.open) return;
    returnFocus.set(dlg, from || document.activeElement);
    closeAC();
    const panel = dlg.querySelector('.sheet-panel');
    dlg.classList.remove('closing', 'shown', 'dragging');
    panel.style.transform = ''; panel.style.transition = '';
    dlg.querySelector('.sheet-scrim').style.opacity = '';
    dlg.showModal();
    document.documentElement.classList.add('modal-open');
    requestAnimationFrame(() => requestAnimationFrame(() => dlg.classList.add('shown')));
    const head = dlg.querySelector('h2[tabindex="-1"]');   // land on the title, not the close button
    if (head) head.focus({ preventScroll: true });
  }
  function closeSheet(dlg, ms) {
    if (!dlg.open || dlg.classList.contains('closing')) return;
    const d = ms != null ? ms : tok('--dur-m');
    dlg.style.setProperty('--sheet-out', d + 'ms');
    dlg.classList.add('closing');
    dlg.classList.remove('shown');
    dlg.querySelector('.sheet-panel').style.transform = '';
    dlg.querySelector('.sheet-scrim').style.opacity = '';
    setTimeout(() => { dlg.close(); dlg.classList.remove('closing'); dlg.style.removeProperty('--sheet-out'); }, d + 30);
  }
  function closeAllDialogs() { document.querySelectorAll('dialog[open]').forEach((d) => { d.classList.remove('shown', 'closing'); d.close(); }); }

  document.querySelectorAll('dialog').forEach((dlg) => {
    dlg.addEventListener('close', () => {
      if (toasts.parentNode === dlg) document.body.appendChild(toasts);
      if (!document.querySelector('dialog[open]')) document.documentElement.classList.remove('modal-open');
      const f = returnFocus.get(dlg);
      if (f && f.isConnected && typeof f.focus === 'function' && !f.disabled && !(f === input && PHONE.matches)) f.focus({ preventScroll: true });
    });
    if (!dlg.classList.contains('sheet')) return;
    dlg.addEventListener('cancel', (e) => { e.preventDefault(); closeSheet(dlg); });
    dlg.addEventListener('click', (e) => { if (e.target.closest('[data-close]')) closeSheet(dlg); });
    attachDrag(dlg);
  });

  function attachDrag(dlg) {
    const panel = dlg.querySelector('.sheet-panel'), scrim = dlg.querySelector('.sheet-scrim');
    let dragging = false, y0 = 0, lastY = 0, lastT = 0, vy = 0, dy = 0, h = 1, id = null;
    panel.addEventListener('pointerdown', (e) => {
      if (!PHONE.matches || dlg.classList.contains('closing')) return;
      if (!e.target.closest('.sheet-grab, [data-drag]') || e.target.closest('button, a, input')) return;
      const sc = dlg.querySelector('.sheet-scroll');
      if (sc && sc.scrollTop > 2 && !e.target.closest('.sheet-grab')) return;
      dragging = true; id = e.pointerId; y0 = lastY = e.clientY; lastT = performance.now(); vy = 0; dy = 0; h = panel.offsetHeight;
      try { panel.setPointerCapture(id); } catch (err) { /* synthetic events */ }
      dlg.classList.add('dragging');
    });
    panel.addEventListener('pointermove', (e) => {
      if (!dragging || e.pointerId !== id) return;
      const now = performance.now(), raw = e.clientY - y0;
      dy = raw > 0 ? raw : raw * 0.18;                       // resist dragging up
      const inst = (e.clientY - lastY) / Math.max(1, now - lastT);
      vy = 0.75 * inst + 0.25 * vy;                          // px/ms, smoothed
      lastY = e.clientY; lastT = now;
      panel.style.transform = 'translateY(' + dy.toFixed(1) + 'px)';
      scrim.style.opacity = String(Math.max(0, 1 - Math.max(0, dy) / h));
    });
    const end = (e) => {
      if (!dragging || (e && e.pointerId !== id)) return;
      dragging = false;
      dlg.classList.remove('dragging');
      const projected = dy + Math.max(0, vy) * 200;          // where a flick would carry it
      if (projected > h * 0.4 || vy > 0.8) {
        const ms = Math.round(Math.min(360, Math.max(140, (h - dy) / Math.max(vy, 1.4))));
        closeSheet(dlg, ms);
      } else {
        panel.style.transition = 'transform ' + tok('--dur-l') + 'ms var(--ease-spring)';
        panel.style.transform = '';
        scrim.style.opacity = '';
        setTimeout(() => { panel.style.transition = ''; }, tok('--dur-l') + 20);
      }
    };
    panel.addEventListener('pointerup', end);
    panel.addEventListener('pointercancel', end);
  }

  /* ------------------------------------------------------------ results sheet */
  const sheet = $('#sheet');
  let countdownTimer = 0, rollAt = 0;

  /** The next moment the Eastern calendar date changes (binary search over H.easternDate; no tz maths here). */
  function nextRollover() {
    const now = Date.now(), d0 = H.easternDate(new Date(now));
    let lo = now, hi = now + 26 * 3600e3;
    if (H.easternDate(new Date(hi)) === d0) return hi;
    while (hi - lo > 500) { const mid = Math.floor((lo + hi) / 2); if (H.easternDate(new Date(mid)) === d0) lo = mid; else hi = mid; }
    return hi;
  }
  function fmtCountdown(ms) {
    const s = Math.max(0, Math.floor(ms / 1000)), p2 = (n) => (n < 10 ? '0' : '') + n;
    return p2(Math.floor(s / 3600)) + ':' + p2(Math.floor((s % 3600) / 60)) + ':' + p2(s % 60);
  }
  const newPuzzleHTML = () => '<span>A new puzzle is out</span><a class="btn btn-primary" href="#" data-play>Play now</a>';
  function tickCountdown() {
    const el = $('#countdown');
    if (!el) return;
    const left = rollAt - Date.now();
    if (left <= 0) {
      el.closest('.countdown').innerHTML = newPuzzleHTML();
      clearInterval(countdownTimer);
      refreshToday();
      return;
    }
    el.textContent = fmtCountdown(left);
    el.setAttribute('datetime', 'PT' + Math.floor(left / 1000) + 'S');
  }

  function miniChain(ids, links, endId, brass) {
    let html = '';
    ids.forEach((id, i) => {
      const p = H.player(index, id);
      if (i > 0) { const l = links[i - 1]; html += '<li class="ml-link">' + chip(l.team, l.season) + 'Teammates on the ' + esc(H.teamLabel(index, l.team, l.season)) + '</li>'; }
      const cls = i === 0 ? 's' : id === endId ? 'e' + (brass ? ' brass' : '') : '';
      html += '<li><span class="ml-dot ' + cls + '" aria-hidden="true">' + posAbbr(p) + '</span><span class="ml-name">' + esc(p.name) + '</span><span class="chips">' + chipsFor(p, 2) + '</span></li>';
    });
    return html;
  }

  function statTiles(stats) {
    const ds = H.displayStreaks(stats, todayN);
    const pct = stats.played ? Math.round((stats.won / stats.played) * 100) : 0;
    // The par streak counts par or better: in golf terms, bogey-free.
    const t = [[stats.played, 'Played'], [pct, 'Win %'], [ds.cur, 'Streak'], [ds.max, 'Best streak'],
      [ds.parCur, 'Bogey-free streak', 'Days in a row at par or better'], [ds.parMax, 'Best bogey-free', 'Longest run at par or better']];
    return '<div class="tiles">' + t.map((x, i) => '<div class="tile" style="--i:' + i + '"' + (x[2] ? ' title="' + esc(x[2]) + '"' : '') + '><b data-count="' + x[0] + '">' + x[0] + '</b><small>' + x[1] +
      (x[2] ? '<span class="sr-only"> (' + esc(x[2].toLowerCase()) + ')</span>' : '') + '</small></div>').join('') + '</div>';
  }
  /** Numbers tick up from 0 (text only; no layout work beyond the glyphs). */
  function animateCounts(root, delay) {
    if (REDUCE.matches) return;
    root.querySelectorAll('[data-count]').forEach((el, i) => {
      const to = Number(el.dataset.count);
      if (!(to > 0)) return;
      el.textContent = '0';
      const dur = 600 + Math.min(300, to * 8), wait = (delay || 0) + i * tok('--stagger');
      setTimeout(() => { el.textContent = String(to); }, wait + dur + 250);   // always land on the true value
      let t0 = null;
      const step = (now) => {             // rAF timestamps only, so one clock drives the whole count
        if (t0 === null) t0 = now + wait;
        const k = Math.min(1, Math.max(0, (now - t0) / dur));
        el.textContent = String(Math.round(to * (1 - Math.pow(1 - k, 3))));
        if (k < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    });
  }

  function openResults() {
    if (!game || game.state.status === 'playing') return;
    refreshToday();
    const stale = game.mode === 'daily' && game.puzzle.n < todayN;   // finished after midnight: the next puzzle is already out
    const pz = game.puzzle, st = game.state, sc = H.score(st), won = st.status === 'won', practice = game.mode === 'practice';
    const share = H.shareText(pz, st, shareOpts());
    const myLinks = [];
    for (let i = 1; i < st.chain.length; i++) myLinks.push(H.sharedTeams(index, st.chain[i - 1], st.chain[i])[0]);
    const optLinks = (pz.links || []).map((l) => ({ team: l[0], season: l[1] }));
    const tier = tierOf(sc), best = sc.best, optimal = pz.chain.length - 1;
    // Zero counts are left out: "3 links · Par 3" reads better than "· 0 incompletions · 0 hints".
    const sub = [plural(sc.links, 'link') + ' · Par ' + pz.par, won && sc.links > best ? 'shortest ' + best : '', st.inc ? plural(st.inc, S.miss) : '', st.hints ? plural(st.hints, 'hint') : ''].filter(Boolean).join(' · ');
    const headline = !won ? esc(S.lost)
      : sc.over < 0 ? sc.label + '! The shortest chain there is.'
      : sc.over === 0 ? (best < pz.par ? 'Solved at par. The birdie was ' + plural(best, 'link') + '.' : 'Right on par, the shortest chain there is.')
      : 'Solved, ' + sc.over + ' over par';
    let sec = 0;
    const secOpen = (id) => '<section class="sheet-sec" style="--i:' + (sec++) + '" aria-labelledby="' + id + '">';

    $('#sheetScroll').innerHTML =
      '<header class="sheet-hero" data-drag>' +
        '<button type="button" class="close-btn" data-close aria-label="Close results">' + CLOSE_SVG + '</button>' +
        '<span class="kicker">' + esc(S.title) + ' <b>No. ' + pz.n + '</b> · ' + esc(fmtDate(pz.date)) + (practice ? ' · Practice' : '') + '</span>' +
        '<div class="score-big is-' + tier + '" aria-hidden="true">' + esc(sc.label) + '</div>' +
        '<h2 id="sheetTitle" tabindex="-1">' + headline + '</h2>' +
        '<p>' + esc(won ? sub : [plural(st.inc, S.miss), st.hints ? plural(st.hints, 'hint') : '', 'Par ' + pz.par].filter(Boolean).join(' · ')) + '</p>' +
      '</header>' +
      '<div class="sheet-body">' +
        secOpen('shTitle') + '<h3 id="shTitle">Share <span>No spoilers</span></h3>' +
          '<pre class="share-preview" id="sharePreview">' + esc(share) + '</pre>' +
          '<div class="share-btns">' +
            (navigator.share ? '<button type="button" class="btn btn-primary btn-lg" id="btnShare"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 15V3M7 8l5-5 5 5"/><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/></svg>Share</button>' : '') +
            '<button type="button" class="btn ' + (navigator.share ? '' : 'btn-primary ') + 'btn-lg" id="btnCopy"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg><span>Copy result</span></button>' +
          '</div>' +
        '</section>' +
        (practice ? '<p class="practice-note sheet-sec" style="--i:' + (sec++) + '">Practice replay of puzzle #' + pz.n + '. It doesn\'t count toward your stats or streaks.</p>'
          : secOpen('stTitle') + '<h3 id="stTitle">Your stats</h3>' + statTiles(loadStats()) + '</section>') +
        secOpen('myTitle') + '<h3 id="myTitle">Your chain <span>' + (sc.links ? plural(sc.links, 'link') : 'No links') + '</span></h3>' +
          '<ol class="mini-list">' + miniChain(st.chain, myLinks, st.end, tier === 'birdie') +
          (won ? '' : '<li class="ml-link miss">' + esc(S.lost) + '</li><li><span class="ml-dot e" aria-hidden="true">' + posAbbr(H.player(index, st.end)) + '</span><span class="ml-name">' + esc(H.player(index, st.end).name) + '</span></li>') +
          '</ol></section>' +
        secOpen('opTitle') + '<h3 id="opTitle">One optimal chain <span>' + plural(optimal, 'link') + '</span></h3>' +
          '<ol class="mini-list">' + miniChain(pz.chain, optLinks, pz.end, optimal < pz.par) + '</ol>' +
          '<p class="optimal-note">' + (pz.optimal === 1 ? 'Only 1 optimal chain exists' : esc(Number(pz.optimal).toLocaleString('en-US')) + ' optimal chains exist') +
            (optimal < pz.par ? (pz.optimal === 1 ? '. It\'s the only birdie.' : ', and each one is a birdie.') : '.') + '</p>' +
        '</section>' +
        '<div class="countdown sheet-sec" style="--i:' + (sec++) + '">' + (stale ? newPuzzleHTML() : '<span>Next puzzle in</span><time id="countdown">--:--:--</time>') + '</div>' +
      '</div>';

    $('#btnCopy').addEventListener('click', () => copyText(share));
    const sb = $('#btnShare');
    if (sb) sb.addEventListener('click', () => { navigator.share({ text: share }).catch((err) => { if (err && err.name !== 'AbortError') copyText(share); }); });
    clearInterval(countdownTimer);
    if (!stale) {
      rollAt = nextRollover();
      tickCountdown();
      countdownTimer = setInterval(tickCountdown, 1000);
    }
    const from = document.activeElement && document.activeElement !== document.body ? document.activeElement : null;
    openSheet(sheet, from || $('#btnSeeResults'));
    $('#sheetScroll').scrollTop = 0;
    $('#sheetTitle').focus({ preventScroll: true });
    animateCounts($('#sheetScroll'), 420);
  }
  sheet.addEventListener('close', () => clearInterval(countdownTimer));
  sheet.addEventListener('click', (e) => {   // "Play now": go to today's puzzle even when the URL already reads "#"
    if (!e.target.closest('[data-play]')) return;
    e.preventDefault();
    if (location.hash && location.hash !== '#') location.hash = ''; else route();
  });

  function copyText(text) {
    const ok = () => {
      toast('Copied to clipboard', 'good', 'Paste it anywhere.');
      const b = $('#btnCopy span');
      if (b) { b.textContent = 'Copied!'; setTimeout(() => { if (b.isConnected) b.textContent = 'Copy result'; }, 1800); }
    };
    const fallback = () => {
      const ta = document.createElement('textarea');
      ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
      (sheet.open ? sheet : document.body).appendChild(ta);
      ta.select();
      let done = false;
      try { done = document.execCommand('copy'); } catch (e) { done = false; }
      ta.remove();
      if (done) ok(); else toast('Couldn\'t copy', 'warn', 'Select the text above and copy it.');
    };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(ok, fallback); else fallback();
  }

  /* ------------------------------------------------------------ stats page */
  function renderStatsPage() {
    const stats = loadStats(), total = stats.played;
    const buckets = [['-1', 'Birdie'], ['0', 'Par'], ['1', '+1'], ['2', '+2'], ['3', '+3'], ['X', 'X']];
    const max = Math.max(1, ...buckets.map((b) => stats.hist[b[0]] || 0));
    const todayState = store.get(stateKey('daily', todayN), null);
    let mark = null;
    if (todayState && todayState.status !== 'playing' && stats.results[todayN]) { const sc = H.score(todayState); mark = sc.won ? String(Math.max(-1, Math.min(3, sc.over))) : 'X'; }
    $('#statsBody').innerHTML =
      '<section class="card page-card" aria-labelledby="sumTitle"><h2 id="sumTitle">Summary</h2>' + statTiles(stats) + '</section>' +
      '<section class="card page-card" aria-labelledby="histTitle"><h2 id="histTitle">Strokes vs par <small>' + plural(total, 'daily game') + '</small></h2>' +
        (total ? '<ol class="hist">' + buckets.map((b, i) => {
          const c = stats.hist[b[0]] || 0, on = mark ? mark === b[0] : c > 0 && c === max;
          return '<li class="' + (b[0] === '-1' ? 'is-birdie ' : b[0] === '0' ? 'is-par ' : '') + (on ? 'on' : '') + '"><span class="h-lab">' + b[1] + (b[0] === '3' ? '<span class="sr-only"> or more</span>' : b[0] === '-1' ? '<span class="sr-only"> or better</span>' : '') + '</span>' +
            '<span class="h-track"><span class="h-bar" style="--w:' + Math.round((c / max) * 100) + ';--i:' + i + '"></span><span class="h-num" style="--w:' + Math.round((c / max) * 100) + ';--i:' + i + '">' + c + '</span></span></li>';
        }).join('') + '</ol>' : '<p class="empty-note">Finish a daily puzzle to start your record.</p>') +
      '</section>' +
      '<div class="back-row"><a class="btn btn-ink" href="#">Back to today\'s puzzle</a></div>';
    setKicker(todayKicker());
    showView('stats');
    animateCounts($('#statsBody'), 80);
  }

  /* ------------------------------------------------------------ archive */
  function badgeFor(st) {
    if (!st) return null;
    if (st.status === 'playing') return st.chain.length > 1 || st.inc || st.hints ? { cls: 'prog', text: 'In progress' } : null;
    const sc = H.score(st);
    return { cls: tierOf(sc), text: sc.label };
  }
  function renderArchive() {
    const last = Math.min(todayN, puzzlesJson.puzzles.length);
    let html = '';
    for (let n = last, i = 0; n >= 1; n--, i++) {
      const p = H.puzzleByNumber(puzzlesJson, n);
      if (!p) continue;
      const daily = store.get(stateKey('daily', n), null), practice = store.get(stateKey('practice', n), null);
      const vd = validState(daily, p) ? daily : null, vp = validState(practice, p) ? practice : null;
      const isToday = n === todayN;
      // An unfinished daily from an earlier day can't be resumed (the archive opens a fresh practice replay), so it shows no badge.
      let b = isToday || (vd && vd.status !== 'playing') ? badgeFor(vd) : null, note = '';
      if (vd && vd.status !== 'playing') note = 'Daily';
      else if (!isToday && badgeFor(vp)) { b = badgeFor(vp); note = 'Practice'; }
      if (!b) b = { cls: 'play', text: 'Play →' };
      html += '<li><a class="arch-row' + (isToday ? ' today' : '') + '" href="#' + n + '" style="--i:' + i + '" aria-label="Puzzle ' + n + ', ' + esc(fmtDate(p.date, true)) + ', par ' + p.par + (p.theme ? ', ' + esc(p.theme) : '') + '. ' + esc(b.text) + (note ? ' (' + note + ')' : '') + '">' +
        '<span class="arch-n"><small>No.</small>' + n + '</span>' +
        '<span class="arch-who"><strong>' + esc(fmtDate(p.date)) + (isToday ? ' <span class="today-tag">· Today</span>' : '') + '</strong><small>Par ' + p.par + (p.theme ? ' · ' + esc(p.theme) : '') + '</small></span>' +
        '<span class="badge-wrap"><span class="badge ' + b.cls + '">' + esc(b.text) + '</span>' + (note ? '<small>' + note + '</small>' : '') + '</span></a></li>';
    }
    $('#archiveList').innerHTML = html || '<li class="empty-note">No puzzles yet.</li>';
    setKicker(todayKicker());
    showView('archive');
  }

  /* ------------------------------------------------------------ how to play / about */
  const dlgHelp = $('#dlgHelp'), dlgAbout = $('#dlgAbout');
  function helpHTML() {
    return '<p class="lede">' + esc(S.tagline) + ' A new puzzle every day at midnight Eastern.</p>' +
      '<ul class="rules">' +
        '<li style="--i:0"><span class="runin">The chain.</span>You get a Start and a Finish player. Add players one at a time; each must have been a <strong>teammate</strong> of the one before (' + esc(S.rule || 'same team, same season') + '). Reach a teammate of the Finish player and you\'ve solved it.</li>' +
        '<li style="--i:1"><span class="runin">Par.</span>The fewest links possible, plus one to spare. Find the shortest chain for a <strong>birdie</strong>; every link over par is +1.</li>' +
        '<li style="--i:2"><span class="runin">' + esc(cap(LIVES)) + '.</span>You have ' + H.DOWNS + '. A guess that wasn\'t a teammate is an ' + esc(S.miss) + ' and costs one. Lose them all and it\'s a ' + esc(S.lost.toLowerCase()) + '.</li>' +
        '<li style="--i:3"><span class="runin">Help.</span>Undo is free. A hint reveals a team and a position for your next link, and costs a ' + esc(LIFE) + '.</li>' +
      '</ul>' +
      '<p class="fine">Seasons ' + esc(seasonsRange()) + ', regular season and playoffs. Your progress and stats stay on this device.</p>' +
      '<button type="button" class="btn btn-ink btn-wide btn-lg" data-close>Start playing</button>';
  }
  function aboutHTML() {
    const built = playersJson && playersJson.built ? fmtDate(playersJson.built, true) : 'unknown';
    const att = S.attribution || { text: 'Player data from nflverse (CC-BY 4.0)', href: 'https://github.com/nflverse' };
    return '<p><strong>' + esc(S.title) + '</strong> is a free daily teammate-chain puzzle. ' + esc(S.tagline) + (S.mode ? ' You\'re playing the ' + esc(S.mode) + ' mode.' : '') + '</p>' +
      '<p>' + esc(S.disclaimer) + '</p>' +
      '<p><a href="' + esc(att.href) + '" rel="noopener">' + esc(att.text) + '</a>. Teams appear as plain colour chips with their abbreviation; there are no logos or photos.</p>' +
      '<p>No accounts, no ads, no tracking. Your games and stats are kept only in this browser\'s local storage.</p>' +
      '<p class="fine">Data built ' + esc(built) + (seasonsRange() ? ' · seasons ' + esc(seasonsRange()) : '') + (index ? ' · ' + esc(index.n.toLocaleString('en-US')) + ' players' : '') + '</p>' +
      '<div class="legal-links"><a href="privacy.html">Privacy</a><a href="terms.html">Terms</a><a href="support.html">Support</a></div>';
  }
  $('#btnHelp').addEventListener('click', (e) => { $('#helpBody').innerHTML = helpHTML(); openSheet(dlgHelp, e.currentTarget); });
  $('#btnAbout').addEventListener('click', (e) => { $('#aboutBody').innerHTML = aboutHTML(); openSheet(dlgAbout, e.currentTarget); });
  dlgHelp.addEventListener('close', () => store.set(KEY('seen-help'), 1));
  function maybeFirstVisitHelp() {
    if (store.get(KEY('seen-help'), 0) || document.querySelector('dialog[open]')) return;
    $('#helpBody').innerHTML = helpHTML();
    openSheet(dlgHelp, input);
  }

  /* ------------------------------------------------------------ misc chrome */
  $('#brand').addEventListener('click', (e) => {
    if (!location.hash || location.hash === '#') { e.preventDefault(); route(); window.scrollTo({ top: 0, behavior: REDUCE.matches ? 'auto' : 'smooth' }); }
  });
  let scrollRaf = 0;
  window.addEventListener('scroll', () => {
    if (scrollRaf) return;
    scrollRaf = requestAnimationFrame(() => { scrollRaf = 0; $('#topbar').classList.toggle('scrolled', window.scrollY > 4); });
  }, { passive: true });
  /** The Eastern date changed while the page was open (timer at midnight, or the tab coming back). */
  function onNewDay() {
    if (!index) return;
    refreshToday();
    if (today === viewDay) return;
    if (document.querySelector('dialog[open]')) return;   // an open sheet carries its own "Play now"
    if (currentView === 'archive' || currentView === 'stats') { route(); return; }   // "Today" tag and streaks move on
    if (location.hash && location.hash !== '#' && parseHash().n !== todayN) return;   // a specific older puzzle: leave it alone
    const st = game && game.state, midGame = game && game.mode === 'daily' && st.status === 'playing' && (st.chain.length > 1 || st.inc || st.hints);
    if (midGame && game.puzzle.n < todayN) { toast('A new puzzle is ready', 'good', 'Finish this one, then tap the logo for No. ' + todayN + '.'); viewDay = today; return; }
    route();
    toast('A new puzzle is ready', 'good');
  }
  let rolloverTimer = 0;
  function scheduleRollover() {
    clearTimeout(rolloverTimer);
    rolloverTimer = setTimeout(() => { onNewDay(); scheduleRollover(); }, Math.min(Math.max(nextRollover() - Date.now(), 0) + 1500, 2147483000));
  }
  document.addEventListener('visibilitychange', () => { if (!document.hidden) onNewDay(); });

  // read-only test hook: lets automated checks see the current state
  window.__chainmates = { get state() { return game && JSON.parse(JSON.stringify(game.state)); }, get mode() { return game && game.mode; } };

  load();
})();
