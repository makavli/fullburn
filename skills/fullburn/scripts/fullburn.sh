#!/usr/bin/env bash
# Fullburn's worktree and merge steps. Run from anywhere inside the main tree of the repository.
#   init                      set up .fullburn/ (git-excluded) and turn on extensions.worktreeConfig in the shared
#                             git config (left on: git needs it for per-worktree settings); needs a clean tree
#   add <job>                 make worktree ../<repo>_wt_<job> on branch wt/<job>, from HEAD
#   patch <job> [':!path'..]  save the worktree's diff to .fullburn/patches/<job>.patch, minus the excluded paths
#   apply <job>               3-way apply that patch to the main tree, once
#   clean <job> [--force]     remove the worktree and its branch
set -euo pipefail
# An inherited repository variable would aim every git -C call below at another repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

die() { echo "fullburn: $*" >&2; exit 1; }
# One patch format whatever the user's diff config (colour, prefixes, external or textconv drivers). With
# core.autocrlf on Windows, diff warns "LF will be replaced by CRLF" per file: noise, not news.
gdiff() { local d=$1; shift; git -C "$d" -c core.safecrlf=false diff --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ "$@"; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
[ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
  || die "run this from the main tree, not from a worktree"
run="$root/.fullburn"

job_name() {
  [ -n "${1:-}" ] || die "missing job name"
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || die "job name must be lowercase letters, digits and dashes: $1"
}
wt_path() { echo "$(dirname "$root")/$(basename "$root")_wt_$1"; }
# Paths with unstaged edits or untracked files, outside .fullburn/ (excluded).
loose() {
  local s; s=$(git -C "$root" status --porcelain --untracked-files=all) || die "git status failed in the main tree"
  grep -E '^(.[^ ]|\?\?)' <<< "$s" || true
}
# Hash of a worktree's whole diff against its base, new files included: what clean compares with the last patch.
work_hash() { git -C "$1" add -A -N . && gdiff "$1" --binary "$2" | git hash-object --stdin; }
# New files git ignores travel in no patch and are lost with the worktree; folders are listed once.
ignored() { git -C "$1" ls-files -o -i --exclude-standard --directory; }

cmd=${1:-}; shift || true
case "$cmd" in
  init)
    if git -C "$root" config --local --get core.worktree > /dev/null; then
      die "core.worktree is set here (a submodule?): fullburn's per-worktree config would break this repository's worktrees"
    fi
    [ -z "$(git -C "$root" status --porcelain --untracked-files=all)" ] \
      || die "the tree is not clean: commit or stash first (merging stages every change)"
    git -C "$root" rev-parse --verify -q HEAD > /dev/null || die "the repository has no commit yet: commit something first"
    exclude=$(git -C "$root" rev-parse --git-path info/exclude)
    case "$exclude" in /*|?:*) ;; *) exclude="$root/$exclude" ;; esac
    mkdir -p "$(dirname "$exclude")"
    grep -qxF '/.fullburn/' "$exclude" 2>/dev/null || echo '/.fullburn/' >> "$exclude"
    # Per-worktree settings stay out of the shared .git/config only with this extension on.
    git -C "$root" config extensions.worktreeConfig true
    mkdir -p "$run/reports" "$run/patches"
    echo "$run"
    ;;

  add)
    job_name "${1:-}"; wt=$(wt_path "$1")
    [ -d "$run" ] || die "run init first"
    [ ! -e "$wt" ] || die "already exists: $wt"
    if git -C "$root" show-ref --verify --quiet "refs/heads/wt/$1"; then
      die "branch wt/$1 is left from an earlier run: clean $1 first"
    fi
    GIT_LFS_SKIP_SMUDGE=1 git -C "$root" worktree add -q -b "wt/$1" "$wt" HEAD
    # --worktree is the point: without it this lands in the shared config and stops the main tree's LFS fetches.
    git -C "$wt" config --worktree lfs.fetchexclude '*'
    git -C "$wt" config --worktree fullburn.base "$(git -C "$wt" rev-parse HEAD)"
    old="$run/patches/$1.patch"  # a reused job name: set the last patch aside, so it is never applied or trusted as this job's
    if [ -f "$old" ]; then mv "$old" "$old.$(date +%Y%m%d%H%M%S)"; fi
    rm -f "$run/patches/$1.applied"
    echo "$wt"
    ;;

  patch)
    job_name "${1:-}"; job=$1; shift; wt=$(wt_path "$job")
    [ -d "$wt" ] || die "no worktree: $wt"
    for s in "$@"; do
      case "$s" in ':!'?*|':^'?*|':(exclude)'?*) ;; *) die "a pathspec may only exclude (':!path'): $s" ;; esac
    done
    base=$(git -C "$wt" config --worktree fullburn.base) || die "no base recorded in $wt (made by fullburn add?)"
    [ "$(git -C "$wt" rev-parse --show-toplevel)" = "$wt" ] || die "$wt does not resolve to itself as a work tree"
    git -C "$wt" add -A -N .
    raw=$(gdiff "$wt" --raw "$base" -- . "$@")
    sub=$(grep -E '^:[0-7]{6} 160000 |^:160000 ' <<< "$raw" | cut -f2 | tr '\n' ' ' || true)
    [ -z "$sub" ] || die "a nested repository or submodule cannot travel in a patch: $sub(remove it, or exclude it with ':!<path>')"
    out="$run/patches/$job.patch"
    # Against the base commit, so a helper's stray commit or staged edit is still included.
    gdiff "$wt" --binary "$base" -- . "$@" > "$out.tmp"
    mv "$out.tmp" "$out"
    git -C "$wt" config --worktree fullburn.patched "$(work_hash "$wt" "$base")"
    if [ -s "$out" ]; then gdiff "$wt" --stat "$base" -- . "$@"; else echo "empty: $job changed nothing"; fi
    if [ $# -gt 0 ]; then
      left=$(LC_ALL=C comm -23 <(gdiff "$wt" --name-only "$base" | LC_ALL=C sort) \
                               <(gdiff "$wt" --name-only "$base" -- . "$@" | LC_ALL=C sort))
      [ -z "$left" ] || printf 'left out, to regenerate in the main tree:\n%s\n' "$left"
    fi
    i=$(ignored "$wt")
    [ -z "$i" ] || printf 'ignored by git, so not in the patch:\n%s\n' "$i"
    echo "$out"
    ;;

  apply)
    job_name "${1:-}"; job=$1; p="$run/patches/$job.patch"; mark="$run/patches/$job.applied"; wt=$(wt_path "$job")
    [ -f "$p" ] || die "no patch: $p (run patch first)"
    [ -s "$p" ] || { echo "empty patch, nothing to apply: $job"; exit 0; }
    h=$(git hash-object "$p")
    [ "$(cat "$mark" 2>/dev/null)" != "$h" ] || die "already applied: $job"
    if [ -d "$wt" ]; then
      base=$(git -C "$wt" config --worktree fullburn.base 2>/dev/null || true)
      saved=$(git -C "$wt" config --worktree fullburn.patched 2>/dev/null || true)
      [ -z "$base" ] || [ "$(work_hash "$wt" "$base")" = "$saved" ] \
        || die "$wt changed after its patch was made: run patch $job again, then apply"
    fi
    if [ -n "$(git -C "$root" ls-files -u)" ]; then
      die "unresolved conflicts: fix the markers, then git add those files: $(git -C "$root" diff --name-only --diff-filter=U | tr '\n' ' ')"
    fi
    l=$(loose)
    if [ -n "$l" ]; then
      echo "$l" >&2
      die "unstaged or untracked changes in the main tree (above). Yours (a resolved conflict, a regenerated file)? git add them and rerun. Not yours? A helper wrote outside its worktree: look before merging."
    fi
    if git -C "$root" apply --3way --whitespace=nowarn "$p"; then
      echo "$h" > "$mark"
      echo "applied: $job"
    else
      c=$(git -C "$root" diff --name-only --diff-filter=U | tr '\n' ' ')
      [ -n "$c" ] || die "nothing was applied, the tree is unchanged (see the error above): merge $job by hand from its worktree, or relaunch it on the merged tree; do not clean it yet"
      echo "$h" > "$mark"
      echo "conflicts: $c" >&2
      die "the rest of the patch is applied and staged. In those files: resolve the markers keeping both jobs' intent; a binary or deleted file has none, so pick a side (git checkout --ours or --theirs, or git rm). Then git add them and go on."
    fi
    ;;

  clean)
    job_name "${1:-}"; job=$1; wt=$(wt_path "$job"); br="refs/heads/wt/$job"
    case "${2:-}" in --force) force=1 ;; '') force= ;; *) die "unknown option: $2 (only --force)" ;; esac
    if [ -d "$wt" ]; then
      if [ -z "$force" ]; then
        base=$(git -C "$wt" config --worktree fullburn.base 2>/dev/null) \
          || die "no base recorded in $wt, so its work cannot be checked: clean $job --force removes it anyway"
        now=$(work_hash "$wt" "$base")
        saved=$(git -C "$wt" config --worktree fullburn.patched 2>/dev/null || true)
        if [ "$now" != "$(git hash-object --stdin < /dev/null)" ]; then
          [ "$now" = "$saved" ] || die "$wt holds work its patch does not have: run patch $job first, or clean $job --force to discard it"
          p="$run/patches/$job.patch"
          if [ -s "$p" ] && [ "$(cat "$run/patches/$job.applied" 2>/dev/null)" != "$(git hash-object "$p")" ]; then
            die "the patch of $job was never applied: apply $job first, or clean $job --force to discard its work"
          fi
        fi
        i=$(ignored "$wt")
        [ -z "$i" ] || printf 'dropping files git ignores:\n%s\n' "$i"
      fi
      git -C "$root" worktree remove --force "$wt"
    elif [ -z "$force" ] && git -C "$root" show-ref --verify --quiet "$br" && [ -n "$(git -C "$root" rev-list -1 "HEAD..$br")" ]; then
      die "the worktree is gone, but wt/$job has commits that HEAD does not: merge them, or clean $job --force"
    fi
    git -C "$root" worktree prune
    if git -C "$root" show-ref --verify --quiet "$br"; then git -C "$root" branch -q -D "wt/$job"; fi
    echo "removed: $job"
    ;;

  *) die "usage: fullburn.sh init | add <job> | patch <job> [':!path'...] | apply <job> | clean <job> [--force]" ;;
esac
