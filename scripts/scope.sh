#!/usr/bin/env bash
# greptile-style-review: resolve and pin the review scope, then print it.
# Usage: scope.sh [--base <branch>] [<branch> | <commit> | <PR number or URL>]
# Read-only. PR mode may `git fetch` the PR head when it is not available locally.
# Works with macOS /bin/bash 3.2: no arrays, no mapfile, no ${var,,}.
set -u

die() { printf 'scope.sh: %s\n' "$*" >&2; exit 1; }
ref_ok() { git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1; }
short() { git rev-parse --short "$1" 2>/dev/null || printf '%s' "$1"; }

BASE_ARG="" TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || die "--base needs a branch name"; BASE_ARG=$2; shift 2 ;;
    --base=*) BASE_ARG=${1#--base=}; shift ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$TARGET" ] || die "unexpected extra argument: $1"; TARGET=$1; shift ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$ROOT" || die "cannot enter $ROOT"

best_ref() {
  _up=$(git rev-parse --abbrev-ref --symbolic-full-name "$1@{upstream}" 2>/dev/null) \
    && ref_ok "$_up" && { printf '%s' "$_up"; return 0; }
  ref_ok "refs/remotes/origin/$1" && { printf 'origin/%s' "$1"; return 0; }
  ref_ok "refs/heads/$1" && { printf '%s' "$1"; return 0; }
  return 1
}
is_branch() {
  [ "$1" != HEAD ] && git check-ref-format --branch "$1" >/dev/null 2>&1 || return 1
  git show-ref --verify --quiet "refs/heads/$1" || git show-ref --verify --quiet "refs/remotes/origin/$1"
}

CUR_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "detached HEAD")
MODE="" PR="" PR_TITLE="" PR_URL="" PR_BODY="" BASE_REF="" HEAD_REF="HEAD" NOTE=""

if [ -n "$TARGET" ]; then
  case "$TARGET" in
    http*://*/pull/*) PR=${TARGET##*/pull/}; PR=${PR%%[/?#]*} ;;
    \#[0-9]*) PR=${TARGET#\#} ;;
  esac
  if [ -z "$PR" ] && [ "${#TARGET}" -le 6 ] && ! is_branch "$TARGET"; then
    case "$TARGET" in *[!0-9]*) ;; *) PR=$TARGET ;; esac
  fi
  if [ -n "$PR" ]; then
    MODE=pr
  elif is_branch "$TARGET"; then
    if [ "$TARGET" = "$CUR_BRANCH" ]; then
      :                                               # reviewing the current branch = default mode
    elif git merge-base --is-ancestor "$(best_ref "$TARGET")" HEAD 2>/dev/null \
         || [ "$TARGET" = dev ] || [ "$TARGET" = main ] || [ "$TARGET" = master ]; then
      [ -n "$BASE_ARG" ] || BASE_ARG=$TARGET
      NOTE="Interpreting '$TARGET' as the base branch (HEAD already contains it)."
    else
      MODE=branch; HEAD_REF=$(best_ref "$TARGET")
    fi
  elif ref_ok "$TARGET"; then
    MODE=commit
  else
    die "cannot resolve '$TARGET' as a PR, branch or commit"
  fi
fi

if [ "$MODE" = pr ]; then
  command -v gh >/dev/null 2>&1 || die "PR mode needs the GitHub CLI (gh)"
  PR_BASE=$(gh pr view "$PR" --json baseRefName --jq .baseRefName 2>/dev/null) || die "gh pr view $PR failed"
  PR_OID=$(gh pr view "$PR" --json headRefOid --jq .headRefOid)
  PR_BASE_OID=$(gh pr view "$PR" --json baseRefOid --jq .baseRefOid)
  PR_STATE=$(gh pr view "$PR" --json state --jq .state)
  PR_TITLE=$(gh pr view "$PR" --json title --jq .title)
  PR_URL=$(gh pr view "$PR" --json url --jq .url)
  PR_BODY=$(gh pr view "$PR" --json body --jq .body | sed -n '1,60p')
  if ! ref_ok "$PR_OID"; then
    git fetch --quiet origin "pull/$PR/head" 2>/dev/null || git fetch --quiet origin "$PR_OID" 2>/dev/null \
      || die "PR head $PR_OID is not available locally and could not be fetched"
  fi
  HEAD_REF=$PR_OID
  if [ -z "$BASE_ARG" ]; then
    BASE_ARG=$PR_BASE
    if [ "$PR_STATE" != OPEN ]; then
      ref_ok "$PR_BASE_OID" || git fetch --quiet origin "$PR_BASE_OID" 2>/dev/null || true
      ref_ok "$PR_BASE_OID" && BASE_ARG=$PR_BASE_OID
      NOTE="PR is $PR_STATE; diffing against its recorded base commit $(short "$PR_BASE_OID")."
    fi
  fi
