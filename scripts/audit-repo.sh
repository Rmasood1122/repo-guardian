#!/usr/bin/env bash
# audit-repo.sh — read-only audit of any git repository. Part of repo-guardian.
# Every check exists because a real failure earned it; every rule is a code path:
#  U1 collision-proof report names + refuse-overwrite  (reports lost to silent overwrite)
#  U2 fail closed: an errored/empty repo produces NO report (errors committed as data)
#  U3 nested test-dir detection                         (false "no tests" verdicts)
#  U4 ratios suppressed below n=20, denominators printed (tiny samples stated as facts)
#  U5 line-level secret scan with redacted evidence     (leaks found months late)
#  v2.2: fail-closed bash>=4 guard (stock macOS bash 3.2 dies mid-script otherwise),
#        tracked .db/.sqlite/.env detector (a committed database IS a leak),
#        --history mode: full-history secret scan, required before any repo goes public.
# Usage: bash scripts/audit-repo.sh /path/to/repo [audits_dir] [--history]
set -u

# ---------- v2.2: refuse old bash WITH a reason, before any 4+-only syntax runs ----------
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "REFUSED: bash >= 4 required (this is bash ${BASH_VERSION:-unknown})." >&2
  echo "macOS ships bash 3.2 — install a modern bash:  brew install bash  — then re-run." >&2
  exit 4
fi

REPO="${1:?usage: audit-repo.sh <repo-path> [audits-dir] [--history]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDITS="${2:-$ROOT/audits}"
HISTORY_SCAN=0
for arg in "$@"; do [ "$arg" = "--history" ] && HISTORY_SCAN=1; done
[ "$AUDITS" = "--history" ] && AUDITS="$ROOT/audits"
RUNLOG="$ROOT/runs/RUNLOG-$(date +%F)-$(hostname 2>/dev/null || echo host).txt"
mkdir -p "$AUDITS" "$ROOT/runs"
DATE="$(date +%F)"

log() { echo "$(date +%T) $*" >> "$RUNLOG"; }

# ---------- U1: collision-proof, path-keyed report name ----------
SAFE="$(echo "$REPO" | sed -e 's|^/c/Users/[^/]*/||' -e 's|[/ ]|__|g' -e 's|[^A-Za-z0-9._-]|_|g')"
REPORT="$AUDITS/${SAFE}-${DATE}.md"
if [ -e "$REPORT" ]; then
  echo "REFUSED: $REPORT already exists (fail closed — U1). Delete it explicitly to re-audit." >&2
  log "REFUSED_OVERWRITE $REPO -> $REPORT"
  exit 3
fi

# ---------- U2: fail closed — no valid HEAD, no report file ----------
if ! git -C "$REPO" rev-parse HEAD >/dev/null 2>&1; then
  log "SKIPPED_EMPTY_OR_BROKEN $REPO"
  echo "EMPTY_REPO STATUS=SKIPPED $REPO (no report written — U2)"
  exit 2
fi

# ---------- read-only throwaway clone (source untouched) ----------
SBX="$(mktemp -d)"
trap 'rm -rf "$SBX"' EXIT
if ! git clone --quiet --no-hardlinks "$REPO" "$SBX/clone" 2>>"$RUNLOG"; then
  log "SKIPPED_CLONE_FAIL $REPO"
  echo "CLONE_FAIL STATUS=SKIPPED $REPO (no report written — U2)"
  exit 2
fi
C="$SBX/clone"

# ---------- commit health ----------
TOTAL=$(git -C "$C" rev-list --count HEAD)
FEAT=$(git -C "$C" log --oneline | grep -ciE '^[0-9a-f]+ feat(\(|:)' || true)
FIX=$(git -C "$C"  log --oneline | grep -ciE '^[0-9a-f]+ fix(\(|:)'  || true)
# U12: UNPREFIXED counts against the SAME set the kit commit-msg hook accepts —
# the auditor and the hook must never disagree on what a prefix is.
HOOK_PREFIXES='feat|fix|docs|chore|test|refactor|audit|ci'
PREFIXED=$(git -C "$C" log --oneline | grep -cE "^[0-9a-f]+ ($HOOK_PREFIXES)(\([a-z0-9_-]+\))?: " || true)
PASSTHRU=$(git -C "$C" log --oneline | grep -cE '^[0-9a-f]+ (Merge|Revert|fixup!|squash!)' || true)
MERGES=$(git -C "$C" rev-list --merges --count HEAD)
TAGS=$(git -C "$C" tag | wc -l | tr -d ' ')
DEN=$((FEAT + FIX))
UNPREFIXED=$((TOTAL - PREFIXED - PASSTHRU))
LAST=$(git -C "$C" log -1 --format=%cd --date=short)
DORMANT_DAYS=$(( ( $(date +%s) - $(git -C "$C" log -1 --format=%ct) ) / 86400 ))

