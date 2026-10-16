#!/usr/bin/env python3
"""Build Chainmates' client data from nflverse (CC-BY 4.0).

  python3 tools/build_data.py                 # download (cached), build players.json, extend puzzles.json
  python3 tools/build_data.py --rebuild --epoch 2026-10-12 --days 400
  python3 tools/build_data.py --offline       # use the cache only

Outputs data/nfl/players.json and data/nfl/puzzles.json (see docs/spec.md).
Puzzles dated on or before today (America/New_York) are never changed.
"""
import argparse
import datetime as dt
import json
import math
import os
import random
import sys
import time
import urllib.request
from collections import defaultdict
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd
import scipy.sparse as sp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".cache", "nflverse")
SPORT = "nfl"
DATA = os.path.join(ROOT, "data", SPORT)
BASE = "https://github.com/nflverse/nflverse-data/releases/download"
FIRST_SEASON = 2002
ET = ZoneInfo("America/New_York")

# --- Teams -----------------------------------------------------------------

# Every source code -> current franchise abbreviation.
FRANCHISE = {"ARZ": "ARI", "BLT": "BAL", "CLV": "CLE", "HST": "HOU", "SL": "LA", "STL": "LA",
             "LAR": "LA", "OAK": "LV", "SD": "LAC", "JAC": "JAX"}

TEAMS = {  # franchise: city, name, primary, secondary
    "ARI": ("Arizona", "Cardinals", "#97233F", "#FFB612"), "ATL": ("Atlanta", "Falcons", "#A71930", "#000000"),
    "BAL": ("Baltimore", "Ravens", "#241773", "#9E7C0C"), "BUF": ("Buffalo", "Bills", "#00338D", "#C60C30"),
    "CAR": ("Carolina", "Panthers", "#0085CA", "#101820"), "CHI": ("Chicago", "Bears", "#0B162A", "#C83803"),
    "CIN": ("Cincinnati", "Bengals", "#FB4F14", "#000000"), "CLE": ("Cleveland", "Browns", "#311D00", "#FF3C00"),
    "DAL": ("Dallas", "Cowboys", "#003594", "#869397"), "DEN": ("Denver", "Broncos", "#FB4F14", "#002244"),
    "DET": ("Detroit", "Lions", "#0076B6", "#B0B7BC"), "GB": ("Green Bay", "Packers", "#203731", "#FFB612"),
    "HOU": ("Houston", "Texans", "#03202F", "#A71930"), "IND": ("Indianapolis", "Colts", "#002C5F", "#A2AAAD"),
    "JAX": ("Jacksonville", "Jaguars", "#006778", "#D7A22A"), "KC": ("Kansas City", "Chiefs", "#E31837", "#FFB81C"),
    "LA": ("Los Angeles", "Rams", "#003594", "#FFA300"), "LAC": ("Los Angeles", "Chargers", "#0080C6", "#FFC20E"),
    "LV": ("Las Vegas", "Raiders", "#000000", "#A5ACAF"), "MIA": ("Miami", "Dolphins", "#008E97", "#FC4C02"),
    "MIN": ("Minnesota", "Vikings", "#4F2683", "#FFC62F"), "NE": ("New England", "Patriots", "#002244", "#C60C30"),
    "NO": ("New Orleans", "Saints", "#101820", "#D3BC8D"), "NYG": ("New York", "Giants", "#0B2265", "#A71930"),
    "NYJ": ("New York", "Jets", "#125740", "#FFFFFF"), "PHI": ("Philadelphia", "Eagles", "#004C54", "#A5ACAF"),
    "PIT": ("Pittsburgh", "Steelers", "#101820", "#FFB612"), "SEA": ("Seattle", "Seahawks", "#002244", "#69BE28"),
    "SF": ("San Francisco", "49ers", "#AA0000", "#B3995D"), "TB": ("Tampa Bay", "Buccaneers", "#D50A0A", "#34302B"),
    "TEN": ("Tennessee", "Titans", "#0C2340", "#4B92DB"), "WAS": ("Washington", "Commanders", "#5A1414", "#FFB612"),
}
# Historical abbreviations: code -> (franchise, last season with that code, city)
HISTORIC = {"OAK": ("LV", 2019, "Oakland"), "SD": ("LAC", 2016, "San Diego"), "STL": ("LA", 2015, "St. Louis")}
WAS_NAMES = [[2002, 2019, "Washington"], [2020, 2021, "Football Team"], [2022, 9999, "Commanders"]]


