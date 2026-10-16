#!/usr/bin/env bash
# Build _site/ and serve it at http://localhost:8765/
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/tools/build_site.sh"
echo "Serving http://localhost:${PORT:-8765}/  (Ctrl+C to stop)"
exec python3 -m http.server "${PORT:-8765}" -d "$ROOT/_site"
