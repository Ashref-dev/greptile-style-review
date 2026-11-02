---
name: greptile-style-review
description: Fast Greptile-style pre-PR code review by two independent reviewers on different model families (GPT via the deep category, Claude via unspecified-high), cross-checked into one report - a merge-readiness score out of 5 and findings ranked P0-P3 with file:line, trigger, impact and fix. Reviews the current branch against its base (dev, else main) or local uncommitted changes, a commit, or a PR. Uses CodeGraph, AGENTS.md/CLAUDE.md rules and LESSONS-LEARNED files. Use when the user runs /greptile-style-review or asks to "review my branch", "review before the PR", "pre-PR review", "greptile review", "score my changes", or "find bugs in my changes". Read-only; never edits code.
---

# Greptile-style review

Goal: catch the bugs Greptile or a strong human reviewer would flag, before the PR exists, fast. Deliver one clean report: a score out of 5, P0-first findings, and a clear merge verdict.

You are the orchestrator. You resolve the scope, launch two reviewers on different model families in parallel, verify and merge what they find, and write the report. You never edit code. Target wall time: under about 8 minutes for a typical branch.

## Hard rules (paste into every reviewer prompt)

1. Read-only. Allowed: `git diff/log/show/status/grep/merge-base`, `gh pr view/diff`, reading files, CodeGraph queries, code search, and quick existing local checks (type check, lint, focused tests). Forbidden: editing, formatting, committing, stashing, checkout, push, deploy, migrations, live LLM or cloud calls, anything that writes shared state.
2. You are a leaf agent. Do not spawn sub-agents or background tasks. Finish within about 50 tool calls.
3. The change is in scope; untouched pre-existing code is not, unless the change makes a problem reachable or worse. A file the diff edits is in scope as a whole: if the change updates a script, config or doc but leaves it broken or stale (for example still referencing something the same change removed), report it.
4. No finding without evidence: the changed line, a concrete trigger (input, state or path), and the consequence. "Could be a problem" is not a finding.
5. Respect decisions stated by the user, the PR description or AGENTS.md. A code comment written in the same change is not an accepted decision: if it justifies a risky behavior (publishing without a check, swallowing a failure, skipping validation on the last attempt), still report the risk, quote the rationale, and rate it P2 unless the impact is P1.
6. Not findings: style and naming preferences, nitpicks, issues a CI linter or type checker already blocks, hypothetical problems with no reachable trigger, generic advice ("add tests") with no named unprotected behavior.

## Step 1: Scope (orchestrator, a few commands, no sub-agents)

Arguments ($ARGUMENTS):
- None: if `git status --short` shows changes, review uncommitted work (`git diff`, `git diff --cached`, full content of untracked files) plus the branch's commits against the base. If clean, review the branch against its base.
- Branch name: `git diff <branch>...HEAD`. Commit hash: `git show <hash>`. PR number or URL: `gh pr view <n> --json title,body,baseRefName` and `gh pr diff <n>`. `--base <branch>` overrides the base.

Base: `dev` if it exists locally or as `origin/dev`, else `main`, else `master`. Diff from the merge base: `git diff $(git merge-base <base> HEAD)` (add `...HEAD` form for committed-only). Skip lockfiles, generated, vendored, snapshot and binary files unless they are the point of the change.

Gather only paths and short facts; reviewers read the content themselves:
1. Changed files with stat (`git diff --stat`, `--name-status`) and total changed lines.
2. Intent: `git log --oneline <base>..HEAD`, the PR body if any, and what the user said in this conversation. Note any stated decisions.
3. Rule files: every AGENTS.md, agents.md and CLAUDE.md from the repo root to each changed directory, plus the parent workspace root's if the repo sits inside a multi-repo workspace.
4. Lesson files: every LESSONS-LEARNED.md / lessons-learned.md in the repo and the workspace root.
5. Whether a CodeGraph index exists (a `.codegraph/` directory at or above the repo, or a working `codegraph_explore` tool).