# U4: suppress ratio below n=20
if [ "$DEN" -ge 20 ]; then
  RATIO="$(( FIX * 100 / DEN ))% [EST: prefix-based; denominator FEAT+FIX=$DEN; UNPREFIXED=$UNPREFIXED uncounted]"
else
  RATIO="SUPPRESSED (FEAT+FIX=$DEN < 20; raw counts only — U4) UNPREFIXED=$UNPREFIXED"
fi

# ---------- hotspots + U7 session-prose metric ----------
HOTSPOTS="$(git -C "$C" log --name-only --format= | grep -v '^$' | sort | uniq -c | sort -rn | head -5)"
SESSION_PROSE_TOUCHES=$(git -C "$C" log --name-only --format= | grep -v '^$' \
  | grep -ciE '(CONTINUATION|SESSION|STATE\.md|REGISTER\.md|START_HERE|_state\.(md|json))' || true)

# ---------- gates ----------
CI_FILES=$(find "$C/.github/workflows" -name '*.yml' -o -name '*.yaml' 2>/dev/null | wc -l | tr -d ' ')
[ "$CI_FILES" -gt 0 ] && CI="YES ($CI_FILES file(s)) — verify a run has actually fired on GitHub" || CI="NO"
TESTS_GLOB='**/tests/ dirs OR **/test_*.py|*.test.*|*_test.go'
TESTS_HITS=$(find "$C" -path "$C/.git" -prune -o \( -type d -name tests -print \) -o \( -type f \( -name 'test_*.py' -o -name '*.test.ts' -o -name '*.test.js' -o -name '*_test.go' \) -print \) 2>/dev/null | wc -l | tr -d ' ')
[ "$TESTS_HITS" -gt 0 ] && TESTS="YES ($TESTS_HITS match(es); glob: $TESTS_GLOB)" || TESTS="NO (glob: $TESTS_GLOB)"
g() { [ -e "$C/$1" ] && echo YES || echo NO; }
CLAUDE_MD=$(g CLAUDE.md); DECISIONS=$(g decisions.md); LEDGER=$(g LEDGER.md)
GATTR=$(g .gitattributes); ENVEX=$(g .env.example)

# ---------- U9: junk detector ----------
JUNK="$(find "$C" -path "$C/.git" -prune -o \( -name '__pycache__' -o -name '*.pyc' -o -name '*.tar.gz' -o -name '*.tmp' \) -print 2>/dev/null | sed "s|$C/||" | head -10)"
JUNK_COUNT=$(echo "$JUNK" | grep -c . || true)

# ---------- v2.2: tracked data artifacts — a committed DB or .env is a leak, not junk ----------
ARTIFACTS="$(git -C "$C" ls-files | grep -E '\.(db|sqlite3?)$|(^|/)\.env$' || true)"
ARTIFACT_COUNT=$(echo "$ARTIFACTS" | grep -c . || true)
ARTIFACT_LINES=""
if [ "$ARTIFACT_COUNT" -gt 0 ]; then
  while IFS= read -r f; do
    ARTIFACT_LINES="${ARTIFACT_LINES}HIT [tracked_artifact] $f"$'\n'
  done <<< "$ARTIFACTS"
fi

