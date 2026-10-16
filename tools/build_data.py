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


def load_honors(offline):
    """gsis_id -> (pro_bowls, all_pros, hall_of_fame) from nflverse draft_picks (drafted players only)."""
    p = fetch("draft_picks/draft_picks.parquet", offline, max_age_h=20)
    if not p:
        return {}
    d = pd.read_parquet(p).dropna(subset=["gsis_id"])
    return {g: (int(pb or 0), int(ap or 0), bool(h)) for g, pb, ap, h in zip(d.gsis_id, d.probowls, d.allpro, d.hof)}


def fame_scores(stats, stints, players, honors):
    """Returns (fame 0-999 for every player, production points). Honors weigh as much as stats:
    fans remember Pro Bowlers, not compilers."""
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
    # Fantasy points: casual fans know players through fantasy football.
    ppr = reg.fantasy_points_ppr.fillna(0).groupby(reg.player_id).sum()
    ppr_best = reg.groupby(["player_id", "season"]).fantasy_points_ppr.sum().groupby("player_id").max()
    games = stints.groupby("pid").games.sum()
    m = players.set_index("gsis_id")
    raw = {}
    for pid, g in games.items():
        r = 0.25 * g + prod.get(pid, 0.0) + ppr.get(pid, 0.0) / 10
        pb, ap, hof = honors.get(pid, (0, 0, False))
        r += 25 * pb + 25 * ap + 60 * hof
        if pid in m.index:
            row = m.loc[pid]
            if isinstance(row, pd.DataFrame):
                row = row.iloc[0]
            if row.get("draft_round") == 1 and pd.notna(row.get("draft_pick")):
                r += 12 + (33 - min(32, int(row["draft_pick"]))) * 0.5
        raw[pid] = max(r, 0.0)
    top = max(raw.values())
    fame = {pid: int(round(999 * math.sqrt(v / top))) for pid, v in raw.items()}
    return fame, prod.to_dict(), {"career": ppr.to_dict(), "best": ppr_best.to_dict()}


ENTRY_MIN = 2011  # endpoints entered the league (drafted, or undrafted rookie year) after 2010


def known_since_2002(pid, meta, prod):
    return meta[pid]["games"] >= 48 and prod.get(pid, 0) >= (60 if meta[pid]["pos"] in OFFENSE_POS else 30)


def is_star(pid, meta, honors, ppr):
    """Offensive endpoint: a fantasy-relevant QB/RB/WR/TE who entered the league after 2010."""
    m = meta[pid]
    if m["pos"] not in OFFENSE_POS or m["entry"] < ENTRY_MIN or m["games"] < 24:
        return False
    pb, ap, _ = honors.get(pid, (0, 0, False))
    # Honors count only with a real fantasy season behind them: return specialists make Pro Bowls too.
    if ppr["best"].get(pid, 0) >= 150 and (ap >= 1 or pb >= 2 or (pb >= 1 and m["first"] >= 2020)):
        return True
    # Fantasy stars: a big career, or one season a whole league drafted him for.
    return ppr["career"].get(pid, 0) >= 1100 or ppr["best"].get(pid, 0) >= 260


def is_elite_defender(pid, meta, honors):
    """Defenders only when they're household names: multiple All-Pros or a pile of Pro Bowls."""
    m = meta[pid]
    if m["pos"] not in DEFENSE_POS or m["entry"] < ENTRY_MIN:
        return False
    pb, ap, hof = honors.get(pid, (0, 0, False))
    return hof or ap >= 3 or (ap >= 2 and pb >= 6)


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
# Par is one more than the fewest links possible, so an optimal chain is a birdie.
PAR_OFFSET = 1
# Endpoints are fantasy-relevant offensive stars who entered the league after 2010 (the top `pool`
# of them by fame, picked with a lean toward fame). About one puzzle in eight swaps one end for an
# elite defender. Friends found the first calendar too hard, so most days have plenty of routes.
# kind: (best = fewest links, min optimal routes, max optimal routes, pool)
DIFFICULTY = {
    "mon": (2, 20, 10**9, 80),     # 2 links, lots of shared teammates, the biggest names
    "tue": (2, 12, 10**9, 120),
    "wed": (2, 6, 10**9, 160),
    "thu": (2, 4, 10**9, 160),
    "fri": (3, 1, 10**9, 200),     # the one 3-link weekday
    "sat": (2, 4, 10**9, 10**9),
    "sun": (3, 1, 10**9, 10**9),
}
DEF_CHANCE = 0.12
MAX_USES = 6       # times a player can be an endpoint across the generated year
KIND = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def era(p):  # career midpoint
    return (p["first"] + p["last"]) / 2