Print one line, then launch immediately: "Reviewing <scope>: N files, +A/-D lines. Reviewers: GPT (deep) and Claude (unspecified-high)."

## Step 2: Two reviewers in parallel (one turn, both in the background)

Launch both in the same message:
- Reviewer G: `task(category="deep", run_in_background=true, ...)` - GPT family. Give the changed files in diff order.
- Reviewer C: `task(category="unspecified-high", run_in_background=true, ...)` - Claude family. Give the changed files in reverse order.

Both review the WHOLE change with the full checklist; diversity comes from the model family and the reading order, not from splitting the work. Check the routing notice in each launch result: if both resolved to the same model family, relaunch one on another category whose model is from the other family (for example `ultrabrain` for GPT, `artistry` for Claude) and mention it in the report.

Large changes (over about 1,500 changed lines): also launch Reviewer S on `deep`, focused only on contracts, data, ownership and security across the whole diff. Say in the report that coverage per line is thinner.

Reviewer prompt template (fill the brackets; keep it this short):

```
TASK: Read-only pre-PR code review of one change. Report bugs with evidence.
REPO: <path>   DIFF: <exact diff command>   FILES (read in this order): <list>
INTENT: <2-5 lines>   STATED DECISIONS: <list or none>
RULES: <rule file paths>   LESSONS: <lesson file paths> - read the parts that apply to the changed files.
CODEGRAPH: <"available: use codegraph_explore first for callers, blast radius and flows" | "not available">
HARD RULES: <the 6 hard rules above, verbatim>
CHECKLIST: <the checklist below, verbatim>
OUTPUT: <the candidate format below, verbatim>
```

Checklist (both reviewers):
1. Callers and contracts: for every renamed, removed, re-typed or re-shaped symbol, schema, payload, setting, env var, route or CLI flag, find every caller and consumer (CodeGraph first, then `git grep -n -w`), including sibling services in the workspace, deploy files, Dockerfiles, CI, scripts and `.env.example`. A contract change must update producer, passthrough and consumer together.
2. Logic: inverted or always-true conditions, off-by-one, wrong variable, unit or default, missing await, unreachable branches, shared-state mutation, ordering and idempotency of retried work.
3. Failure paths: errors swallowed or caught too broadly or too narrowly, fallbacks that hide failure, partial writes, retries of non-idempotent work, timeouts, cancellation, empty or null input, concurrency and races, resource leaks, blocking calls on an event loop, sessions held across slow awaits.
4. Lossy steps: every truncation, cap, limit, sample, excerpt, summary, dedup or filter the change adds or touches. What is silently dropped, and does anything downstream rely on it? Are "keep whole" items (pinned, required, primary) really exempt?
5. Gates: when the change claims a check happens (review, validation, approval, retry), find every path that skips it (last attempt, limit reached, timeout, error fallback) and confirm the skipped state is recorded and visible.
6. Persisted and durable state: when a stored model, schema, checkpoint, JSON column, cache, queue message or workflow input changes, data written by the previous version must still load (strict parsing, removed or newly required fields). Migrations must match model changes. Durable workflow code and payloads must stay replay-compatible for in-flight runs.
7. Ownership and security: who owns each record, who may read, edit or delete it; tenant or organization filters on every query; shared or public fallbacks treated as owned; auth on new endpoints; injection, path traversal, SSRF, secrets in code or logs; untrusted input validated at the boundary.
8. Rules and lessons: a rule violation needs the quoted rule and a path scope that covers the file. A change that repeats a recorded lesson is a strong finding; quote the lesson.
9. Tests: does each changed behavior have a test that fails on revert? Do new tests assert behavior rather than prose, implementation detail or self-fulfilling mocks? Did deleted tests cover behavior nothing else covers? Run the focused tests and the type checker or linter on changed files if they run locally in under about a minute.

Candidate format (one block each, then CHECKED):

```
CANDIDATE <reviewer letter><n>
priority: P0|P1|P2|P3
confidence: high|medium|low
location: path/file.ext:<start>-<end>
title: <imperative, at most 80 chars>
trigger: <input, state or path that causes it>
impact: <what goes wrong, for whom>
evidence: <quoted code, search result, test output, rule or lesson>
fix: <concrete change>
```