def season_code(franchise, season):
    for code, (fr, last, _) in HISTORIC.items():
        if fr == franchise and season <= last:
            return code
    return franchise


def teams_table():
    out = {}
    for fr, (city, name, c1, c2) in TEAMS.items():
        out[fr] = {"name": name, "city": city, "franchise": fr, "c1": c1, "c2": c2}
    for code, (fr, _, city) in HISTORIC.items():
        _, name, c1, c2 = TEAMS[fr]
        out[code] = {"name": name, "city": city, "franchise": fr, "c1": c1, "c2": c2}
    out["WAS"]["names"] = WAS_NAMES
    return out


def team_label(code, season):
    t = teams_table()[code]
    for a, b, n in t.get("names", []):
        if a <= season <= b:
            return f"{season} {n}"
    return f"{season} {t['name']}"


# --- Download --------------------------------------------------------------

def fetch(rel, offline=False, max_age_h=None):
    path = os.path.join(CACHE, rel.replace("/", "__"))
    fresh = os.path.exists(path) and (max_age_h is None or time.time() - os.path.getmtime(path) < max_age_h * 3600)
    if fresh or (offline and os.path.exists(path)):
        return path
    if offline:
        return None
    os.makedirs(CACHE, exist_ok=True)
    url = f"{BASE}/{rel}"
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                body = r.read()
            with open(path + ".tmp", "wb") as f:
                f.write(body)
            os.replace(path + ".tmp", path)
            return path
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            err = e
        except Exception as e:  # network hiccup
            err = e
        time.sleep(2 ** (attempt + 1))
    raise RuntimeError(f"download failed: {url}: {err}")


def read(rel, offline, current=False):
    # Past seasons never change; refresh the current season (and master tables) daily.
    p = fetch(rel, offline, max_age_h=20 if current else None)
    return pd.read_parquet(p) if p else None


# --- Build stints ----------------------------------------------------------

def norm_team(s):
    return s.map(lambda t: FRANCHISE.get(t, t))


def load(seasons, offline):
    last = seasons[-1]
    players = read("players/players.parquet", offline, current=True)
    pfr_to_gsis = players.dropna(subset=["pfr_id"]).set_index("pfr_id")["gsis_id"].to_dict()
    ev, stats, rosters = [], [], []
    for y in seasons:
        cur = y == last
        w = read(f"weekly_rosters/roster_weekly_{y}.parquet", offline, cur)
        if w is not None:
            w = w[w.gsis_id.notna()]
            rosters.append(w[["gsis_id", "full_name", "position", "season", "team"]])
            # On the 53-man roster that week: ACT, or INA (game-day inactive, recorded from 2019).
            # Practice squad (DEV), reserve lists (RES: IR, PUP, suspended) and cuts don't count.
            a = w[w.status.isin(["ACT", "INA"])]
            ev.append(pd.DataFrame({"pid": a.gsis_id, "fr": norm_team(a.team), "season": y, "week": a.week}))
        s = read(f"stats_player/stats_player_week_{y}.parquet", offline, cur)
        if s is not None:
            s = s[s.player_id.notna()]
            ev.append(pd.DataFrame({"pid": s.player_id, "fr": norm_team(s.team), "season": y, "week": s.week}))
            stats.append(s)
        if y >= 2012:
            c = read(f"snap_counts/snap_counts_{y}.parquet", offline, cur)
            if c is not None:
                # Super Bowl rows in snap_counts have the teams swapped in some seasons
                # (e.g. 2015: Von Miller listed on CAR); stats and rosters cover the SB anyway.
                c = c[c.game_type != "SB"]
                c = c[(c.offense_snaps.fillna(0) + c.defense_snaps.fillna(0) + c.st_snaps.fillna(0)) > 0]
                pid = c.pfr_player_id.map(pfr_to_gsis)
                ok = pid.notna()
                ev.append(pd.DataFrame({"pid": pid[ok], "fr": norm_team(c.team[ok]), "season": y, "week": c.week[ok]}))
        print(f"  {y}", end="", flush=True)
    print()
    ev = pd.concat(ev, ignore_index=True).drop_duplicates()
    ev = ev[ev.fr.isin(TEAMS.keys())]
    stints = ev.groupby(["pid", "fr", "season"]).week.nunique().rename("games").reset_index()
    stints = stints[stints.games >= 1]
    stints["team"] = [season_code(f, s) for f, s in zip(stints.fr, stints.season)]
    return players, pd.concat(stats, ignore_index=True), pd.concat(rosters, ignore_index=True), stints