def build_pool(meta, fame, honors, ppr):
    """Offensive star pool and elite-defender pool, each by fame."""
    ranked = sorted(meta, key=lambda p: -fame[p])
    off = [p for p in ranked if is_star(p, meta, honors, ppr)]
    dfn = [p for p in ranked if is_elite_defender(p, meta, honors)]
    return off, dfn


# Night games that get their own puzzle: the day's featured game is the latest kickoff.
PRIME_DAYS = {"Thursday": ("TNF", "Thursday Night"), "Saturday": ("SAT", "Saturday"),
              "Sunday": ("SNF", "Sunday Night"), "Monday": ("MNF", "Monday Night")}
ROSTER_STARS = 10   # per team: the most famous current players a game-day puzzle can start or end on


def primetime_games(seasons, offline):
    """date -> {"slot", "away", "home", "season", "label"} for that day's featured night game.

    Read fresh from the nflverse schedule on every build, so flexed games move with it."""
    p = fetch("schedules/games.parquet", offline, max_age_h=6)
    if not p:
        return {}
    g = pd.read_parquet(p)
    g = g[g.season >= seasons[-1]]
    out = {}
    for date, day in g.groupby("gameday"):
        d = dt.date.fromisoformat(date)
        wd = d.strftime("%A")
        thanksgiving = wd == "Thursday" and d.month == 11 and 22 <= d.day <= 28
        christmas = d.month == 12 and d.day == 25
        if wd not in PRIME_DAYS and not christmas:
            continue
        if wd == "Sunday":
            day = day[day.gametime >= "19:00"]  # Sunday Night, not the afternoon slate
        if day.empty:
            continue
        r = day.sort_values("gametime").iloc[-1]
        season = int(r.season)
        slot, label = PRIME_DAYS.get(wd, ("XMAS", "Christmas"))
        if thanksgiving:
            label = "Thanksgiving Night"
        elif christmas:
            slot, label = "XMAS", "Christmas"
        away, home = (season_code(FRANCHISE.get(t, t), season) for t in (r.away_team, r.home_team))
        out[date] = {"slot": slot, "away": away, "home": home, "season": season, "label": label}
    return out


def game_theme(game):
    tt = teams_table()
    return f"{game['label']}: {tt[game['away']]['name']} at {tt[game['home']]['name']}"


