# Launching the reviewers

Each reviewer gets the same kind of prompt: the filled-in REVIEW HEADER followed by the whole of reviewer-brief.md. Launch every reviewer in one message so they run in parallel. Reviewers are leaf agents: they must not spawn agents of their own.

## OpenCode with oh-my-openagent (OmO)

The `task` tool takes `category`. Use two categories that run on different model families, which is the main reason to prefer this setup:

```
task(category="deep-low", run_in_background=true, load_skills=[], description="Reviewer A: <scope>", prompt="<header A + brief>")
task(category="unspecified-high", run_in_background=true, load_skills=[], description="Reviewer B: <scope>", prompt="<header B + brief>")
```

- Always pass `run_in_background=true`: when it is omitted the call blocks, and the reviewers run one after the other.
- Older OmO versions call the first category `deep`. If `deep-low` is rejected, use `deep`.
- Check that A and B resolved to different model families (the launch output or the reviewer's REVIEWER line names the model). If they did not, and `~/.omo/omo.jsonc` or `.omo/omo.jsonc` maps another category to the other family (often `ultrabrain` for GPT, `artistry` for Claude), relaunch B on it. Otherwise continue and note it in the footer.
- End your turn after launching. Collect each result with `background_output(task_id="bg_...")` when its completion notice arrives. To ask a reviewer to finish, use `task(task_id="ses_...", run_in_background=true, prompt="Finish now: return your report within 10 tool calls.")`.

## OpenCode

The `task` tool takes `subagent_type` (newer versions call it `agent`). Make two `task` calls with the `general` subagent in one message. They run in parallel and each returns its report as the tool result. `general` can edit files, so the brief's read-only rule is what keeps it read-only. A configured read-only subagent works too if it can run bash.

## Claude Code

Use the `Agent` tool (called `Task` in older versions). Make two calls in one message:

```
Agent(subagent_type="general-purpose", model="opus", description="Reviewer A", prompt="<header A + brief>")
Agent(subagent_type="general-purpose", model="opus", description="Reviewer B", prompt="<header B + brief>")
```

They run in the background by default. Wait for both completion notifications before step 3. Use `general-purpose` rather than `Explore`: reviewers need to run git and tests. If you are yourself a sub-agent and cannot spawn agents, use solo mode.

## Codex

With `spawn_agent` available, spawn two agents in the same turn. Give each a fresh context (`fork_turns: "none"`, or `fork_context: false` on older versions), the header plus brief as `message`, a `task_name` such as `reviewer_a`, and `reasoning_effort: "high"`. Then call `wait_agent` until both have reported. Children inherit your sandbox, so a read-only session keeps reviewers read-only. If spawning is unavailable or refused, use solo mode.

## Solo mode (no sub-agent tool)

Do the review yourself in two passes: pass A with lens A, files in diff order; then pass B with lens B, files in reverse order, deliberately looking for what pass A missed. Write each pass's CANDIDATE list before starting the next, then verify as in step 3. In the footer write `Reviewers: solo (2 passes on <model>)`.

## Manual scope (no bash)

Collect what scope.sh prints, using git directly:
- Base: `--base`, else the first of `origin/dev`, `dev`, `origin/main`, `main`, `origin/master`, `master` that exists. Merge base: `git merge-base <base> HEAD`.
- Diff: `git diff <merge-base>` (working tree, includes uncommitted changes) and the full contents of untracked files from `git status --short`. For a commit: `git show <sha>`. For a PR: `gh pr view <n> --json title,body,baseRefName,headRefOid` and `gh pr diff <n>`.
- Files and size: `git diff --stat <merge-base>`. Skip lockfiles and generated files.
- Rule files: AGENTS.md, CLAUDE.md and similar from the repo root to each changed directory, plus greptile.json, `.greptile/` and `.coderabbit.yaml`. Lesson files: LESSONS-LEARNED.md or lessons-learned.md.