fi

if [ "$MODE" = commit ]; then
  HEAD_SHA=$(git rev-parse "$TARGET^{commit}")
  if ref_ok "$HEAD_SHA^"; then MB=$(git rev-parse "$HEAD_SHA^"); else MB=$(git hash-object -t tree /dev/null); fi
  BASE_REF="parent of $(short "$HEAD_SHA")"
else
  if [ -n "$BASE_ARG" ]; then
    BASE_REF=$(best_ref "$BASE_ARG") || { ref_ok "$BASE_ARG" && BASE_REF=$BASE_ARG; } || die "base '$BASE_ARG' not found"
  else
    for b in dev main master; do BASE_REF=$(best_ref "$b") && break; BASE_REF=""; done
  fi
  HEAD_SHA=$(git rev-parse "$HEAD_REF^{commit}")
  if [ -n "$BASE_REF" ]; then
    MB=$(git merge-base "$BASE_REF" "$HEAD_SHA" 2>/dev/null) || die "no merge base between $BASE_REF and $(short "$HEAD_SHA") (shallow clone? try: git fetch --unshallow)"
  else
    MB=$HEAD_SHA; NOTE="No dev, main or master branch found; reviewing uncommitted work only (pass --base <branch> to change)."
  fi
fi

DIRTY=""
if [ -z "$MODE" ] && [ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]; then DIRTY=1; fi

if [ -z "$MODE" ] && [ -n "$DIRTY" ]; then
  MODE=worktree; RANGE="$MB"; DIFF_CMD="git diff $MB"
elif [ -z "$MODE" ]; then
  MODE=branch-clean; RANGE="$MB $HEAD_SHA"; DIFF_CMD="git diff $MB $HEAD_SHA"
else
  RANGE="$MB $HEAD_SHA"; DIFF_CMD="git diff $MB $HEAD_SHA"
fi

if [ "$MODE" != worktree ] && [ "$MB" = "$HEAD_SHA" ]; then
  echo "NOTHING TO REVIEW: $(short "$HEAD_SHA") has no changes against ${BASE_REF:-its base} and the working tree is clean."
  echo "Try: scope.sh HEAD (last commit), scope.sh --base <branch>, or a PR number."
  exit 2
fi

FILE_ACCESS="working tree"
if [ "$MODE" = commit ] || [ "$MODE" = pr ] || [ "$MODE" = branch ]; then
  [ "$(git rev-parse HEAD)" = "$HEAD_SHA" ] || FILE_ACCESS="not checked out: read files with git show $(short "$HEAD_SHA"):<path>"
fi

