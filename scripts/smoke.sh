#!/usr/bin/env bash
# smoke.sh — the ONE command to run before any push that touches the auditor.
# Same fixtures CI runs; green here then green in CI, or neither counts.
set -e
cd "$(dirname "$0")/.."

bash -n scripts/audit-repo.sh
bash -n scripts/audit-all.sh
echo "SYNTAX_OK"

rm -rf /tmp/fx1 /tmp/fx2 /tmp/aud && mkdir -p /tmp/fx1/core/tests /tmp/aud
( cd /tmp/fx1 && git init -q && git config user.email a@b.c && git config user.name t \
  && echo x > core/tests/test_a.py && git add -A && git commit -qm "feat: fx" \
  && echo y > core/notes.md && git add -A && git commit -qm "docs: fx notes" \
  && echo z > core/z && git add -A && git commit -qm "no prefix here" )

out="$(bash scripts/audit-repo.sh /tmp/fx1 /tmp/aud)"
echo "$out" | grep -q 'TESTS=YES'   || { echo "FAIL U3: nested tests not found"; exit 1; }
echo "$out" | grep -q 'SUPPRESSED'  || { echo "FAIL U4: ratio printed on n<20"; exit 1; }
# U12: hook-valid prefixes (docs:) must NOT count as unprefixed; a truly
# unprefixed commit still must (still-blocks: the loosened check still fires).
echo "$out" | grep -q 'PREFIXED=2 PASSTHRU=0 UNPREFIXED=1 ' || { echo "FAIL U12: auditor/hook prefix disagreement"; exit 1; }

git init -q /tmp/fx2
bash scripts/audit-repo.sh /tmp/fx2 /tmp/aud && { echo "FAIL U2: empty repo did not skip"; exit 1; } || true
ls /tmp/aud/*fx2* 2>/dev/null && { echo "FAIL U2: report written for empty repo"; exit 1; } || true

bash scripts/audit-repo.sh /tmp/fx1 /tmp/aud && { echo "FAIL U1: overwrite not refused"; exit 1; } || true

[ "$(ls /tmp/aud/ | wc -l)" -eq 1 ] || { echo "FAIL U1: expected exactly one report"; exit 1; }

# ---- v2.2 detectors: tracked artifact + history-only secret, both seen firing ----
rm -rf /tmp/fx3 /tmp/aud3 && mkdir -p /tmp/fx3 /tmp/aud3
( cd /tmp/fx3 && git init -q && git config user.email a@b.c && git config user.name t \
  && echo x > app.db && printf 'k="sk-%s"\n' "smokeplantAAAA1234567890" > leak.txt \
  && git add -A && git commit -qm "feat: dirty history" \
  && git rm -q leak.txt && git commit -qm "fix: remove leak (still in history)" )
out3="$(bash scripts/audit-repo.sh /tmp/fx3 /tmp/aud3 --history)"
echo "$out3" | grep -q 'HIT \[tracked_artifact\] app.db' || { echo "FAIL v2.2: tracked .db not flagged"; exit 1; }
echo "$out3" | grep -q 'HIST-HIT \[sk_family_key\]'      || { echo "FAIL v2.2: history-only secret not found by --history"; exit 1; }
echo "$out3" | grep -q 'FILES_SCANNED=.* HITS=0 '        || { echo "FAIL v2.2: tree scan should be clean after removal"; exit 1; }

echo "SMOKE_PASS: U1 U2 U3 U4 U12 + v2.2 (tracked_artifact, history scan) fired and held"
