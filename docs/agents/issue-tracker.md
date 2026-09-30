# Issue tracker: GitHub

Issues, specifications, and implementation tickets for this repository live in GitHub Issues in `dellteixeira/lexpdf`.

## Conventions

- Create: `gh issue create --title "..." --body "..."`
- Read: `gh issue view <number> --comments`
- List: `gh issue list --state open --json number,title,body,labels,comments`
- Comment: `gh issue comment <number> --body "..."`
- Close: `gh issue close <number> --comment "..."`

When a skill says **publish to the issue tracker**, create a GitHub issue.

When a skill says **fetch the relevant ticket**, read the corresponding GitHub issue and its comments.

## Pull requests as request surface

PRs as a request surface: **no**.

## LexPDF review context

For reviews, always pin an explicit fixed point and compare with three-dot diff semantics against the merge-base. Do not silently replace a user-specified fixed point. PR #233 and related GitHub issues/specifications may be used as intent sources when relevant.