# --- Fame ------------------------------------------------------------------

OFFENSE_POS = {"QB", "RB", "WR", "TE"}
DEFENSE_POS = {"DE", "DT", "NT", "DL", "LB", "OLB", "ILB", "MLB", "CB", "S", "FS", "SS", "DB"}


def fame_scores(stats, stints, players):
    reg = stats[stats.season_type == "REG"]
    f = lambda c: reg[c].fillna(0) if c in reg else 0
    pts = (
        (f("rushing_yards") + f("receiving_yards")) / 80 + f("passing_yards") / 200
        + (f("rushing_tds") + f("receiving_tds")) * 0.8 + f("passing_tds") * 0.4
        + f("def_sacks") * 1.2 + f("def_interceptions") * 2 + f("def_tackles_solo") / 25
        + f("def_fumbles_forced") * 1 + f("def_pass_defended") * 0.2
        + f("fg_made") / 15
    )
    prod = pts.groupby(reg.player_id).sum()
    games = stints.groupby("pid").games.sum()
    m = players.set_index("gsis_id")
    raw = {}
    for pid, g in games.items():
        r = 0.25 * g + prod.get(pid, 0.0)
        if pid in m.index:
            row = m.loc[pid]
            if isinstance(row, pd.DataFrame):
                row = row.iloc[0]
            if row.get("draft_round") == 1 and pd.notna(row.get("draft_pick")):
                r += 12 + (33 - min(32, int(row["draft_pick"]))) * 0.5
        raw[pid] = max(r, 0.0)
    top = max(raw.values())
    return {pid: int(round(999 * math.sqrt(v / top))) for pid, v in raw.items()}


# --- Graph -----------------------------------------------------------------

class Graph:
    def __init__(self, stints, order):
        self.ids = order  # index -> pid (fame order)
        self.idx = {p: i for i, p in enumerate(order)}
        keys = sorted(set(zip(stints.team, stints.season)))
        self.ts = keys
        kidx = {k: i for i, k in enumerate(keys)}
        rows = stints.pid.map(self.idx).to_numpy()
        cols = np.array([kidx[k] for k in zip(stints.team, stints.season)])
        S = sp.csr_matrix((np.ones(len(rows), dtype=np.float32), (rows, cols)), shape=(len(order), len(keys)))
        A = (S @ S.T).tocsr()
        A.setdiag(0)
        A.eliminate_zeros()
        A.data[:] = 1
        self.S, self.A = S, A
        self.members = defaultdict(list)
        self.of = defaultdict(set)
        for p, t, s in zip(stints.pid, stints.team, stints.season):
            self.members[(t, s)].append(self.idx[p])
            self.of[self.idx[p]].add((t, s))

    def bfs_many(self, sources, maxd=8):
        """dist (len(sources) x n, int8, -1 unreachable) and shortest-path counts (float64)."""
        n, k = self.A.shape[0], len(sources)
        dist = np.full((k, n), -1, dtype=np.int8)
        cnt = np.zeros((k, n))
        front = np.zeros((n, k))
        front[sources, np.arange(k)] = 1
        dist[np.arange(k), sources] = 0
        cnt[np.arange(k), sources] = 1
        for d in range(1, maxd + 1):
            nxt = self.A @ front
            nxt[dist.T >= 0] = 0
            hit = nxt > 0
            if not hit.any():
                break
            dist.T[hit] = d
            cnt.T[hit] = nxt[hit]
            front = nxt
        return dist, cnt

    def shared(self, a, b):
        return sorted(self.of[a] & self.of[b], key=lambda x: (-x[1], x[0]))

    def path(self, dist_from_start, end, fame):
        """Reconstruct an optimal path ending at `end`, preferring famous intermediates."""
        d = dist_from_start[end]
        path = [end]
        cur = end
        while d > 0:
            nb = self.A.indices[self.A.indptr[cur]:self.A.indptr[cur + 1]]
            cand = [u for u in nb if dist_from_start[u] == d - 1]
            cur = max(cand, key=lambda u: fame[self.ids[u]])
            path.append(cur)
            d -= 1
        return path[::-1]


# --- Puzzles ---------------------------------------------------------------

