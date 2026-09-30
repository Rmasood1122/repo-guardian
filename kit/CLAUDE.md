# CLAUDE.md — session contract (kit template; copy into every new repo)
Resume protocol: a fresh session reads, in order: LEDGER.md, decisions.md, this file. Nothing lives only in chat.
- Every claim binds to a test, a command output, or a receipt. No attestation-shaped output.
- Fail closed: an errored run produces no artifact; every count prints its denominator.
- Seen-it-fire: no detector or gate is trusted until observed catching a planted defect.
- Commits: feat:/fix:/docs:/chore: prefixes (kit/commit-msg enforces at commit time).
- Before any push that touches tooling: run the repo's smoke script. Green-at-destination is the only green.
