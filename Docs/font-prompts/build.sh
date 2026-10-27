#!/bin/bash
# Assembles one ready-to-paste design-tool prompt per font into ready/<Name>.txt
# from common.txt (shared requirements) and briefs.txt (one style per "=== Name | Title ===" block).
# Usage: Docs/font-prompts/build.sh
set -euo pipefail
cd "$(dirname "$0")"
rm -rf ready && mkdir ready

awk '
  /^=== .* ===$/ {
    if (out) close(out)
    header = $0
    sub(/^=== /, "", header); sub(/ ===$/, "", header)
    split(header, parts, " \\| ")
    name = parts[1]; title = parts[2]
    out = "ready/.brief-" name ".tmp"
    print title > out
    next
  }
  out { print >> out }
' briefs.txt

for brief in ready/.brief-*.tmp; do
  name=$(basename "$brief" .tmp); name=${name#.brief-}
  title=$(head -n 1 "$brief")
  nospace=${name// /}
  {
    sed -e "s/{NAME}/$name/g" -e "s/{NAMENOSPACE}/$nospace/g" common.txt
    echo "$title."
    tail -n +2 "$brief"
  } > "ready/Lyra-$nospace.txt"
  rm "$brief"
done

ls -1 ready | sed 's/^/  /'
