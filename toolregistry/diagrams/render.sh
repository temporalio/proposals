#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

DOT=$(command -v dot 2>/dev/null || echo /opt/homebrew/bin/dot)

if ! command -v "$DOT" >/dev/null 2>&1; then
  echo "ERROR: graphviz 'dot' not found. Install with: brew install graphviz" >&2
  exit 1
fi

count=0
for f in *.dot; do
  [ -f "$f" ] || continue
  out="${f%.dot}.svg"
  echo "  $f → $out"
  "$DOT" -Tsvg "$f" -o "$out"
  count=$((count + 1))
done

echo ""
echo "Done. $count SVGs rendered."
