#!/usr/bin/env python3
"""Sanity tests for the generated data (stdlib only, independent of build_data.py).

  python3 tools/test_data.py
"""
import datetime as dt
import gzip
import json
import os
import sys
from collections import defaultdict, deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(sport):
    d = os.path.join(ROOT, "data", sport)
    return json.load(open(os.path.join(d, "players.json"))), json.load(open(os.path.join(d, "puzzles.json")))


def parse_stints(s):
    out = []
    for part in s.split(";"):
        team, yrs = part.split(":")
        a, _, b = yrs.partition("-")
        out += [(team, y) for y in range(int(a), int(b or a) + 1)]
    return out


class Index:
    def __init__(self, pj):
        self.of, self.members, self.name = {}, defaultdict(set), {}
        for pid, name, _pos, _fame, stints in pj["players"]:
            self.name[pid] = name
            self.of[pid] = set(parse_stints(stints))
            for ts in self.of[pid]:
                self.members[ts].add(pid)

    def by_name(self, name):
        ids = [p for p, n in self.name.items() if n == name]
        assert len(ids) == 1, f"{name}: {len(ids)} matches"
        return ids[0]

    def dist(self, a, b):
        seen, q, seen_ts = {a: 0}, deque([a]), set()
        while q:
            u = q.popleft()
            if u == b:
                return seen[u]
            for ts in self.of[u]:
                if ts in seen_ts:
                    continue
                seen_ts.add(ts)
                for v in self.members[ts]:
                    if v not in seen:
                        seen[v] = seen[u] + 1
                        q.append(v)
        return None


def main():
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    pj, pz = load("nfl")
    ix = Index(pj)

    brady, gronk, mahomes = ix.by_name("Tom Brady"), ix.by_name("Rob Gronkowski"), ix.by_name("Patrick Mahomes")
    check(ix.dist(brady, gronk) == 1, "Brady and Gronkowski should be direct teammates")
    d = ix.dist(mahomes, brady)
    check(d is not None and 2 <= d <= 3, f"Mahomes-Brady par should be short, got {d}")
    print(f"Mahomes -> Brady par {d}")

    check(("TB", 2020) in ix.of[brady] and ("NE", 2019) in ix.of[brady], "Brady stints")
    check(not any(t in ("SEA", "LA") for t, _ in ix.of[brady]), "Brady must not have Super Bowl opponent stints")

    epoch = dt.date.fromisoformat(pz["epoch"])
    pairs = set()
    for i, p in enumerate(pz["puzzles"]):
        tag = f"#{p['n']}"
        check(p["n"] == i + 1, f"{tag}: numbering")
        check(p["date"] == (epoch + dt.timedelta(days=i)).isoformat(), f"{tag}: date")
        check(p["best"] >= 2, f"{tag}: fewest links {p['best']} < 2")
        check(p["par"] == p["best"] + 1, f"{tag}: par should be fewest links + 1")
        check(len(p["chain"]) == p["best"] + 1 and len(p["links"]) == p["best"], f"{tag}: chain length")
        check(p["chain"][0] == p["start"] and p["chain"][-1] == p["end"], f"{tag}: chain ends")
        for (t, s), a, b in zip(p["links"], p["chain"], p["chain"][1:]):
            check((t, s) in ix.of[a] and (t, s) in ix.of[b], f"{tag}: {ix.name[a]}-{ix.name[b]} not on {s} {t}")
        check(ix.dist(p["start"], p["end"]) == p["best"], f"{tag}: best is not the shortest path")
        pair = frozenset((p["start"], p["end"]))
        check(pair not in pairs, f"{tag}: repeated pair")
        pairs.add(pair)
    print(f"{len(pz['puzzles'])} puzzles checked")

    for f in ("players.json", "puzzles.json"):
        raw = open(os.path.join(ROOT, "data", "nfl", f), "rb").read()
        print(f"{f}: {len(raw) / 1e6:.2f} MB, gzip {len(gzip.compress(raw)) / 1e6:.2f} MB")
        check(len(raw) < 3e6, f"{f} too large")

    if failures:
        print("FAIL\n  " + "\n  ".join(failures[:50]))
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