# Difficulty calendar. NFL rosters are big (53+), so the teammate graph is dense:
# among the top ~400 players every pair is 1-3 links apart and par 4 almost never
# exists. Difficulty therefore comes from par *and* how many optimal routes exist.
# kind: (par, min optimal, max optimal, deep-cut chance for one endpoint)
DIFFICULTY = {
    "mon": (2, 20, 10**9, 0.0),   # par 2, lots of shared teammates
    "tue": (2, 8, 19, 0.0),
    "wed": (3, 1, 10**9, 0.0),
    "thu": (2, 3, 7, 0.0),        # par 2, only a handful of routes
    "fri": (3, 1, 300, 0.3),      # par 3, few routes, sometimes a deep cut
    "sat": (3, 1, 10**9, 0.0),    # themed; falls back to par 2
    "sun": (3, 1, 10**9, 0.0),
}
KIND = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
POOL_SIZE = 400
DEEP_POOL = 1200  # "deep cut" endpoints come from fame ranks POOL_SIZE..DEEP_POOL


def era(p):  # career midpoint
    return (p["first"] + p["last"]) / 2


def build_pool(meta, fame):
    """Endpoint pool: ~65% offensive skill players, ~35% defenders; plus a deep-cut pool."""
    ranked = sorted(meta, key=lambda p: -fame[p])
    off = [p for p in ranked if meta[p]["pos"] in OFFENSE_POS]
    dfn = [p for p in ranked if meta[p]["pos"] in DEFENSE_POS]
    n_off = round(POOL_SIZE * 0.65)
    pool = off[:n_off] + dfn[:POOL_SIZE - n_off]
    k = DEEP_POOL // POOL_SIZE
    deep = off[n_off:n_off * k] + dfn[POOL_SIZE - n_off:(POOL_SIZE - n_off) * k]
    return pool, deep


def snf_by_weekend(seasons, offline):
    """Saturday date -> (away, home) for that weekend's Sunday night game."""
    p = fetch("schedules/games.parquet", offline, max_age_h=20)
    if not p:
        return {}
    g = pd.read_parquet(p)
    g = g[(g.season >= seasons[-1] - 1) & (g.weekday == "Sunday") & (g.gametime >= "20:00")]
    out = {}
    for _, r in g.iterrows():
        sun = dt.date.fromisoformat(r.gameday)
        out[(sun - dt.timedelta(days=1)).isoformat()] = (FRANCHISE.get(r.away_team, r.away_team),
                                                        FRANCHISE.get(r.home_team, r.home_team))
    return out