def generate(G, meta, fame, honors, ppr, epoch, days, existing, today, seasons, offline, overrides, seed=20021):
    pool, defs = build_pool(meta, fame, honors, ppr)
    cur = seasons[-1]
    star_set, def_set = set(pool), set(defs)
    # Current rosters: who could be "from tonight's game". Stars and elite defenders first, then
    # other fantasy-relevant offensive players from those rosters.
    roster, roster_wide = defaultdict(list), defaultdict(list)
    for (t, s), members in G.members.items():
        if s == cur:
            ids = sorted((G.ids[i] for i in members), key=lambda p: -fame[p])
            roster[t] = [p for p in ids if p in star_set or p in def_set]
            roster_wide[t] = [p for p in ids if meta[p]["pos"] in OFFENSE_POS and meta[p]["entry"] >= ENTRY_MIN
                              and (ppr["career"].get(p, 0) >= 600 or ppr["best"].get(p, 0) >= 200)][:ROSTER_STARS]
    on_roster = {t: set(roster[t]) | set(roster_wide[t]) for t in set(roster) | set(roster_wide)}
    sources = list(dict.fromkeys(pool + defs + [p for t in on_roster for p in on_roster[t]]))
    print(f"offensive stars {len(pool)}, elite defenders {len(defs)}, BFS sources {len(sources)}")
    t0 = time.time()
    dist, cnt = G.bfs_many([G.idx[p] for p in sources])
    print(f"  BFS done in {time.time() - t0:.1f}s")
    col = {p: i for i, p in enumerate(sources)}
    prime = primetime_games(seasons, offline)
    rng = random.Random(seed)
    modern = lambda p: meta[p]["last"] >= cur - 4   # played in the last five seasons

    def game_ok(pz, game):
        if not game:
            return True
        teams = (season_code(teams_table()[game["away"]]["franchise"], cur),
                 season_code(teams_table()[game["home"]]["franchise"], cur))
        return any(e in on_roster.get(t, ()) for e in (pz["start"], pz["end"]) for t in teams)

    def game_pool(game, wide, defenders):
        teams = (season_code(teams_table()[game["away"]]["franchise"], cur),
                 season_code(teams_table()[game["home"]]["franchise"], cur))
        src = roster_wide if wide else roster
        ps = {p for t in teams for p in src.get(t, []) if (p in def_set) == defenders}
        return sorted(ps, key=lambda p: -fame[p])

    def make(date, a, b, kind, theme, game):
        i = col.get(a)
        if i is None:
            d1, c1 = G.bfs_many([G.idx[a]])
            drow, crow = d1[0], c1[0]
        else:
            drow, crow = dist[i], cnt[i]
        e = G.idx[b]
        best = int(drow[e])
        path = G.path(drow, e, fame)
        links = []
        for x, y in zip(path, path[1:]):
            t, s = G.shared(x, y)[0]
            links.append([t, int(s)])
        return {"date": date, "start": a, "end": b, "best": best, "par": best + PAR_OFFSET, "kind": kind,
                "theme": theme, "game": game, "chain": [G.ids[x] for x in path], "links": links,
                "optimal": int(crow[e])}

    used_pairs = set()
    uses = defaultdict(int)  # endpoint appearances, capped at MAX_USES so the same faces don't dominate
    recent = []  # endpoints used in the last ~45 days
    out = []
    start_date = dt.date.fromisoformat(epoch)
    old = {p["date"]: p for p in existing}
    for n in range(1, days + 1):
        day = start_date + dt.timedelta(days=n - 1)
        date, kind = day.isoformat(), KIND[day.weekday()]
        g = prime.get(date)
        game = {k: g[k] for k in ("slot", "away", "home")} if g else None
        prev = old.get(date)
        if prev and date <= today:
            keep = dict(prev)  # frozen: already playable
            if "best" not in keep:  # format migration only: old files stored par = fewest links
                keep["best"], keep["par"] = keep["par"], keep["par"] + PAR_OFFSET
            keep.setdefault("game", None)
        elif date in overrides:
            o = overrides[date]
            keep = make(date, o["start"], o["end"], kind, o.get("theme") or (game_theme(g) if g else None), game)
        elif prev and prev["start"] in G.idx and prev["end"] in G.idx:
            again = make(date, prev["start"], prev["end"], kind, prev.get("theme"), prev.get("game"))
            prev_best = prev.get("best", prev["par"])
            keep = again
            if again["best"] != prev_best or again["best"] < 2:
                print(f"  {date}: fewest links changed {prev_best} -> {again['best']}, regenerating")
                keep = None
            elif (prev.get("game") or None) != game:
                print(f"  {date}: game changed {prev.get('game')} -> {game} (flex or new schedule), regenerating")
                keep = None
            elif not game_ok(prev, game):
                print(f"  {date}: game-day player no longer on that roster, regenerating")
                keep = None
        else:
            keep = None
        if keep is None:
            best, lo, hi, size = DIFFICULTY[kind]
            ctx = (G, col, dist, cnt, meta, fame, used_pairs, recent, rng, uses, modern)
            off = pool[:size]
            use_def = rng.random() < DEF_CHANCE   # now and then one end is an elite defender
            tries = []
            if g:  # tonight's stars first, then other fantasy-relevant players on those rosters
                for a_pool in ([game_pool(g, False, True)] if use_def else []) + [game_pool(g, False, False),
                                                                                    game_pool(g, True, False)]:
                    if a_pool:
                        tries += [(best, lo, hi, a_pool, pool), (best, 1, 10**9, a_pool, pool),
                                  (2, 1, 10**9, a_pool, pool), (3, 1, 10**9, a_pool, pool)]
            tries += ([(best, lo, hi, defs, off)] if use_def else []) + [
                (best, lo, hi, off, off), (best, lo, hi, pool, pool), (best, 1, 10**9, pool, pool),
                (2, 1, 10**9, pool, pool), (3, 1, 10**9, pool, pool)]
            for t in tries:
                keep = pick(ctx, *t)
                if keep:
                    if t[3] in (defs, off, pool) and g:
                        print(f"  {date}: no game-day pair found, plain puzzle")
                        g = game = None
                    break
            if keep is None:
                sys.exit(f"no puzzle found for {date}")
            a, b = keep
            keep = make(date, a, b, kind, game_theme(g) if g else None, game)
        keep["n"] = n
        used_pairs.add(frozenset((keep["start"], keep["end"])))
        uses[keep["start"]] += 1
        uses[keep["end"]] += 1
        recent = (recent + [keep["start"], keep["end"]])[-40:]   # ~3 weeks before an endpoint returns
        out.append({k: keep.get(k) for k in ("n", "date", "start", "end", "best", "par", "kind", "theme", "game",
                                             "chain", "links", "optimal")})
    return out