skipped() {
  case "$1" in
    *package-lock.json|*npm-shrinkwrap.json|*yarn.lock|*pnpm-lock.yaml|*bun.lock|*bun.lockb|*poetry.lock|*uv.lock|\
    *Pipfile.lock|*Cargo.lock|*go.sum|*Gemfile.lock|*composer.lock|*Podfile.lock|*pubspec.lock|*mix.lock|*flake.lock|\
    *.min.js|*.min.css|*.map|*.snap|*__snapshots__/*|*_pb2.py|*_pb2_grpc.py|*.pb.go|*.generated.*|\
    node_modules/*|*/node_modules/*|vendor/*|*/vendor/*|dist/*|*/dist/*) return 0 ;;
  esac
  return 1
}

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t gsr) || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC2086
git diff --numstat -M $RANGE > "$TMP/numstat" 2>/dev/null
# shellcheck disable=SC2086
git diff --name-status -M $RANGE > "$TMP/status" 2>/dev/null
if [ "$MODE" = worktree ]; then
  git ls-files --others --exclude-standard | sed -n '1,300p' > "$TMP/untracked"
else
  : > "$TMP/untracked"
fi

ADDS=0 DELS=0 NFILES=0
: > "$TMP/files"; : > "$TMP/skipped"; : > "$TMP/dirs"
while IFS="$(printf '\t')" read -r a d path; do
  [ -n "${path:-}" ] || continue
  case "$path" in *" => "*) path=$(printf '%s' "$path" | sed -E 's/\{([^}]*) => ([^}]*)\}/\2/; s/.* => //') ;; esac
  st=$(awk -F '\t' -v p="$path" '$NF==p {print substr($1,1,1); exit}' "$TMP/status")
  if [ "$a" = "-" ]; then line="  ${st:-M}  $path  (binary)"; echo "$line" >> "$TMP/skipped"; continue; fi
  line="  ${st:-M}  $path  +$a/-$d"
  if skipped "$path"; then echo "$line" >> "$TMP/skipped"; continue; fi
  echo "$line" >> "$TMP/files"
  ADDS=$((ADDS + a)); DELS=$((DELS + d)); NFILES=$((NFILES + 1))
  dirname "$path" >> "$TMP/dirs"
done < "$TMP/numstat"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  n=$(git diff --no-index --numstat -- /dev/null "$path" 2>/dev/null | awk '{print $1; exit}')
  if [ "${n:-}" = "-" ] || [ -z "${n:-}" ]; then echo "  ?? $path  (untracked, binary)" >> "$TMP/skipped"; continue; fi
  if skipped "$path"; then echo "  ?? $path  +$n (untracked)" >> "$TMP/skipped"; continue; fi
  echo "  ?? $path  +$n (untracked)" >> "$TMP/files"
  ADDS=$((ADDS + n)); NFILES=$((NFILES + 1))
  dirname "$path" >> "$TMP/dirs"
done < "$TMP/untracked"

CHANGED=$((ADDS + DELS))
if [ "$CHANGED" -ge 1500 ] || [ "$NFILES" -gt 40 ]; then SIZE=large
elif [ "$CHANGED" -ge 200 ]; then SIZE=medium
else SIZE=small; fi

# Rule files: directory-scoped files from each changed dir up to the root,
# repo-level review configs, and AGENTS.md/CLAUDE.md in enclosing workspace dirs.
# `find -name` reports names as stored, so case-insensitive filesystems give no duplicates.
rule_files_in() {
  find "$1" -maxdepth 1 -type f \( -name AGENTS.md -o -name agents.md -o -name AGENTS.override.md \
    -o -name CLAUDE.md -o -name GEMINI.md -o -name BUGBOT.md \) 2>/dev/null
}
: > "$TMP/rules"
sort -u "$TMP/dirs" | while IFS= read -r d; do
  while :; do
    rule_files_in "$d" | sed 's|^\./||' >> "$TMP/rules"
    for f in .greptile/config.json .greptile/rules.md .greptile/files.json .cursor/BUGBOT.md; do
      if [ "$d" = "." ]; then p=$f; else p="$d/$f"; fi
      [ -f "$p" ] && echo "$p" >> "$TMP/rules"
    done
    [ "$d" = "." ] && break
    d=$(dirname "$d")
  done
done
for f in greptile.json .coderabbit.yaml .coderabbit.yml .github/copilot-instructions.md REVIEW.md CODE_REVIEW.md .cursorrules; do
  [ -f "$f" ] && echo "$f" >> "$TMP/rules"
done
for f in .github/instructions/*.instructions.md .cursor/rules/*.mdc; do [ -f "$f" ] && echo "$f" >> "$TMP/rules"; done
p=$(dirname "$ROOT")
while [ "$p" != "/" ] && [ "$p" != "$HOME" ] && [ -n "$p" ]; do
  rule_files_in "$p" | grep -v '/BUGBOT.md$' | sed 's/$/ (workspace)/' >> "$TMP/rules"
  p=$(dirname "$p")
done

: > "$TMP/lessons"
find . -maxdepth 3 -type f \( -iname 'lessons-learned*.md' -o -iname 'lessons_learned*.md' -o -iname 'lessons.md' \) \
  -not -path './node_modules/*' -not -path './.git/*' 2>/dev/null | sed 's|^\./||' >> "$TMP/lessons"
p=$(dirname "$ROOT")
while [ "$p" != "/" ] && [ "$p" != "$HOME" ] && [ -n "$p" ]; do
  find "$p" -maxdepth 1 -type f \( -iname 'lessons-learned*.md' -o -iname 'lessons.md' \) 2>/dev/null \
    | sed 's/$/ (workspace)/' >> "$TMP/lessons"
  p=$(dirname "$p")
done

GRAPH="not found"; p=$ROOT
while [ "$p" != "/" ] && [ -n "$p" ]; do
  [ -d "$p/.codegraph" ] && { GRAPH="index at $p/.codegraph (use code-graph tools for callers if available)"; break; }
  p=$(dirname "$p")
done

case "$MODE" in
  worktree)     SCOPE="$CUR_BRANCH vs ${BASE_REF:-HEAD}: committed and uncommitted changes" ;;
  branch-clean) SCOPE="$CUR_BRANCH vs $BASE_REF" ;;
  branch)       SCOPE="branch $TARGET vs $BASE_REF" ;;
  commit)       SCOPE="commit $(short "$HEAD_SHA") ($(git log -1 --format=%s "$HEAD_SHA" | cut -c1-72))" ;;
  pr)           SCOPE="PR #$PR ($PR_TITLE) vs $PR_BASE @ $(short "$MB")" ;;
esac

echo "SCOPE: $SCOPE"
[ -n "$NOTE" ] && echo "NOTE: $NOTE"
echo "REPO: $ROOT"
echo "BASE: ${BASE_REF:-none} -> merge base $(short "$MB")"
if [ "$(git rev-parse HEAD)" = "$HEAD_SHA" ]; then
  echo "HEAD: $(short "$HEAD_SHA") ($CUR_BRANCH)"
else
  echo "HEAD: $(short "$HEAD_SHA") (${TARGET:-?}; not checked out)"
fi
if [ "$MODE" = worktree ]; then
  echo "DIFF: $DIFF_CMD    # working tree (staged + unstaged) vs merge base; read untracked files in full"
else
  echo "DIFF: $DIFF_CMD"
fi
echo "FILE ACCESS: $FILE_ACCESS"
echo "SIZE: $SIZE - $NFILES files, +$ADDS/-$DELS ($CHANGED changed lines, skipped files excluded)"
echo "FILES (diff order):"
if [ -s "$TMP/files" ]; then cat "$TMP/files"; else echo "  (none)"; fi
if [ -s "$TMP/skipped" ]; then echo "SKIPPED (lockfile, generated or binary; review only if they are the point of the change):"; cat "$TMP/skipped"; fi
if [ "$MODE" = pr ]; then
  echo "PR: $PR_URL"
  echo "PR BODY (first 60 lines):"
  printf '%s\n' "$PR_BODY" | sed 's/^/  /'
fi
if [ "$MODE" != worktree ] || [ "$MB" != "$HEAD_SHA" ]; then
  echo "COMMITS (oldest first, body up to 6 lines):"
  git log --reverse --no-merges -n 40 --format='@@ %h %s%n%b' "$MB..$HEAD_SHA" 2>/dev/null \
    | awk '/^@@ /{sub(/^@@ /,"  "); print; n=0; next} NF && n<6 {print "      " $0; n++}'
fi
echo "RULE FILES:"
if [ -s "$TMP/rules" ]; then sort -u "$TMP/rules" | sed 's/^/  /'; else echo "  (none)"; fi
echo "LESSON FILES:"
if [ -s "$TMP/lessons" ]; then sort -u "$TMP/lessons" | sed 's/^/  /'; else echo "  (none)"; fi
echo "CODE GRAPH: $GRAPH"
