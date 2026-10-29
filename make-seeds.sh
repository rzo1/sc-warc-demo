#!/usr/bin/env bash
# Writes the first N hosts of the Tranco list GQ32K (https://tranco-list.eu/list/GQ32K/1000000) to seeds.txt,
# as used for the StormCrawler 4.0 test crawls (https://github.com/apache/stormcrawler/discussions/2268)
set -euo pipefail
N="${1:-1000}"
LIST="${TRANCO_CSV:-tranco-GQ32K.csv}"
[ -f "$LIST" ] || curl -sfL -o "$LIST" https://tranco-list.eu/download/GQ32K/1000000
head -n "$N" "$LIST" | cut -d, -f2 | tr -d '\r' | sed 's|^|https://|; s|$|/|' > seeds.txt
wc -l < seeds.txt | xargs echo "seeds written:"