# ---------- U5: secrets — every pattern verified against a known-positive fixture ----------
declare -A PATTERNS=(
  [sk_family_key]='sk-[A-Za-z0-9_-]\{16,\}'
  [aws_key]='AKIA[0-9A-Z]\{16\}'
  [github_token]='ghp_[A-Za-z0-9]\{20,\}'
  [slack_token]='xox[baprs]-[A-Za-z0-9-]\{10,\}'
  [private_key]='-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
SECRETS=""; HITS=0
FILES_SCANNED=$(find "$C" -path "$C/.git" -prune -o -type f -print 2>/dev/null | wc -l | tr -d ' ')
for name in "${!PATTERNS[@]}"; do
  while IFS=: read -r f ln match; do
    [ -z "$f" ] && continue
    HITS=$((HITS+1))
    m="$(echo "$match" | grep -o "${PATTERNS[$name]}" | head -1)"
    red="$(echo "$m" | sed -E 's/^(..).*(..)$/\1…\2/')"
    SECRETS="${SECRETS}HIT [$name] ${f#$C/}:$ln  context: $red"$'\n'
  done < <(grep -rIn -e "${PATTERNS[$name]}" "$C" --exclude-dir=.git 2>/dev/null || true)
done

# ---------- v2.2: --history — scan every committed version, not just HEAD's tree ----------
HIST_HITS=0; HIST_LINES=""
if [ "$HISTORY_SCAN" -eq 1 ]; then
  for name in "${!PATTERNS[@]}"; do
    n=$(git -C "$C" log --all -p 2>/dev/null | grep -c -e "${PATTERNS[$name]}" || true)
    if [ "$n" -gt 0 ]; then
      HIST_HITS=$((HIST_HITS + n))
      HIST_LINES="${HIST_LINES}HIST-HIT [$name] x$n (occurrences across all history diffs; locate: git log --all -p -S'<match>')"$'\n'
    fi
  done
fi

# ---------- report ----------
{
echo "# Audit: $(basename "$REPO") — $DATE"
echo "SOURCE_PATH=$REPO"
if [ "$HISTORY_SCAN" -eq 1 ]; then
  echo "SCOPE=single repo, working tree at HEAD + FULL-HISTORY secret scan (all branches); REMOTES NOT ENUMERATED (U10)"
else
  echo "SCOPE=single repo, working tree at HEAD; HISTORY NOT SCANNED for secrets — required before any visibility flip (re-run with --history); REMOTES NOT ENUMERATED (U10)"
fi
echo "Read-only throwaway clone; source untouched."
echo
echo "## Commit health"
echo "COMMITS_TOTAL=$TOTAL FEAT=$FEAT FIX=$FIX PREFIXED=$PREFIXED PASSTHRU=$PASSTHRU UNPREFIXED=$UNPREFIXED MERGES=$MERGES TAGS=$TAGS"
echo "REWORK_RATIO_EST=$RATIO"
echo "LAST_COMMIT=$LAST DORMANT_DAYS=$DORMANT_DAYS"
echo
echo "## Hotspot files (top 5 by total touches)"
echo "$HOTSPOTS"
echo "SESSION_PROSE_TOUCHES=$SESSION_PROSE_TOUCHES  # U7: >10 = repo memory living in rewrite-churn prose"
echo
echo "## Gates present (existence only — seen-it-fire NOT verified here)"
echo "CI_WORKFLOWS=$CI"
echo "TESTS=$TESTS"
echo "CLAUDE_MD=$CLAUDE_MD"
echo "DECISIONS_MD=$DECISIONS"
echo "LEDGER_MD=$LEDGER"
echo "GITATTRIBUTES=$GATTR"
echo "ENV_EXAMPLE=$ENVEX"
echo
echo "## Junk in tree (U9)"
if [ "$JUNK_COUNT" -gt 0 ]; then echo "$JUNK"; else echo "none"; fi
echo "JUNK_COUNT=$JUNK_COUNT"
echo
echo "## Tracked data artifacts (committed .db/.sqlite/.env)"
if [ "$ARTIFACT_COUNT" -gt 0 ]; then printf '%s' "$ARTIFACT_LINES"; else echo "none"; fi
echo "ARTIFACT_COUNT=$ARTIFACT_COUNT"
echo
echo "## Secret patterns (working tree at HEAD)"
[ -n "$SECRETS" ] && printf '%s' "$SECRETS"
echo "FILES_SCANNED=$FILES_SCANNED HITS=$HITS STATUS=COMPLETE"
echo
if [ "$HISTORY_SCAN" -eq 1 ]; then
  echo "## Secret patterns (FULL HISTORY, all branches — required before any visibility flip)"
  [ -n "$HIST_LINES" ] && printf '%s' "$HIST_LINES"
  echo "HISTORY_HITS=$HIST_HITS STATUS=COMPLETE"
else
  echo "## Secret patterns (history): NOT SCANNED — run with --history before any visibility flip"
fi
echo
echo "## Findings queue (fill by hand after reading the numbers)"
echo "| Finding | Concept violated | Fix | Status |"
echo "|---------|------------------|-----|--------|"
} > "$REPORT"

cat "$REPORT"
log "OK $REPO -> $REPORT"
echo
echo "Report saved: $REPORT  (target repo untouched; sandbox deleted)"
