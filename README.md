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
- **Reports only, unless you ask for fixes.** Say "review and fix" (or ask after the report) and the agent fixes the confirmed findings, adds tests, and reviews again.

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
2. **Review.** Two sub-agents get the same self-contained brief ([references/reviewer-brief.md](references/reviewer-brief.md)). Reviewer A focuses on correctness and contracts and reads the files in diff order. Reviewer B focuses on failure paths, security and tests and reads them in reverse order.
3. **Verify.** The main agent merges duplicates, re-reads the code behind every single-reviewer finding, and drops anything not introduced by the change, not reachable, already guarded, or just style.
4. **Report.** Score, findings, summary, diagram, details, and a footer saying who reviewed and what actually ran.

## Tips

- Commit or stage the work first if you only want the branch reviewed: the default scope includes uncommitted changes.
- Keep rules in `AGENTS.md` or `CLAUDE.md`. Reviewers quote them when a change breaks one.
- A `LESSONS-LEARNED.md` in the repo is read too. A change that repeats a recorded mistake is reported as a strong finding.

## License

MIT
