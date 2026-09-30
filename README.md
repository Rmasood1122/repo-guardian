# repo-guardian

**A read-only auditor that tells you the truth about your repositories — and a small kit that keeps future ones honest.**

Built by a solo AI-assisted developer from ten months of logged, dated failures: reports silently overwritten, errors committed as valid data, percentages quoted off five samples, a database file sitting in a public repo, secrets found in git history months after "deleting" them. Every check in this tool exists because one of those actually happened. Nothing here is advice — each rule is a code path that refuses.

## Privacy
`audit-repo.sh` reads your code **locally, on your machine**. It makes a read-only throwaway clone, scans it, writes a Markdown report next to the tool, and deletes the clone. **Nothing leaves your machine.** Secret findings are printed redacted (first/last two characters only).

## Quickstart
See [QUICKSTART.md](QUICKSTART.md) — clone to first report in under 15 minutes.

## What's here
| Path | What it does |
|---|---|
| `scripts/audit-repo.sh` | Audits one repo: commit health, hotspots, gate presence, junk, tracked `.db`/`.env` artifacts, redacted secret scan; `--history` scans **all git history** (run it before ever making a repo public) |
| `scripts/audit-all.sh` | Fleet scan with run-manifest arithmetic (OK runs must equal reports on disk — lost work refuses to hide) and duplicate-repo detection |
| `scripts/smoke.sh` | Proves the auditor itself works, against planted defects, before you trust it |
| `kit/` | Drop into any new repo: commit-msg hook + CLAUDE.md / decisions.md / LEDGER.md templates |
| `.github/workflows/audit-ci.yml` | Runs the same planted-defect smoke on every push — the tools are tested on a machine that isn't yours |

## Design rules (the ones that held)
- **Fail closed.** An errored run produces no report. A missing index is a failure, never a skip.
- **Denominators everywhere.** Ratios are suppressed below n=20; every count prints what it's out of.
- **Seen-it-fire.** No detector is trusted until it's been observed catching a planted defect — `smoke.sh` and CI do exactly that on every change.
- **Refuse, don't warn.** Re-auditing the same repo the same day refuses instead of overwriting.

## Requirements
bash ≥ 4 (the script checks and tells you; macOS: `brew install bash`), git. That's all.

## Feedback
Found a false positive, a blocker, or a defect class the auditor should catch? [Open an issue](../../issues/new/choose) — the feedback template takes two minutes and every report improves the fixtures.

## License
MIT.
