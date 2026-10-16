#!/usr/bin/env bash
# Assemble the static site into _site/ (gitignored): web/* at the root, the core at core/, data at data/.
# Pages reference core/handoff-core.js and data/<sport>/... relative to themselves.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/_site"
rm -rf "$OUT"
mkdir -p "$OUT/core" "$OUT/data"
cp -R "$ROOT/web/." "$OUT/"
cp "$ROOT/core/handoff-core.js" "$OUT/core/"
for d in "$ROOT"/data/*/; do
  name="$(basename "$d")"
  mkdir -p "$OUT/data/$name"
  cp "$d"*.json "$OUT/data/$name/"
done
touch "$OUT/.nojekyll"
echo "Built $OUT ($(find "$OUT" -type f | wc -l | tr -d ' ') files)"
