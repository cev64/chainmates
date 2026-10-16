/* Chainmates web client. Vanilla JS, no build step.
 * Every game rule (guessing, downs, hints, undo, scoring, dates, search, share text, stats) comes from
 * core/handoff-core.js (globalThis.HandoffCore). This file only renders, routes and stores. */
(function () {
  'use strict';

  const H = window.HandoffCore;
  const SPORTS = window.CHAINMATES_SPORTS || {};

  /* ------------------------------------------------------------ config */
  const CONFIG = {
    shareUrl: 'cev64.github.io/handoff/', // base URL in the share text; "#n" is appended by the core
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

  /* ------------------------------------------------------------ tiny helpers */
  const $ = (sel, root) => (root || document).querySelector(sel);
  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ESC[c]);
  const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
  const plural = (n, one, many) => n + ' ' + (n === 1 ? one : many || one + 's');
  const REDUCE = window.matchMedia('(prefers-reduced-motion: reduce)');
  const PHONE = window.matchMedia('(max-width: 760px)');
  const COARSE = window.matchMedia('(pointer: coarse)');

  const store = {
    get(k, def) {
      try { const v = localStorage.getItem(k); return v == null ? def : JSON.parse(v); } catch (e) { return def; }
    },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private mode / full */ } },
    raw(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    rawSet(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* ignore */ } },
  };

  function haptic(ms) {
    if (!COARSE.matches || !navigator.vibrate) return;
    try { navigator.vibrate(ms); } catch (e) { /* not allowed yet */ }
  }

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
    applyTheme(next);
    toast(next === 'auto' ? 'Theme follows your device' : cap(next) + ' theme', 'warn');
  });
  applyTheme(currentTheme());

  /* ------------------------------------------------------------ static copy from the registry */
  function brandHTML() {
    const t = S.title || 'Chainmates';
    const want = S.accent || 'mates';
    const a = t.length > want.length && t.endsWith(want) ? want : '';
    return esc(t.slice(0, t.length - a.length)) + (a ? '<span class="brand-accent">' + esc(a) + '</span>' : '');
  }
  $('#brandTitle').innerHTML = brandHTML();
  $('#brandMode').textContent = S.mode || '';
  $('#brandMode').hidden = !S.mode;
  $('#brand').setAttribute('aria-label', (S.title || 'Chainmates') + (S.mode ? ' ' + S.mode : '') + ", today's puzzle");
  if (S.disclaimer) $('#footDisclaimer').textContent = S.disclaimer;
  if (S.attribution) { const a = $('#footAttribution'); a.textContent = S.attribution.text; a.href = S.attribution.href; }
  document.title = (S.title || 'Chainmates') + (S.mode ? ' ' + S.mode : '') + ' · Daily teammate chain';
  if (sportKeys.length > 1) {
    const box = $('#sportPick');
    box.hidden = false;
    box.innerHTML = '<label class="sr-only" for="sportSel">Sport</label><select id="sportSel">' +
      sportKeys.map((k) => '<option value="' + esc(k) + '"' + (k === sportKey ? ' selected' : '') + '>' + esc((SPORTS[k].mode || SPORTS[k].title)) + '</option>').join('') + '</select>';
    $('#sportSel').addEventListener('change', (e) => { location.search = '?sport=' + encodeURIComponent(e.target.value); });
  }

  /* ------------------------------------------------------------ data */
  let index = null, playersJson = null, puzzlesJson = null, TEAMS = {};
  let today = '', todayN = 0;
  let game = null;         // { puzzle, mode: 'daily'|'practice', key, state }
  let currentView = null;

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
  function years(p) { return p.first == null ? '' : p.first === p.last ? String(p.first) : p.first + '–' + p.last; }
  function metaLine(p) { return [p.pos, years(p)].filter(Boolean).join(' · '); }

  function inkFor(hex) {
    const n = parseInt(String(hex).replace('#', ''), 16);
    if (!isFinite(n)) return '#ffffff';
    const lum = (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
    return lum > 0.62 ? '#0b1726' : '#ffffff';
  }
  /** ClubChip: the team code on its primary colour, a thin secondary stripe, ink picked by luminance. */
  function chip(team, season) {
    const t = TEAMS[team] || {};
    const c1 = t.c1 || '#8A94A1', c2 = t.c2 || c1;
    const title = season != null ? H.teamFullName(index, team, season) + ' (' + season + ')' : (t.city ? t.city + ' ' : '') + (t.name || team);
    return '<span class="club" style="--c1:' + esc(c1) + ';--c2:' + esc(c2) + ';--ci:' + inkFor(c1) + '" title="' + esc(title) + '">' + esc(team) + '</span>';
  }
  /** Most recent distinct franchises a player played for, newest first (display only). */
  function recentTeams(p, k) {
    const seen = new Set(), out = [];
    const st = p.stints.slice().sort((a, b) => b.season - a.season);
    for (const s of st) {
      const f = (TEAMS[s.team] && TEAMS[s.team].franchise) || s.team;
      if (seen.has(f)) continue;
      seen.add(f); out.push(s);
      if (out.length >= k) break;
    }
    return out;
  }
  const chipsFor = (p, k) => recentTeams(p, k).map((s) => chip(s.team, s.season)).join('');
  const posAbbr = (p) => esc((p.pos || '').slice(0, 3) || '•');

  /* ------------------------------------------------------------ views */
  const views = { status: $('#viewStatus'), game: $('#viewGame'), archive: $('#viewArchive'), stats: $('#viewStats') };
  function showView(name) {
    if (currentView !== name) {
      Object.keys(views).forEach((k) => { views[k].hidden = k !== name; });
      currentView = name;
    }
    $('#btnArchive').toggleAttribute('aria-current', false);
    $('#btnStats').toggleAttribute('aria-current', false);
    if (name === 'archive') $('#btnArchive').setAttribute('aria-current', 'page');
    if (name === 'stats') $('#btnStats').setAttribute('aria-current', 'page');
  }
  function setKicker(html) { $('#brandKicker').innerHTML = html; }
  const todayKicker = () => '<span class="k-word">Puzzle </span><b>#' + todayN + '</b>';

  function showStatus(kind, arg) {
    const card = $('#statusCard');
    closeAC();
    card.className = 'status-card' + (kind === 'error' ? ' error' : '');
    if (kind === 'loading') {
      card.innerHTML = '<div class="spinner" aria-hidden="true"></div><strong>Loading today\'s puzzle…</strong><span>Fetching the player list.</span>';
    } else if (kind === 'error') {
      card.innerHTML = '<span class="status-big">Fumble</span><strong>We couldn\'t load the puzzle.</strong>' +
        '<span>Check your connection and try again.</span>' + (arg && arg.message ? '<code>' + esc(arg.message) + '</code>' : '') +
        '<button type="button" class="btn btn-primary" id="btnRetry">Try again</button>';
      $('#btnRetry').addEventListener('click', load);
    } else if (kind === 'future') {
      const p = H.puzzleByNumber(puzzlesJson, arg);
      card.innerHTML = '<span class="status-big">Not available yet</span><strong>Puzzle #' + esc(arg) + ' hasn\'t kicked off.</strong>' +
        '<span>' + (p ? 'It unlocks ' + esc(fmtDate(p.date)) + ' at midnight Eastern.' : 'Check back later.') + '</span>' +
        '<a class="btn btn-primary" href="#">Play today\'s puzzle</a>';
    } else if (kind === 'notfound') {
      card.innerHTML = '<span class="status-big">No such puzzle</span><strong>There is no puzzle #' + esc(arg) + '.</strong>' +
        '<span>Pick one from the archive instead.</span><a class="btn btn-primary" href="#archive">Open the archive</a>';
    } else if (kind === 'nopuzzle') {
      card.innerHTML = '<span class="status-big">Bye week</span><strong>There\'s no puzzle for today.</strong>' +
        '<span>New puzzles are on the way. Older ones are in the archive.</span><a class="btn btn-primary" href="#archive">Open the archive</a>';
    }
    setKicker(todayN > 0 ? todayKicker() : 'Daily');
    showView('status');
  }

  /* ------------------------------------------------------------ routing */
  function parseHash() {
    const h = decodeURIComponent(location.hash.replace(/^#\/?/, '')).trim().toLowerCase();
    if (!h || h === 'today') return { view: 'game', n: todayN };
    if (h === 'archive') return { view: 'archive' };
    if (h === 'stats') return { view: 'stats' };
    if (/^\d{1,6}$/.test(h)) return { view: 'game', n: parseInt(h, 10) };
    return { view: 'game', n: todayN };
  }

  function route() {
    if (!index) return;
    refreshToday();
    closeAC();
    closeAllDialogs();
    toasts.innerHTML = '';
    const r = parseHash();
    if (r.view === 'archive') { renderArchive(); window.scrollTo(0, 0); return; }
    if (r.view === 'stats') { renderStatsPage(); window.scrollTo(0, 0); return; }
    if (r.n > todayN) { showStatus('future', r.n); return; }   // never reveal a future puzzle
    const p = H.puzzleByNumber(puzzlesJson, r.n);
    if (!p) { showStatus(r.n === todayN ? 'nopuzzle' : 'notfound', r.n); return; }
    const same = game && game.puzzle.n === p.n && game.mode === (p.n === todayN ? 'daily' : 'practice');
    if (!same) startGame(p, p.n === todayN ? 'daily' : 'practice');
    else { renderGame(); }
    showView('game');
    if (!same) window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', route);

  /* ------------------------------------------------------------ game state */
  function validState(st, p) {
    return st && typeof st === 'object' && st.n === p.n && st.start === p.start && st.end === p.end && st.par === p.par &&
      Array.isArray(st.chain) && st.chain[0] === p.start && st.chain.every((id) => !!H.player(index, id)) &&
      ['playing', 'won', 'lost'].indexOf(st.status) >= 0 && Array.isArray(st.log) && st.hintAt && typeof st.hintAt === 'object';
  }
  const stateKey = (mode, n) => KEY((mode === 'daily' ? 'daily.' : 'practice.') + n);

  function startGame(p, mode) {
    const key = stateKey(mode, p.n);
    let st = store.get(key, null);
    if (!validState(st, p)) st = H.newGame(p);
    game = { puzzle: p, mode, key, state: st };
    if (mode === 'daily' && st.status !== 'playing') recordDaily();
    clearGuess();
    renderHero();
    renderGame();
  }
  function save() { store.set(game.key, game.state); }

  function loadStats() {
    const s = store.get(KEY('stats'), null);
    return s && s.v === 1 && s.hist && s.results ? s : H.newStats();
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
  function renderHero() {
    const pz = game.puzzle;
    const a = H.player(index, pz.start), b = H.player(index, pz.end);
    const practice = game.mode === 'practice';
    $('#heroInner').innerHTML =
      '<div class="hero-kicker">' +
        '<span class="kicker"><b>#' + pz.n + '</b> · ' + esc(fmtDate(pz.date)) + '</span>' +
        (practice ? '<span class="pill pill-blue"><span class="pill-dot"></span>Practice</span>' : '<span class="pill pill-gold"><span class="pill-dot"></span>Daily</span>') +
      '</div>' +
      '<h1 class="hero-title" id="heroTitle">' + esc(S.tagline || 'Connect two players through teammates.') + '</h1>' +
      '<div class="matchup">' +
        heroCard(a, 'Start', 'pcard-start') +
        '<div class="matchup-arrow" aria-hidden="true"><span><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg></span></div>' +
        heroCard(b, 'Finish', 'pcard-end') +
      '</div>' +
      '<div class="hero-foot">' +
        '<span class="par-badge" aria-label="Par ' + pz.par + ' links">Par ' + pz.par + '</span>' +
        (pz.theme ? '<span class="theme-label"><svg viewBox="0 0 24 24" width="15" height="15" fill="currentColor" aria-hidden="true"><path d="m12 2.8 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 16.8l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9Z"/></svg>' + esc(pz.theme) + '</span>' : '') +
        (practice ? '<span class="hero-note">Archive replay · doesn\'t count toward stats</span>' : '<span class="hero-note">Fewest links possible: ' + pz.par + '</span>') +
      '</div>';
    setKicker('<span class="k-word">' + (practice ? 'Practice ' : 'Puzzle ') + '</span><b>#' + pz.n + '</b>');
  }

  /* ------------------------------------------------------------ chain */
  function connHTML(shared, cls) {
    if (!shared || !shared.length) return '';
    const first = shared[0], more = shared.length - 1;
    return '<div class="conn ' + (cls || '') + '">' + chip(first.team, first.season) +
      '<span>Teammates on the <b>' + esc(H.teamLabel(index, first.team, first.season)) + '</b></span>' +
      (more > 0 ? '<button type="button" class="more-btn" aria-expanded="false" data-more>+' + more + ' more</button>' +
        '<div class="more-list" hidden>' + shared.slice(1).map((s) => '<span>' + chip(s.team, s.season) + esc(H.teamLabel(index, s.team, s.season)) + '</span>').join('') + '</div>' : '') +
      '</div>';
  }
  function nodeHTML(p, kind, tag) {
    const dot = kind === 'target' ? '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17.5 19 7"/></svg>'
      : kind === 'ghost' ? '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 21V4M5 4h11l-2 4 2 4H5"/></svg>'
      : kind === 'lost' ? '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>'
      : posAbbr(p);
    return '<div class="node node-' + kind + '">' +
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

    // chain so far
    $('#chain').innerHTML = body.map((id, i) => {
      const p = H.player(index, id);
      const enter = opts.animate && i === body.length - 1 && i > 0 ? ' enter' : '';
      return '<li class="step' + enter + '">' +
        (i > 0 ? connHTML(H.sharedTeams(index, ids[i - 1], id)) : '') +
        nodeHTML(p, i === 0 ? 'start' : 'mid', i === 0 ? 'Start' : '') + '</li>';
    }).join('');

    // header meta
    $('#chainMeta').innerHTML = '<b>' + plural(sc.links, 'link') + '</b> · Par ' + st.par;

    // slot: input while playing, a result strip when over
    const last = H.player(index, lastId());
    const finder = $('#finder'), strip = $('#resultStrip'), next = $('#nextConn');
    finder.hidden = !playing;
    next.hidden = !playing;
    if (playing) {
      next.className = 'conn conn-next';
      next.innerHTML = '<span>Next: a teammate of <b>' + esc(last.name) + '</b></span>';
      $('#guess').disabled = false;
    } else {
      $('#guess').disabled = true;
      closeAC();
    }
    strip.hidden = playing;
    if (!playing) {
      strip.innerHTML = '<div><div class="rs-score ' + (won && sc.over === 0 ? 'is-par' : lost ? 'is-x' : '') + '">' +
        (won ? esc(sc.label === 'Par' ? 'Par' : sc.label) : esc(S.lost)) + '</div>' +
        '<small>' + (won ? 'Solved in ' + plural(sc.links, 'link') + ' · Par ' + st.par : plural(st.inc, S.miss) + ' · Par ' + st.par) + '</small></div>' +
        '<button type="button" class="btn btn-gold" id="btnSeeResults">See results</button>';
      $('#btnSeeResults').addEventListener('click', () => openResults());
    }
    $('#slot').hidden = !playing;

    // hint for the current position (kept visible while you stay there)
    const h = playing ? st.hintAt[lastId()] : null;
    const pill = $('#hintPill');
    pill.hidden = !h;
    if (h) {
      pill.innerHTML = '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-3.6 10.8c.7.5 1.1 1.3 1.1 2.2h5c0-.9.4-1.7 1.1-2.2A6 6 0 0 0 12 3Z"/></svg>' +
        '<span>Hint: try the</span>' + chip(h.team, h.season) + '<b>' + esc(H.teamLabel(index, h.team, h.season)) + '</b>';
    }

    // target
    const end = H.player(index, st.end);
    const tgt = $('#target');
    tgt.className = 'target' + (opts.animate && won ? ' enter' : '');
    if (won) {
      tgt.innerHTML = connHTML(H.sharedTeams(index, ids[ids.length - 2], st.end), 'conn-final') + nodeHTML(end, 'target', 'Finish');
    } else {
      tgt.innerHTML = '<div class="conn conn-pending" aria-hidden="true"></div>' + nodeHTML(end, lost ? 'lost' : 'ghost', 'Finish');
    }

    renderControls();
    $('#ruleNote').textContent = playing
      ? 'Teammates = same team, same season (' + (playersJson.seasons ? playersJson.seasons.join('–') : '') + ', regular season and playoffs).'
      : (game.mode === 'practice' ? 'Practice replay: not counted in your stats.' : '');
  }

  function renderControls() {
    const st = game.state, playing = st.status === 'playing';
    const total = H.DOWNS;
    let dots = '<span class="downs-label">' + esc(cap(S.lives)) + '</span>';
    for (let i = 0; i < total; i++) dots += '<span class="down' + (i < st.downs ? '' : ' used') + '"></span>';
    const d = $('#downs');
    d.innerHTML = dots;
    d.classList.toggle('last', playing && st.downs === 1);
    d.setAttribute('aria-label', plural(st.downs, S.life || 'down', S.lives) + ' left of ' + total);
    $('#btnUndo').disabled = !playing || st.chain.length < 2;
    const cached = playing && !!st.hintAt[lastId()];
    const hb = $('#btnHint');
    hb.disabled = !playing || cached || st.downs <= 1;
    $('#btnHintLabel').textContent = cached ? 'Hint shown' : 'Hint';
    hb.title = !playing ? '' : cached ? 'The hint for this spot is shown below the search box' : st.downs <= 1 ? 'No hints on your last ' + (S.life || 'down') : 'Costs one ' + (S.life || 'down');
  }

  // "+2 more" toggles
  $('#chainCard').addEventListener('click', (e) => {
    const b = e.target.closest('[data-more]');
    if (!b) return;
    const list = b.nextElementSibling;
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
      case 'end': return ['Not yet', p.name + ' never played with ' + last.name + '. Find a link first. No ' + (S.life || 'down') + ' lost.'];
      case 'unknown': return ['Pick a player from the list', ''];
      default: return ['This game is over', ''];
    }
  }

  function pick(id) {
    if (!game || game.state.status !== 'playing') return;
    const before = game.state;
    const lastP = H.player(index, lastId());
    const p = H.player(index, id);
    const res = H.guess(index, before, id);
    const r = res.result;
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
      flashMiss();
      haptic([12, 40, 12]);
      const left = r.kind === 'lost' ? 0 : r.downsLeft;
      const msg = (r.kind === 'lost' ? S.lost : cap(S.miss)) + ' — ' + p.name + ' and ' + lastP.name + ' were never teammates';
      toast(msg, 'bad', r.kind === 'lost' ? 'Game over.' : plural(left, S.life || 'down', S.lives) + ' left');
      announce(msg + '. ' + plural(left, S.life || 'down', S.lives) + ' left.');
      renderGame();
      if (r.kind === 'lost') finish();
      return;
    }
    // link or solved
    haptic(6);
    const sh = r.links[0];
    renderGame({ animate: true });
    if (r.kind === 'link') {
      announce(p.name + ' added. Teammates on the ' + H.teamLabel(index, sh.team, sh.season) + '. ' + plural(game.state.chain.length - 1, 'link') + ' so far.');
      keepInputInView();
    } else {
      const end = H.player(index, game.state.end);
      const f = r.final[0];
      announce(p.name + ' added, and played with ' + end.name + ' on the ' + H.teamLabel(index, f.team, f.season) + '. Solved!');
      finish();
    }
  }

  function finish() {
    recordDaily();
    $('#guess').blur();
    setTimeout(() => openResults(), REDUCE.matches ? 50 : 900);
  }

  function flashMiss() {
    const f = $('#field');
    f.classList.remove('miss');
    void f.offsetWidth;
    f.classList.add('miss');
    setTimeout(() => f.classList.remove('miss'), 900);
  }

  $('#btnUndo').addEventListener('click', () => {
    if (!game) return;
    const removed = H.player(index, lastId());
    const next = H.undo(game.state);
    if (next.chain.length === game.state.chain.length) return;
    game.state = next;
    save();
    renderGame();
    announce('Removed ' + removed.name + '. Undo is free.');
    toast('Removed ' + removed.name, 'warn', 'Undo is free.');
  });

  /* hint: confirm first (it costs a down), then show it and keep it visible */
  const dlgHint = $('#dlgHint');
  $('#btnHint').addEventListener('click', () => {
    if (!game || game.state.status !== 'playing') return;
    const st = game.state;
    if (st.hintAt[lastId()]) { $('#hintPill').scrollIntoView({ block: 'nearest' }); return; }
    if (st.downs <= 1) { toast('No hints on your last ' + (S.life || 'down'), 'warn'); return; }
    const life = S.life || 'down';
    $('#hintDesc').innerHTML = 'A hint names the team and season of the next link on a shortest route from <b>' + esc(H.player(index, lastId()).name) +
      '</b>. It costs one ' + esc(life) + ': you\'ll have ' + plural(st.downs - 1, life, S.lives) + ' left.';
    openDialog(dlgHint, $('#btnHint'));
  });
  dlgHint.addEventListener('close', () => {
    document.documentElement.classList.remove('modal-open');
    if (dlgHint.returnValue !== 'ok' || !game) return;
    const r = H.hint(index, game.state);
    if (r.error) {
      toast(r.error === 'last-down' ? 'No hints on your last ' + (S.life || 'down') : r.error === 'none' ? 'No hint available here' : 'This game is over', 'warn');
      return;
    }
    game.state = r.state;
    save();
    renderGame();
    const label = H.teamLabel(index, r.hint.team, r.hint.season);
    announce('Hint: try the ' + label + '. ' + plural(game.state.downs, S.life || 'down', S.lives) + ' left.');
    toast('Try the ' + label, 'good', plural(game.state.downs, S.life || 'down', S.lives) + ' left');
  });

  /* ------------------------------------------------------------ autocomplete */
  const input = $('#guess'), acList = $('#acList'), clearBtn = $('#guessClear');
  let acItems = [], acActive = -1, acTimer = 0;

  function clearGuess(keepFocus) {
    clearTimeout(acTimer); acTimer = 0;
    input.value = '';
    clearBtn.hidden = true;
    closeAC();
    if (keepFocus && document.activeElement !== input && !PHONE.matches) input.focus();
  }
  function closeAC() {
    acItems = []; acActive = -1;
    acList.hidden = true; acList.innerHTML = '';
    input.setAttribute('aria-expanded', 'false');
    input.removeAttribute('aria-activedescendant');
  }
  function highlight(name, q) {
    const nq = H.normalize(q);
    if (!nq) return esc(name);
    // only highlight a plain case-insensitive prefix match on the raw name (cosmetic)
    const lower = name.toLowerCase(), i = lower.indexOf(q.trim().toLowerCase());
    if (i < 0 || !q.trim()) return esc(name);
    const j = i + q.trim().length;
    return esc(name.slice(0, i)) + '<mark>' + esc(name.slice(i, j)) + '</mark>' + esc(name.slice(j));
  }
  function runSearch() {
    acTimer = 0;
    if (!game || game.state.status !== 'playing') return closeAC();
    const q = input.value;
    if (!q.trim()) return closeAC();
    acItems = H.search(index, q, { limit: CONFIG.searchLimit, exclude: game.state.chain });
    acActive = acItems.length ? 0 : -1;
    renderAC(q);
  }
  function renderAC(q) {
    if (!acItems.length) {
      acList.innerHTML = '<li class="ac-empty" role="option" aria-disabled="true">No player by that name played ' + esc(playersJson.seasons ? playersJson.seasons.join('–') : '') + '.</li>';
    } else {
      const endId = game.state.end;
      acList.innerHTML = acItems.map((p, i) => '<li class="ac-row" role="option" id="ac-' + i + '" data-id="' + esc(p.id) + '" aria-selected="' + (i === acActive) + '" style="--i:' + i + '">' +
        '<span><strong>' + highlight(p.name, q) + (p.id === endId ? '<span class="ac-tag">Finish</span>' : '') + '</strong><small>' + esc(metaLine(p)) + '</small></span>' +
        '<span class="chips">' + chipsFor(p, 3) + '</span></li>').join('');
    }
    acList.hidden = false;
    input.setAttribute('aria-expanded', 'true');
    syncActive();
    sizeAC();
  }
  function syncActive() {
    [...acList.querySelectorAll('.ac-row')].forEach((el, i) => el.setAttribute('aria-selected', String(i === acActive)));
    if (acActive >= 0) {
      input.setAttribute('aria-activedescendant', 'ac-' + acActive);
      const el = $('#ac-' + acActive);
      if (el) el.scrollIntoView({ block: 'nearest' });
    } else input.removeAttribute('aria-activedescendant');
  }
  /** Keep the dropdown inside the visible viewport (above an on-screen keyboard). */
  function sizeAC() {
    if (acList.hidden) return;
    const vv = window.visualViewport;
    const bottom = vv ? vv.height + vv.offsetTop : window.innerHeight;
    const top = input.getBoundingClientRect().bottom + 6;
    const room = Math.floor(bottom - top - 12);
    acList.style.maxHeight = Math.max(150, Math.min(420, room)) + 'px';
  }
  function keepInputInView() {
    if (!PHONE.matches || document.activeElement !== input) return;
    const hb = $('#topbar').getBoundingClientRect().height;
    const y = $('#field').getBoundingClientRect().top + window.scrollY - hb - 12;
    if (Math.abs(window.scrollY - y) > 4) window.scrollTo({ top: y, behavior: REDUCE.matches ? 'auto' : 'smooth' });
    setTimeout(sizeAC, 350);
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
      syncActive();
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (acTimer) { clearTimeout(acTimer); runSearch(); }
      if (acActive >= 0 && acItems[acActive]) pick(acItems[acActive].id);
      else if (input.value.trim()) toast('Pick a player from the list', 'warn');
    } else if (e.key === 'Escape') {
      if (!acList.hidden) { e.preventDefault(); closeAC(); }
      else if (input.value) { e.preventDefault(); clearGuess(); }
    } else if (e.key === 'Tab') {
      closeAC();
    }
  });
  acList.addEventListener('mousedown', (e) => e.preventDefault()); // keep focus (and the keyboard) on the input
  acList.addEventListener('click', (e) => {
    const row = e.target.closest('.ac-row');
    if (row) pick(row.dataset.id);
  });
  acList.addEventListener('mousemove', (e) => {
    const row = e.target.closest('.ac-row');
    if (!row) return;
    const i = [...acList.children].indexOf(row);
    if (i !== acActive) { acActive = i; syncActive(); }
  });
  clearBtn.addEventListener('click', () => { clearGuess(); input.focus(); });
  document.addEventListener('pointerdown', (e) => { if (!e.target.closest('#finder')) closeAC(); });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', sizeAC);
  window.addEventListener('resize', sizeAC);

  /* "/" focuses the search from anywhere */
  document.addEventListener('keydown', (e) => {
    if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.target.closest && e.target.closest('input, textarea, select, [contenteditable]')) return;
    if (document.querySelector('dialog[open]') || currentView !== 'game' || input.disabled) return;
    e.preventDefault();
    input.focus();
  });

  /* ------------------------------------------------------------ toasts / announcer */
  const toasts = $('#toasts');
  function toast(msg, kind, sub) {
    const el = document.createElement('div');
    el.className = 'toast ' + (kind || 'warn');
    const ic = kind === 'bad' ? '!' : kind === 'good' ? '✓' : 'i';
    el.innerHTML = '<span class="t-ic" aria-hidden="true">' + ic + '</span><span>' + esc(msg) + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span>';
    toasts.appendChild(el);
    while (toasts.children.length > 2) toasts.firstElementChild.remove();
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, CONFIG.toastMs);
  }
  const announcer = $('#announcer');
  function announce(text) { announcer.textContent = ''; setTimeout(() => { announcer.textContent = text; }, 30); }

  /* ------------------------------------------------------------ dialogs */
  const returnFocus = new WeakMap();
  function openDialog(dlg, from) {
    if (dlg.open) return;
    returnFocus.set(dlg, from || document.activeElement);
    closeAC();
    dlg.classList.remove('closing');
    dlg.showModal();
    document.documentElement.classList.add('modal-open');
  }
  function closeDialog(dlg, value) {
    if (!dlg.open) return;
    const done = () => { dlg.classList.remove('closing'); dlg.style.transform = ''; dlg.close(value); };
    if (REDUCE.matches || !dlg.classList.contains('sheet')) return done();
    dlg.classList.add('closing');
    setTimeout(done, PHONE.matches ? 230 : 180);
  }
  function closeAllDialogs() { document.querySelectorAll('dialog[open]').forEach((d) => d.close()); }
  document.querySelectorAll('dialog').forEach((dlg) => {
    dlg.addEventListener('close', () => {
      if (!document.querySelector('dialog[open]')) document.documentElement.classList.remove('modal-open');
      const f = returnFocus.get(dlg);
      if (f && f.isConnected && typeof f.focus === 'function' && !f.disabled) {
        if (f === input && PHONE.matches) return; // don't pop the keyboard back up
        f.focus({ preventScroll: true });
      }
    });
    dlg.addEventListener('cancel', (e) => { if (dlg.classList.contains('sheet')) { e.preventDefault(); closeDialog(dlg); } });
    dlg.addEventListener('click', (e) => {
      if (e.target.closest('[data-close]')) { closeDialog(dlg); return; }
      if (e.target === dlg) { // backdrop
        const r = dlg.getBoundingClientRect();
        if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) closeDialog(dlg, 'cancel');
      }
    });
    if (dlg.classList.contains('sheet')) swipeToClose(dlg);
  });

  /** Phones: drag a sheet down from its top (when scrolled to the top) to close it. */
  function swipeToClose(dlg) {
    let y0 = 0, t0 = 0, dy = 0, active = false, scroller = null;
    dlg.addEventListener('pointerdown', (e) => {
      if (!PHONE.matches || e.pointerType === 'mouse' || e.target.closest('button, a, input, pre')) return;
      scroller = dlg.querySelector('.sheet-scroll');
      if (scroller && scroller.scrollTop > 0) return;
      active = true; y0 = e.clientY; t0 = performance.now(); dy = 0;
    });
    dlg.addEventListener('pointermove', (e) => {
      if (!active) return;
      dy = Math.max(0, e.clientY - y0);
      if (dy > 6) { dlg.classList.add('dragging'); dlg.style.transform = 'translateY(' + dy + 'px)'; }
    });
    const end = () => {
      if (!active) return;
      active = false;
      const v = dy / Math.max(1, performance.now() - t0);
      dlg.classList.remove('dragging');
      if (dy > dlg.getBoundingClientRect().height / 3 || (dy > 40 && v > 0.6)) closeDialog(dlg);
      else { dlg.style.transition = 'transform .35s var(--spring)'; dlg.style.transform = ''; setTimeout(() => { dlg.style.transition = ''; }, 360); }
    };
    dlg.addEventListener('pointerup', end);
    dlg.addEventListener('pointercancel', end);
  }

  /* ------------------------------------------------------------ results sheet */
  const sheet = $('#sheet');
  let countdownTimer = 0, rollAt = 0;

  /** The next moment the Eastern calendar date changes (binary search on H.easternDate; no tz math here). */
  function nextRollover() {
    const now = Date.now(), d0 = H.easternDate(new Date(now));
    let lo = now, hi = now + 26 * 3600e3;
    if (H.easternDate(new Date(hi)) === d0) return hi;
    while (hi - lo > 500) {
      const mid = Math.floor((lo + hi) / 2);
      if (H.easternDate(new Date(mid)) === d0) lo = mid; else hi = mid;
    }
    return hi;
  }
  function fmtCountdown(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    const p2 = (n) => (n < 10 ? '0' : '') + n;
    return p2(Math.floor(s / 3600)) + ':' + p2(Math.floor((s % 3600) / 60)) + ':' + p2(s % 60);
  }
  function tickCountdown() {
    const el = $('#countdown');
    if (!el) return;
    const left = rollAt - Date.now();
    if (left <= 0) {
      el.closest('.countdown').innerHTML = '<span>New puzzle</span><a class="btn btn-gold" href="#" data-close>Play now</a>';
      clearInterval(countdownTimer);
      refreshToday();
      return;
    }
    el.textContent = fmtCountdown(left);
    el.setAttribute('datetime', 'PT' + Math.floor(left / 1000) + 'S');
  }

  function miniChain(ids, links, stEnd) {
    // ids: player ids; links[i]: {team, season} between ids[i] and ids[i+1]
    let html = '';
    ids.forEach((id, i) => {
      const p = H.player(index, id);
      if (i > 0) {
        const l = links[i - 1];
        html += '<li class="ml-link">' + chip(l.team, l.season) + 'Teammates on the ' + esc(H.teamLabel(index, l.team, l.season)) + '</li>';
      }
      const cls = i === 0 ? 's' : id === stEnd ? 'e' : '';
      html += '<li><span class="ml-dot ' + cls + '" aria-hidden="true">' + posAbbr(p) + '</span><span class="ml-name">' + esc(p.name) + '</span><span class="chips">' + chipsFor(p, 2) + '</span></li>';
    });
    return html;
  }

  function statTiles(stats) {
    const ds = H.displayStreaks(stats, todayN);
    const pct = stats.played ? Math.round((stats.won / stats.played) * 100) : 0;
    const t = [[stats.played, 'Played'], [pct, 'Win %'], [ds.cur, 'Streak'], [ds.max, 'Best streak'], [ds.parCur, 'Par streak', 'gold'], [ds.parMax, 'Best par streak', 'gold']];
    return '<div class="tiles">' + t.map((x, i) => '<div class="tile ' + (x[2] || '') + '" style="--i:' + i + '"><b>' + x[0] + '</b><small>' + x[1] + '</small></div>').join('') + '</div>';
  }

  function openResults() {
    if (!game || game.state.status === 'playing') return;
    const pz = game.puzzle, st = game.state, sc = H.score(st);
    const won = st.status === 'won';
    const share = H.shareText(pz, st, { url: CONFIG.shareUrl, title: S.title, emoji: S.emoji });
    const myLinks = [];
    for (let i = 1; i < st.chain.length; i++) myLinks.push(H.sharedTeams(index, st.chain[i - 1], st.chain[i])[0]);
    const optLinks = (pz.links || []).map((l) => ({ team: l[0], season: l[1] }));
    const scoreCls = won && sc.over === 0 ? 'is-par' : won ? '' : 'is-x';
    const sub = [plural(sc.links, 'link') + ' · Par ' + pz.par, plural(st.inc, S.miss), plural(st.hints, 'hint')].join(' · ');
    const practice = game.mode === 'practice';

    $('#sheetScroll').innerHTML =
      '<div class="sheet-grab" aria-hidden="true"></div>' +
      '<header class="sheet-hero">' +
        '<button type="button" class="close-btn" data-close aria-label="Close results"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>' +
        '<span class="kicker">' + esc(S.title) + ' <b>#' + pz.n + '</b> · ' + esc(fmtDate(pz.date)) + (practice ? ' · Practice' : '') + '</span>' +
        '<div class="score-big ' + scoreCls + '" aria-hidden="true">' + esc(sc.label) + '</div>' +
        '<h2 id="sheetTitle" tabindex="-1">' + (won ? (sc.over === 0 ? 'Right on par!' : 'Solved, ' + sc.label + ' over par') : esc(S.lost)) + '</h2>' +
        '<p>' + esc(won ? sub : plural(st.inc, S.miss) + ' · ' + plural(st.hints, 'hint') + ' · Par ' + pz.par) + '</p>' +
      '</header>' +
      '<div class="sheet-body">' +
        '<section class="sheet-sec" aria-labelledby="shTitle"><h3 id="shTitle">Share <span>No spoilers</span></h3>' +
          '<pre class="share-preview" id="sharePreview">' + esc(share) + '</pre>' +
          '<div class="share-btns">' +
            (navigator.share ? '<button type="button" class="btn btn-gold btn-lg" id="btnShare"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 15V3M7 8l5-5 5 5"/><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/></svg>Share</button>' : '') +
            '<button type="button" class="btn ' + (navigator.share ? '' : 'btn-gold ') + 'btn-lg" id="btnCopy"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg><span>Copy result</span></button>' +
          '</div>' +
        '</section>' +
        (practice
          ? '<p class="practice-note">Practice replay of puzzle #' + pz.n + '. It doesn\'t count toward your stats or streaks.</p>'
          : '<section class="sheet-sec" aria-labelledby="stTitle"><h3 id="stTitle">Your stats</h3>' + statTiles(loadStats()) + '</section>') +
        '<section class="sheet-sec" aria-labelledby="myTitle"><h3 id="myTitle">Your chain <span>' + plural(sc.links, 'link') + '</span></h3>' +
          '<ol class="mini-list">' + miniChain(st.chain, myLinks, st.end) +
          (won ? '' : '<li class="ml-link miss">' + esc(S.lost) + '</li><li><span class="ml-dot e" aria-hidden="true">' + posAbbr(H.player(index, st.end)) + '</span><span class="ml-name">' + esc(H.player(index, st.end).name) + '</span></li>') +
          '</ol></section>' +
        '<section class="sheet-sec" aria-labelledby="opTitle"><h3 id="opTitle">One optimal chain <span>' + plural(pz.par, 'link') + '</span></h3>' +
          '<ol class="mini-list">' + miniChain(pz.chain, optLinks, pz.end) + '</ol>' +
          '<p class="optimal-note">' + (pz.optimal === 1 ? 'Only 1 optimal chain exists.' : esc(Number(pz.optimal).toLocaleString('en-US')) + ' optimal chains exist.') + '</p>' +
        '</section>' +
        '<div class="countdown"><span>Next puzzle in</span><time id="countdown">--:--:--</time></div>' +
      '</div>';

    $('#btnCopy').addEventListener('click', () => copyText(share));
    const sb = $('#btnShare');
    if (sb) sb.addEventListener('click', () => {
      navigator.share({ text: share }).catch((err) => { if (err && err.name !== 'AbortError') copyText(share); });
    });
    rollAt = nextRollover();
    clearInterval(countdownTimer);
    tickCountdown();
    countdownTimer = setInterval(tickCountdown, 1000);
    openDialog(sheet, document.activeElement && document.activeElement !== document.body ? document.activeElement : $('#btnSeeResults'));
    $('#sheetScroll').scrollTop = 0;
    $('#sheetTitle').focus({ preventScroll: true });
  }
  sheet.addEventListener('close', () => { clearInterval(countdownTimer); });

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
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(ok, fallback);
    else fallback();
  }

  /* ------------------------------------------------------------ stats page */
  function renderStatsPage() {
    const stats = loadStats();
    const total = stats.played;
    const buckets = [['0', 'Par'], ['1', '+1'], ['2', '+2'], ['3', '+3'], ['X', 'X']];
    const max = Math.max(1, ...buckets.map((b) => stats.hist[b[0]] || 0));
    const todayState = store.get(stateKey('daily', todayN), null);
    let todayBucket = null;
    if (todayState && todayState.status !== 'playing' && stats.results[todayN]) {
      const sc = H.score(todayState);
      todayBucket = sc.won ? String(Math.min(3, sc.over)) : 'X';
    }
    $('#statsBody').innerHTML =
      '<section class="card page-card" aria-labelledby="sumTitle"><h2 id="sumTitle">Summary</h2>' + statTiles(stats) + '</section>' +
      '<section class="card page-card" aria-labelledby="histTitle"><h2 id="histTitle">Strokes vs par <small>' + plural(total, 'daily game') + '</small></h2>' +
        (total ? '<ol class="hist">' + buckets.map((b, i) => {
          const c = stats.hist[b[0]] || 0;
          return '<li class="' + (b[0] === '0' ? 'is-par' : '') + '"><span class="h-lab">' + b[1] + (b[0] === '3' ? '<span class="sr-only"> or more</span>' : '') + '</span>' +
            '<span class="h-bar' + (todayBucket === b[0] || (c > 0 && !todayBucket && c === max) ? ' on' : '') + '" style="--w:' + Math.round((c / max) * 100) + ';--i:' + i + '">' + c + '</span></li>';
        }).join('') + '</ol>' : '<p class="empty-note">Finish a daily puzzle to start your record.</p>') +
      '</section>' +
      '<div class="back-row"><a class="btn btn-primary" href="#">Back to today\'s puzzle</a></div>';
    setKicker(todayKicker());
    showView('stats');
  }

  /* ------------------------------------------------------------ archive */
  function badgeFor(st) {
    if (!st) return null;
    if (st.status === 'playing') return st.chain.length > 1 || st.inc || st.hints ? { cls: 'prog', text: 'In progress' } : null;
    const sc = H.score(st);
    return { cls: sc.won ? (sc.over === 0 ? 'par' : 'over') : 'x', text: sc.label };
  }
  function renderArchive() {
    const last = Math.min(todayN, puzzlesJson.puzzles.length);
    let html = '';
    for (let n = last, i = 0; n >= 1; n--, i++) {
      const p = H.puzzleByNumber(puzzlesJson, n);
      if (!p) continue;
      const daily = store.get(stateKey('daily', n), null), practice = store.get(stateKey('practice', n), null);
      const vd = validState(daily, p) ? daily : null, vp = validState(practice, p) ? practice : null;
      let b = badgeFor(vd), note = '';
      if (vd && vd.status !== 'playing') note = 'Daily';
      else if (badgeFor(vp) && n !== todayN) { b = badgeFor(vp); note = 'Practice'; }
      if (!b) b = { cls: 'play', text: 'Play' };
      const isToday = n === todayN;
      html += '<li><a class="arch-row' + (isToday ? ' today' : '') + '" href="#' + n + '" style="--i:' + i + '" aria-label="Puzzle ' + n + ', ' + esc(fmtDate(p.date, true)) + ', par ' + p.par + (p.theme ? ', ' + esc(p.theme) : '') + '. ' + esc(b.text) + (note ? ' (' + note + ')' : '') + '">' +
        '<span class="arch-n">#' + n + '</span>' +
        '<span class="arch-who"><strong>' + esc(fmtDate(p.date)) + (isToday ? ' <span class="today-tag">· Today</span>' : '') + '</strong>' +
          '<small>Par ' + p.par + (p.theme ? ' · ' + esc(p.theme) : '') + '</small></span>' +
        '<span class="badge-wrap"><span class="badge ' + b.cls + '">' + esc(b.text) + '</span>' + (note && b.cls !== 'play' ? '<small>' + note + '</small>' : '') + '</span>' +
        '</a></li>';
    }
    $('#archiveList').innerHTML = html || '<li class="empty-note">No puzzles yet.</li>';
    setKicker(todayKicker());
    showView('archive');
  }

  /* ------------------------------------------------------------ how to play / about */
  const dlgHelp = $('#dlgHelp'), dlgAbout = $('#dlgAbout');
  function helpHTML() {
    const life = S.life || 'down', lives = S.lives;
    const range = playersJson && playersJson.seasons ? playersJson.seasons.join('–') : '';
    return '<p><strong>' + esc(S.tagline) + '</strong> A new puzzle drops every day at midnight Eastern.</p>' +
      '<ol class="steps">' +
        '<li>You get a <strong>Start</strong> and a <strong>Finish</strong> player. Add players one at a time to build a chain between them.</li>' +
        '<li>Each player you add must have been a <strong>teammate</strong> of the last one: same team, same season. When your last player was a teammate of the Finish player, you\'ve solved it.</li>' +
        '<li><strong>Par</strong> is the fewest links possible. Match it for a perfect score; every extra link is +1.</li>' +
        '<li>You have <strong>' + H.DOWNS + ' ' + esc(lives) + '</strong>. A guess that wasn\'t a teammate is an ' + esc(S.miss) + ' and costs a ' + esc(life) + '. Lose them all and it\'s a ' + esc(S.lost.toLowerCase()) + '.</li>' +
        '<li><strong>Undo</strong> is free. A <strong>hint</strong> names the team and season of the next link, and costs a ' + esc(life) + '.</li>' +
      '</ol>' +
      '<div class="mini-chain" aria-label="Example">' +
        '<div class="mc-node"><span class="mc-dot">S</span>Start player</div>' +
        '<div class="mc-link">Teammates on the 2015 team</div>' +
        '<div class="mc-node"><span class="mc-dot">2</span>A player you add</div>' +
        '<div class="mc-link">Teammates on the 2019 team</div>' +
        '<div class="mc-node"><span class="mc-dot g">F</span>Finish player</div>' +
      '</div>' +
      '<p class="fine">Seasons ' + esc(range) + ', regular season and playoffs. Your progress and stats stay on this device.</p>' +
      '<button type="button" class="btn btn-gold btn-wide btn-lg" data-close>Let\'s play</button>';
  }
  function aboutHTML() {
    const built = playersJson && playersJson.built ? fmtDate(playersJson.built, true) : 'unknown';
    const att = S.attribution || { text: 'Player data from nflverse (CC-BY 4.0)', href: 'https://github.com/nflverse' };
    return '<p><strong>' + esc(S.title) + '</strong> is a free daily teammate-chain puzzle. ' + esc(S.tagline) + '</p>' +
      '<p>' + esc(S.disclaimer) + '</p>' +
      '<p><a href="' + esc(att.href) + '" rel="noopener">' + esc(att.text) + '</a>. Team names and colours are shown as plain text chips; there are no logos or photos.</p>' +
      '<p>No accounts, no ads, no tracking. Your games and stats are kept only in this browser\'s local storage.</p>' +
      '<p class="fine">Data built ' + esc(built) + (playersJson && playersJson.seasons ? ' · seasons ' + esc(playersJson.seasons.join('–')) : '') + ' · ' + esc(index ? index.n.toLocaleString('en-US') : '') + ' players</p>' +
      '<div class="legal-links"><a href="privacy.html">Privacy</a><a href="terms.html">Terms</a><a href="support.html">Support</a></div>';
  }
  $('#btnHelp').addEventListener('click', (e) => { $('#helpBody').innerHTML = helpHTML(); openDialog(dlgHelp, e.currentTarget); });
  $('#btnAbout').addEventListener('click', (e) => { $('#aboutBody').innerHTML = aboutHTML(); openDialog(dlgAbout, e.currentTarget); });
  dlgHelp.addEventListener('close', () => store.set(KEY('seen-help'), 1));
  function maybeFirstVisitHelp() {
    if (store.get(KEY('seen-help'), 0)) return;
    if (document.querySelector('dialog[open]')) return;
    $('#helpBody').innerHTML = helpHTML();
    openDialog(dlgHelp, input);
  }

  /* ------------------------------------------------------------ misc chrome */
  $('#brand').addEventListener('click', (e) => {
    if (!location.hash || location.hash === '#') { e.preventDefault(); route(); window.scrollTo({ top: 0, behavior: 'smooth' }); }
  });
  let scrollRaf = 0;
  window.addEventListener('scroll', () => {
    if (scrollRaf) return;
    scrollRaf = requestAnimationFrame(() => { scrollRaf = 0; $('#topbar').classList.toggle('scrolled', window.scrollY > 4); });
  }, { passive: true });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden || !index) return;
    const was = today;
    refreshToday();
    if (today !== was && (!location.hash || location.hash === '#')) { toast('A new puzzle is ready', 'good'); route(); }
  });

  // test hook (read-only): lets automated checks see the current state
  window.__chainmates = { get state() { return game && JSON.parse(JSON.stringify(game.state)); }, get mode() { return game && game.mode; } };

  load();
})();
