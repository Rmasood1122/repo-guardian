# Quickstart — first audit in under 15 minutes
1. `git clone https://github.com/Rmasood1122/repo-guardian && cd repo-guardian`
2. Check bash: `bash --version` — need ≥ 4. macOS: `brew install bash`. Windows: Git Bash works as-is.
3. Prove the auditor works before trusting it: `bash scripts/smoke.sh` → must end `SMOKE_PASS`.
4. Audit one of your repos: `bash scripts/audit-repo.sh /path/to/your/repo`
5. Read the report it names (saved under `audits/`): commit health, tests/CI presence, junk, tracked `.db`/`.env` files, redacted secret hits.
6. Before making any repo public, ALWAYS: `bash scripts/audit-repo.sh /path/to/repo audits --history`
7. Fleet scan (all repos under your home): `bash scripts/audit-all.sh` — `MANIFEST_OK` or it tells you a report was lost.
8. New project? Copy `kit/` in: `cp kit/commit-msg your-repo/.git/hooks/ && chmod +x your-repo/.git/hooks/commit-msg`, and use the three template files as your repo's memory.
9. Something broke or looks wrong? Open an issue with the feedback template — include the minutes it took and where you got stuck.
10. Re-run anytime; same-day re-audits refuse to overwrite (delete the old report explicitly — that's on purpose).
