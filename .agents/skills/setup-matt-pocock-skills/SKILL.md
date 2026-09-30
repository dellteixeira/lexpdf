---
name: setup-matt-pocock-skills
description: "Configure this repo for the engineering skills: set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills."
disable-model-invocation: true
---

# Setup Matt Pocock's Skills

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker**: where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels**: the strings used for the five canonical triage roles
- **Domain docs**: where `GLOSSARY.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config`: is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root
- `GLOSSARY.md` and `GLOSSARY-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/`
- `.scratch/`
- whether the `triage` skill is installed
- monorepo signals

### 2. Configure

Use GitHub when the repo remote points to GitHub. Skip triage labels when `triage` is not installed. Default domain docs to single-context unless genuine monorepo signals exist.

Record configuration in:
- `docs/agents/issue-tracker.md`
- `docs/agents/domain.md`
- `docs/agents/triage-labels.md` only when triage is installed

Add or update an `## Agent skills` block in the existing `CLAUDE.md` or `AGENTS.md`. If neither exists, the user chooses which to create.

### 3. Done

Tell the user which engineering skills now read from these files. Re-run only when switching issue trackers or restarting configuration.