def generate(G, meta, fame, epoch, days, existing, today, seasons, offline, overrides, seed=20021):
    pool, deep = build_pool(meta, fame)
    pidx = [G.idx[p] for p in pool]
    print(f"BFS from {len(pool)} endpoints ...", flush=True)
    t = time.time()
    dist, cnt = G.bfs_many(pidx)
    print(f"  done in {time.time() - t:.1f}s")
    col = {p: i for i, p in enumerate(pool)}
    tt = teams_table()
    franchises = {p: {tt[t]["franchise"] for t, _ in G.of[G.idx[p]]} for p in pool + deep}
    snf = snf_by_weekend(seasons, offline)
    rng = random.Random(seed)

    def make(date, a, b, kind, theme):
        i = col.get(a)
        if i is None:
            d1, c1 = G.bfs_many([G.idx[a]])
            drow, crow = d1[0], c1[0]
        else:
            drow, crow = dist[i], cnt[i]
        e = G.idx[b]
        par = int(drow[e])
        path = G.path(drow, e, fame)
        links = []
        for x, y in zip(path, path[1:]):
            t, s = G.shared(x, y)[0]
            links.append([t, int(s)])
        return {"date": date, "start": a, "end": b, "par": par, "kind": kind, "theme": theme,
                "chain": [G.ids[x] for x in path], "links": links, "optimal": int(crow[e])}

    used_pairs = set()
    recent = []  # endpoints used in the last ~45 days
    out = []
    start_date = dt.date.fromisoformat(epoch)
    old = {p["date"]: p for p in existing}
    for n in range(1, days + 1):
        date = (start_date + dt.timedelta(days=n - 1)).isoformat()
        wd = (start_date + dt.timedelta(days=n - 1)).weekday()
        kind = KIND[wd]
        prev = old.get(date)
        if prev and date <= today:
            keep = dict(prev)  # frozen: already playable
        elif date in overrides:
            o = overrides[date]
            keep = make(date, o["start"], o["end"], kind, o.get("theme"))
        elif prev and prev["start"] in G.idx and prev["end"] in G.idx:
            again = make(date, prev["start"], prev["end"], kind, prev.get("theme"))
            keep = again if again["par"] == prev["par"] and again["par"] >= 2 else None
            if keep is None:
                print(f"  {date}: par changed {prev['par']} -> {again['par']}, regenerating")
        else:
            keep = None
        if keep is None:
            theme, side_a, side_b = None, None, None
            if kind in ("sat", "sun"):
                sat = date if kind == "sat" else (dt.date.fromisoformat(date) - dt.timedelta(days=1)).isoformat()
                if sat in snf:
                    away, home = snf[sat]
                    an, hn = TEAMS[away][1], TEAMS[home][1]
                    if kind == "sat":
                        theme, side_a, side_b = f"{hn} weekend", home, home
                    else:
                        theme, side_a, side_b = f"Sunday Night: {an} at {hn}", away, home
                else:
                    fr = sorted(TEAMS)[(n // 7) % 32]
                    theme, side_a, side_b = f"{TEAMS[fr][1]} weekend", fr, fr
            ctx = (G, pool, deep, col, dist, cnt, meta, franchises, used_pairs, recent, rng)
            par, lo, hi, deep_p = DIFFICULTY[kind]
            tries = [(par, lo, hi, rng.random() < deep_p, side_a, side_b)]
            if theme:
                tries += [(2, 1, 10**9, False, side_a, side_b)]
            tries += [(par, 1, 10**9, False, None, None), (2, 1, 10**9, False, None, None)]
            for i, t in enumerate(tries):
                keep = pick(ctx, *t)
                if keep:
                    if t[4] is None:
                        theme = None
                    break
            if keep is None:
                sys.exit(f"no puzzle found for {date}")
            a, b = keep
            keep = make(date, a, b, kind, theme)
        keep["n"] = n
        used_pairs.add(frozenset((keep["start"], keep["end"])))
        recent = (recent + [keep["start"], keep["end"]])[-90:]
        out.append({k: keep[k] for k in ("n", "date", "start", "end", "par", "kind", "theme", "chain", "links", "optimal")})
    return out


def pick(ctx, want, lo, hi, use_deep, side_a, side_b):
    G, pool, deep, col, dist, cnt, meta, franchises, used, recent, rng = ctx
    recent = set(recent)
    ok_a = lambda p: p not in recent and (side_a is None or side_a in franchises[p])
    ok_b = lambda p: p not in recent and (side_b is None or side_b in franchises[p])
    cands_a = [p for p in pool if ok_a(p)]
    rng.shuffle(cands_a)
    b_pool = deep if use_deep else pool
    for a in cands_a:
        drow, crow = dist[col[a]], cnt[col[a]]
        bs = [p for p in b_pool if p != a and ok_b(p) and drow[G.idx[p]] == want
              and lo <= crow[G.idx[p]] <= hi and frozenset((a, p)) not in used]
        if side_a and side_a == side_b:  # same-franchise theme: don't let both share an era
            bs = [p for p in bs if abs(era(meta[p]) - era(meta[a])) >= 4]
        if not bs:
            continue
        # Mix it up: prefer a different position and a different era.
        def score(p):
            s = rng.random()
            if meta[p]["pos"] != meta[a]["pos"]:
                s += 0.6
            s += min(abs(era(meta[p]) - era(meta[a])), 12) / 12
            return s
        b = max(bs, key=score)
        return (a, b) if rng.random() < 0.5 else (b, a)
    return None


# --- Main ------------------------------------------------------------------

def encode_stints(rows):
    by_team = defaultdict(list)
    for t, s in rows:
        by_team[t].append(s)
    parts = []
    for t, ss in by_team.items():
        ss = sorted(set(ss))
        run = [ss[0]]
        for s in ss[1:] + [None]:
            if s is not None and s == run[-1] + 1:
                run.append(s)
                continue
            parts.append((run[0], f"{t}:{run[0]}" if len(run) == 1 else f"{t}:{run[0]}-{run[-1]}"))
            if s is not None:
                run = [s]
    return ";".join(x for _, x in sorted(parts))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true")
    ap.add_argument("--rebuild", action="store_true", help="ignore existing puzzles.json")
    ap.add_argument("--epoch", default=None, help="date of puzzle #1 (YYYY-MM-DD)")
    ap.add_argument("--days", type=int, default=None, help="number of puzzles (default: through today + 365)")
    ap.add_argument("--last-season", type=int, default=None)
    args = ap.parse_args()

    now_et = dt.datetime.now(ET)
    today = now_et.date().isoformat()
    last = args.last_season or (now_et.year if now_et.month >= 9 else now_et.year - 1)
    seasons = list(range(FIRST_SEASON, last + 1))
    print(f"Loading seasons {seasons[0]}-{seasons[-1]} ...")
    players, stats, rosters, stints = load(seasons, args.offline)

    fame = fame_scores(stats, stints, players)
    master = players.drop_duplicates("gsis_id").set_index("gsis_id")
    rnames = rosters.drop_duplicates("gsis_id", keep="last").set_index("gsis_id")
    meta = {}
    for pid, g in stints.groupby("pid"):
        if pid in master.index and pd.notna(master.at[pid, "display_name"]):
            name, pos = master.at[pid, "display_name"], master.at[pid, "position"]
        else:
            name, pos = rnames.at[pid, "full_name"], rnames.at[pid, "position"]
        if pd.isna(pos) or not pos:
            pos = rnames.at[pid, "position"] if pid in rnames.index else ""
        meta[pid] = {"name": str(name), "pos": str(pos or ""), "first": int(g.season.min()), "last": int(g.season.max()),
                     "stints": encode_stints(zip(g.team, g.season))}
    order = sorted(meta, key=lambda p: (-fame[p], meta[p]["name"], p))
    print(f"{len(order)} players, {len(stints)} stints, {stints[['team', 'season']].drop_duplicates().shape[0]} team-seasons")

    G = Graph(stints, order)
    os.makedirs(DATA, exist_ok=True)
    pj = {"v": 1, "sport": SPORT, "built": today, "seasons": [seasons[0], seasons[-1]], "source": "nflverse (CC-BY 4.0)",
          "teams": teams_table(),
          "players": [[p, meta[p]["name"], meta[p]["pos"], fame[p], meta[p]["stints"]] for p in order]}
    write_json(os.path.join(DATA, "players.json"), pj)

    ppath = os.path.join(DATA, "puzzles.json")
    existing = {} if args.rebuild or not os.path.exists(ppath) else json.load(open(ppath))
    epoch = args.epoch or existing.get("epoch") or "2026-10-12"
    if existing and epoch != existing.get("epoch"):
        sys.exit("epoch differs from existing puzzles.json; pass --rebuild to renumber")
    days = args.days or ((dt.date.fromisoformat(today) - dt.date.fromisoformat(epoch)).days + 366)
    days = max(days, len(existing.get("puzzles", [])))
    overrides = load_overrides(meta)
    puzzles = generate(G, meta, fame, epoch, days, existing.get("puzzles", []), today, seasons, args.offline, overrides)
    write_json(ppath, {"v": 1, "sport": SPORT, "epoch": epoch, "tz": "America/New_York", "puzzles": puzzles})

    report(G, meta, fame, puzzles, order)


def load_overrides(meta):
    path = os.path.join(ROOT, "tools", "puzzle_overrides.json")
    if not os.path.exists(path):
        return {}
    by_name = defaultdict(list)
    for p, m in meta.items():
        by_name[m["name"].lower()].append(p)
    out = {}
    for date, o in json.load(open(path)).items():
        if date.startswith("_"):
            continue
        ends = []
        for key in ("start", "end"):
            v = o[key]
            ids = [v] if v in meta else by_name.get(v.lower(), [])
            if len(ids) != 1:
                sys.exit(f"override {date}: {key} {v!r} matches {len(ids)} players; use a gsis id")
            ends.append(ids[0])
        out[date] = {"start": ends[0], "end": ends[1], "theme": o.get("theme")}
    return out


def write_json(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"), ensure_ascii=False)
        f.write("\n")
    print(f"wrote {os.path.relpath(path, ROOT)} ({os.path.getsize(path) / 1e6:.2f} MB)")


def report(G, meta, fame, puzzles, order):
    from collections import Counter
    print("par distribution:", dict(sorted(Counter(p["par"] for p in puzzles).items())))
    print("by weekday:", {k: dict(Counter(p["par"] for p in puzzles if p["kind"] == k)) for k in KIND})
    for p in puzzles[:7]:
        steps = [meta[p["chain"][0]]["name"]]
        for (t, s), pid in zip(p["links"], p["chain"][1:]):
            steps.append(f"--{team_label(t, s)}--> {meta[pid]['name']}")
        print(f"#{p['n']} {p['date']} {p['kind']} par {p['par']} optimal {p['optimal']} {p['theme'] or ''}\n   " + " ".join(steps))


if __name__ == "__main__":
    main()
