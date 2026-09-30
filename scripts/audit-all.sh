#!/usr/bin/env bash
# audit-all.sh — fleet scan with run-manifest arithmetic and duplicate detection.
# The manifest is the point: OK runs MUST equal reports on disk, or a report was
# lost or duplicated and the batch refuses to be committed.
# Usage: bash scripts/audit-all.sh [scan_root]    (default: $HOME, 3 levels deep)
set -u
cd "$(dirname "$0")/.." || exit 1
SELF="$(pwd)"
SCAN_ROOT="${1:-$HOME}"

DATE="$(date +%F)"
RUNLOG="runs/RUNLOG-$DATE-$(hostname 2>/dev/null || echo host).txt"
mkdir -p runs audits
RUNS=0; OK=0; SKIPS=0; REFUSED=0

for repo in $(find "$SCAN_ROOT" -maxdepth 3 -name .git -type d 2>/dev/null | sed 's|/.git$||'); do
  [ "$(cd "$repo" && pwd)" = "$SELF" ] && continue   # never audit self by path, not by name
  RUNS=$((RUNS+1))
  echo "=== auditing $repo ==="
  bash scripts/audit-repo.sh "$repo"
  case $? in
    0) OK=$((OK+1));;
    2) SKIPS=$((SKIPS+1));;
    3) REFUSED=$((REFUSED+1));;
    *) SKIPS=$((SKIPS+1)); echo "$(date +%T) UNKNOWN_ERR $repo" >> "$RUNLOG";;
  esac
done

echo
echo "## RUN MANIFEST $DATE"
REPORTS=$(ls audits/*-"$DATE".md 2>/dev/null | wc -l | tr -d ' ')
echo "RUNS=$RUNS OK=$OK SKIPPED=$SKIPS REFUSED=$REFUSED REPORTS_ON_DISK=$REPORTS"
if [ "$OK" -ne "$REPORTS" ]; then
  echo "MANIFEST_FAIL: OK runs ($OK) != reports on disk ($REPORTS) — a report was lost or duplicated. DO NOT COMMIT." | tee -a "$RUNLOG"
  exit 1
fi
echo "MANIFEST_OK"

echo
echo "## DUPLICATE CANDIDATES (same repo basename across paths — pick one canonical copy)"
grep -h '^SOURCE_PATH=' audits/*-"$DATE".md 2>/dev/null | sed 's|SOURCE_PATH=||' \
  | awk -F/ '{print $NF"\t"$0}' | sort | awk -F'\t' '
    {count[$1]++; paths[$1]=paths[$1]"\n    "$2}
    END {for (b in count) if (count[b]>1) printf "  %s (%d copies):%s\n", b, count[b], paths[b]}'

echo
echo "## DORMANT >60d (archive candidates unless defended)"
for f in audits/*-"$DATE".md; do
  [ -e "$f" ] || continue
  d=$(grep -o 'DORMANT_DAYS=[0-9]*' "$f" | cut -d= -f2)
  [ -n "$d" ] && [ "$d" -gt 60 ] && echo "  $(grep '^SOURCE_PATH=' "$f" | cut -d= -f2)  ($d days)"
done