`CHECKED:` lists what was verified clean (callers searched, tests and checks run with results, rules checked). A reviewer with no findings returns only CHECKED.

## Step 3: Wait, then verify and merge (orchestrator)

1. Wait for the completion notifications; do not poll. If one reviewer finishes and the other is still running after roughly twice as long, or any reviewer errors or aborts, resume that same session with: "Finish now from where you stopped. Do not spawn sub-agents. Return your CANDIDATE blocks and CHECKED within 10 tool calls." If that fails, mark the reviewer INCONCLUSIVE and continue with what you have; never count it as clean.
2. Merge candidates that share a root cause into one finding: keep the strongest evidence, the most precise location, and the highest justified priority. Tag each finding: Found by both / GPT only / Claude only.
3. Verify yourself, quickly and in proportion:
   - Found by both: accept after a sanity check of the location and evidence.
   - Single-reviewer P0 or P1: read the cited code and its guards, callers or tests and confirm the trigger is reachable. Run a focused test or tiny read-only check if that settles it. Downgrade or drop if not confirmed.
   - Single-reviewer P2 or P3: keep only if the evidence is concrete and you see no guard that prevents it.
   - Drop anything that breaks a hard rule (pre-existing, style, linter-level, hypothetical, contradicts a stated decision).
   - If there are more than about 10 single-reviewer candidates to check, you may launch one leaf validator on `unspecified-high` with only those candidates, asking it to return CONFIRMED / DOWNGRADED / REJECTED with evidence for each.
4. Count candidates found, confirmed and rejected for the report.

## Priorities and score

Priorities:
- P0: drop everything. Breaks production for most users, loses or corrupts data, crosses a tenant boundary, exposes secrets or a security hole, breaks the build, or breaks in-flight durable work. Holds regardless of input assumptions.
- P1: fix before merge. A real bug on a plausible path, a broken cross-service contract, a failure path that turns a recoverable error into an outage, or a violation of a rule marked critical or protected.
- P2: should fix. Bug on a less likely path, a risky behavior change without a test, a skipped gate justified only by a new comment, a recorded lesson repeated with limited blast radius.
- P3: minor. Low-impact edge case, misleading docs or comments, small dead or stale code left by the change.

Score (merge readiness, Greptile's convention, not a probability):
- 5/5: no P0, P1 or P2. Safe to merge.
- 4/5: no P0 or P1, at most one easy P2, any P3s.
- 3/5: one P1, or two or more P2s.
- 2/5: two or more P1s, or one P1 with wide impact.
- 1/5: any P0. 0/5: several P0s, or the change does not do what it claims.
Lower by one if a reviewer was INCONCLUSIVE or coverage was thinned, and say why.

## Step 4: Report (plain text, in chat)

```
Greptile-style review: <scope line>
Confidence Score: N/5 - <one sentence on why>
Verdict: Safe to merge | Fix before merge | Do not merge

Summary
- 2-4 bullets: what the change does and the main risk.

Findings
P1-1 <title>  [found by both | GPT only | Claude only]
  Where: path/file.ext:123-130
  Trigger: <input or path>
  Impact: <what breaks>
  Fix: <concrete change>
P2-1 ...
(or "None")

Important files
- path/file.ext - what changed and its risk, one line each, riskiest first, at most 8.

Verified
- Reviewers: GPT (<resolved model>) done, Claude (<resolved model>) done, or INCONCLUSIVE.
- Candidates: X found, Y confirmed, Z rejected (one line on what was rejected).
- Checks run and results, or "static review only".

Notes
- Stated decisions respected; follow-ups outside the change (max 3 lines).
```

Order findings P0, P1, P2, P3. Keep labels stable (P1-1, P2-1, ...). On a re-review after fixes, list each previous finding as Fixed, Still open or Withdrawn first, then new findings, then the new score. The report is the deliverable: do not start fixing unless the user asks.