def pick(ctx, want, lo, hi, a_pool, b_pool):
    """One endpoint from a_pool (tonight's rosters, the defenders, or the stars), the other an
    offensive star from b_pool. At least one played in the last five seasons. Which end is which
    is a coin flip."""
    G, col, dist, cnt, meta, fame, used, recent, rng, uses, modern = ctx
    recent = {p for p in recent} | {p for p, k in uses.items() if k >= MAX_USES}
    # Weighted shuffle (Efraimidis-Spirakis) leaning toward famous players.
    cands_a = sorted((p for p in a_pool if p not in recent),
                     key=lambda p: -rng.random() ** (1 / max(fame[p] / 999, 0.05) ** 2))
    for a in cands_a:
        drow, crow = dist[col[a]], cnt[col[a]]
        bs = [p for p in b_pool if p != a and p not in recent and drow[G.idx[p]] == want
              and lo <= crow[G.idx[p]] <= hi and frozenset((a, p)) not in used
              and (modern(a) or modern(p))]   # never two players who have both been gone for years
        if not bs:
            continue
        def score(p):  # prefer a different position, and fame
            return rng.random() + (0.6 if meta[p]["pos"] != meta[a]["pos"] else 0) + 0.8 * fame[p] / 999
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


def entry_year(master, pid, first):
    """Draft year, else rookie season (undrafted), else first season in our data."""
    if pid in master.index:
        for col in ("draft_year", "rookie_season"):
            v = master.at[pid, col]
            if pd.notna(v) and int(v) > 1950:
                return int(v)
    return first


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--offline", action="store_true")
    ap.add_argument("--rebuild", action="store_true", help="ignore existing puzzles.json")
    ap.add_argument("--regen-future", action="store_true",
                    help="re-pick every puzzle after today (keeps today and earlier); use after changing the picker")
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

    honors = load_honors(args.offline)
    fame, prod, ppr = fame_scores(stats, stints, players, honors)
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
                     "games": int(g.games.sum()), "entry": entry_year(master, pid, int(g.season.min())),
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
    old = existing.get("puzzles", [])
    if args.regen_future:
        old = [p for p in old if p["date"] <= today]
    puzzles = generate(G, meta, fame, honors, ppr, epoch, days, old, today, seasons, args.offline, overrides)
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
    print("fewest-links distribution:", dict(sorted(Counter(p["best"] for p in puzzles).items())), f"(par = fewest + {PAR_OFFSET})")
    print("by weekday:", {k: dict(Counter(p["best"] for p in puzzles if p["kind"] == k)) for k in KIND})
    for p in puzzles[:7]:
        steps = [meta[p["chain"][0]]["name"]]
        for (t, s), pid in zip(p["links"], p["chain"][1:]):
            steps.append(f"--{team_label(t, s)}--> {meta[pid]['name']}")
        print(f"#{p['n']} {p['date']} {p['kind']} best {p['best']} par {p['par']} optimal {p['optimal']} {p['theme'] or ''}\n   " + " ".join(steps))


if __name__ == "__main__":
    main()
