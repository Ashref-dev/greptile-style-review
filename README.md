# greptile-style-review

A Greptile-style code review your coding agent runs locally, before you open the PR.

Two reviewer sub-agents read the change in parallel, each with a different focus. The main agent then checks every finding against the code and drops what doesn't hold up. You get a report formatted like a Greptile PR comment, starting with the line you care about:

```
## Confidence Score: 3/5 — 1 P1 · 2 P2
```

The skill names no models or agent types: it asks your harness for two sub-agents, preferably of different kinds, and lets the harness pick. It works in OpenCode (with or without oh-my-openagent), Claude Code, Codex, or any harness that loads Agent Skills. Without sub-agents, the main agent does both passes itself.

## What you get

```markdown
## Confidence Score: 2/5 — 2 P1 · 1 P2

**[High impact]** The change adds subscription renewals driven by Stripe webhooks.

Do not merge until webhook signatures are enforced and renewals extend from the current period end; duplicate deliveries should also be handled.

### Findings
1. 🟠 **P1** · 🔒 **Unsigned webhooks are accepted** — `billing/webhooks.py:31`
2. 🟠 **P1** · **Renewals restart from the payment date** — `billing/renewals.py:58`
3. 🟡 **P2** · **Retried deliveries extend twice** — `billing/renewals.py:44`

### Summary
...
### Diagram
...
### Details
(trigger, impact and fix for each finding)
```

- **Score**: Greptile's 0-5 merge-readiness scale. Any P0 gives 0/5. Otherwise the score is 5 minus the number of P1s, P2-only gives 4/5, and a security P1 costs one extra point. These rules reproduce Greptile's own score on 96% of 722 real Greptile reviews.
- **Priorities**: P0 drop everything, P1 fix before merge, P2 should fix, P3 minor.
- **Three modes**, picked from how you ask:
  - *Review* (default): the report, nothing else. No code changes.
  - *Review and fix* ("review it, then fix the bugs"): report, fix the confirmed findings with tests, re-review, and finish with a summary.
  - *Target score* ("keep going until 5/5"): review, fix and re-review in a loop until the score reaches the target (at most 5 rounds, and it stops early if a round doesn't improve the score).

## Install

The skill lives in `~/.agents/skills`, the shared location for Agent Skills, which OpenCode and Codex read directly:

```bash
git clone https://github.com/Ashref-dev/greptile-style-review ~/.agents/skills/greptile-style-review
```

Claude Code reads `~/.claude/skills`, so also link it there:

```bash
mkdir -p ~/.claude/skills && ln -s ~/.agents/skills/greptile-style-review ~/.claude/skills/greptile-style-review
```

Update later with `git -C ~/.agents/skills/greptile-style-review pull`.

To install for a single project instead, clone into `<repo>/.agents/skills/greptile-style-review`, or `<repo>/.claude/skills/...` for Claude Code.

You can also use the [skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add Ashref-dev/greptile-style-review -g
```

## Use

| Host | Command |
|---|---|
| OpenCode | `/greptile-style-review`, or "review my branch" |
| Claude Code | `/greptile-style-review` |
| Codex | `$greptile-style-review` |

Arguments are optional:

```
/greptile-style-review                 # current branch vs dev (else main), plus uncommitted work
/greptile-style-review 1234            # a GitHub PR by number or URL (needs gh)
/greptile-style-review a1b2c3d         # a single commit
/greptile-style-review --base release  # a different base branch
```

Or ask in plain words: "review my changes before I open the PR", "is this branch ready to merge?", "review and fix".

## How it works

1. **Scope.** `scripts/scope.sh` pins the diff range and lists the changed files, commits, and the repo's rule files (`AGENTS.md`, `CLAUDE.md`, `greptile.json`, `.coderabbit.yaml`, lessons-learned files).
2. **Review.** Two sub-agents get the same self-contained brief ([references/reviewer-brief.md](references/reviewer-brief.md)). Each one first learns how the repo already does things: rule and lesson files, sibling implementations of the same pattern, the tests of the touched code, and the git history of the changed lines (so a change that undoes an old fix gets caught). Then they dig where bugs concentrate (incomplete changes, conditions, error paths, contracts, state, deleted code, trust boundaries, tests) and prove each candidate by tracing concrete values through the code. Reviewer A and reviewer B each go deepest on a different half of that list and read the files in opposite orders.
3. **Verify.** The main agent merges duplicates, re-reads the code behind every single-reviewer finding, and drops anything not introduced by the change, not reachable, already guarded, or just style.
4. **Report.** Score, findings, summary, diagram, details, and a footer saying who reviewed and what actually ran.

## Tips

- Commit or stage the work first if you only want the branch reviewed: the default scope includes uncommitted changes.
- Keep rules in `AGENTS.md` or `CLAUDE.md`. Reviewers quote them when a change breaks one.
- A `LESSONS-LEARNED.md` in the repo is read too. A change that repeats a recorded mistake is reported as a strong finding.

## License

MIT
