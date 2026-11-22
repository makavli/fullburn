#!/usr/bin/env bash
# Fullburn's worktree and merge steps. Run from anywhere inside the main tree of the repository.
#   init                      set up .fullburn/ (git-excluded) and per-worktree config; needs a clean tree
#   add <job>                 make worktree ../<repo>_wt_<job> on branch wt/<job>, from HEAD
#   patch <job> [pathspec..]  save the worktree's diff to .fullburn/patches/<job>.patch (pathspecs like ':!package-lock.json')
#   apply <job>               3-way apply that patch to the main tree
#   clean <job> [--force]     remove the worktree and its branch
set -euo pipefail
# On Windows with core.autocrlf, every diff and apply warns "LF will be replaced by CRLF" per file: noise, not news.
git() { command git -c core.safecrlf=false "$@"; }

die() { echo "fullburn: $*" >&2; exit 1; }

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
loose() { git -C "$root" status --porcelain --untracked-files=all | grep -E '^(.[^ ]|\?\?)' || true; }
# Hash of a worktree's whole diff against its base, new files included: what clean compares with the last patch.
work_hash() { git -C "$1" add -A -N . && git -C "$1" diff --binary "$2" | git hash-object --stdin; }

cmd=${1:-}; shift || true
case "$cmd" in
  init)
    [ -z "$(git -C "$root" status --porcelain --untracked-files=all)" ] \
      || die "the tree is not clean: commit or stash first (merging stages every change)"
    git -C "$root" rev-parse --verify -q HEAD > /dev/null || die "the repository has no commit yet: commit something first"
    exclude=$(git -C "$root" rev-parse --git-path info/exclude)
    case "$exclude" in /*|?:*) ;; *) exclude="$root/$exclude" ;; esac
    mkdir -p "$(dirname "$exclude")"
    grep -qxF '.fullburn/' "$exclude" 2>/dev/null || echo '.fullburn/' >> "$exclude"
    # Per-worktree settings stay out of the shared .git/config only with this extension on.
    git -C "$root" config extensions.worktreeConfig true
    mkdir -p "$run/reports" "$run/patches"
    echo "$run"
    ;;

  add)
    job_name "${1:-}"; wt=$(wt_path "$1")
    [ -d "$run" ] || die "run init first"
    [ ! -e "$wt" ] || die "already exists: $wt"
    old="$run/patches/$1.patch"  # a reused job name: set the last patch aside, so it is never applied or trusted as this job's
    if [ -f "$old" ]; then mv "$old" "$old.$(date +%Y%m%d%H%M%S)"; fi
    GIT_LFS_SKIP_SMUDGE=1 git -C "$root" worktree add -q -b "wt/$1" "$wt" HEAD
    # --worktree is the point: without it this lands in the shared config and stops the main tree's LFS fetches.
    git -C "$wt" config --worktree lfs.fetchexclude '*'
    git -C "$wt" config --worktree fullburn.base "$(git -C "$wt" rev-parse HEAD)"
    echo "$wt"
    ;;

  patch)
    job_name "${1:-}"; job=$1; shift; wt=$(wt_path "$job")
    [ -d "$wt" ] || die "no worktree: $wt"
    base=$(git -C "$wt" config --worktree fullburn.base) || die "no base recorded in $wt (made by fullburn add?)"
    git -C "$wt" add -A -N .
    out="$run/patches/$job.patch"
    # Against the base commit, so a helper's stray commit or staged edit is still included.
    git -C "$wt" diff --binary "$base" -- . "$@" > "$out"
    git -C "$wt" config --worktree fullburn.patched "$(work_hash "$wt" "$base")"
    if [ -s "$out" ]; then git -C "$wt" diff --stat "$base" -- . "$@"; else echo "empty: $job changed nothing"; fi
    echo "$out"
    ;;

  apply)
    job_name "${1:-}"; p="$run/patches/$1.patch"
    [ -f "$p" ] || die "no patch: $p (run patch first)"
    [ -s "$p" ] || { echo "empty patch, nothing to apply: $1"; exit 0; }
    if [ -n "$(git -C "$root" ls-files -u)" ]; then
      die "unresolved conflicts: fix the markers, then git add those files: $(git -C "$root" diff --name-only --diff-filter=U | tr '\n' ' ')"
    fi
    l=$(loose)
    if [ -n "$l" ]; then
      echo "$l" >&2
      die "unstaged or untracked changes in the main tree (above). Yours (a resolved conflict, a regenerated file)? git add them and rerun. Not yours? A helper wrote outside its worktree: look before merging."
    fi
    if git -C "$root" apply --3way --whitespace=nowarn "$p"; then
      echo "applied: $1"
    else
      c=$(git -C "$root" diff --name-only --diff-filter=U | tr '\n' ' ')
      [ -n "$c" ] || die "patch did not apply and left no conflict markers: $p (see the error above)"
      echo "conflicts: $c" >&2
      die "resolve the markers in those files keeping both jobs' intent, git add them, then go on"
    fi
    ;;

  clean)
    job_name "${1:-}"; job=$1; force=${2:-}; wt=$(wt_path "$job")
    if [ -d "$wt" ]; then
      if [ "$force" != "--force" ]; then
        base=$(git -C "$wt" config --worktree fullburn.base 2>/dev/null || echo HEAD)
        now=$(work_hash "$wt" "$base")
        saved=$(git -C "$wt" config --worktree fullburn.patched 2>/dev/null || true)
        if [ "$now" != "$(git hash-object --stdin < /dev/null)" ] && [ "$now" != "$saved" ]; then
          die "$wt holds work its patch does not have: run patch $job first, or clean $job --force to discard it"
        fi
      fi
      git -C "$root" worktree remove --force "$wt"
    fi
    git -C "$root" worktree prune
    if git -C "$root" show-ref --verify --quiet "refs/heads/wt/$job"; then git -C "$root" branch -q -D "wt/$job"; fi
    echo "removed: $job"
    ;;

  *) die "usage: fullburn.sh init | add <job> | patch <job> [pathspec...] | apply <job> | clean <job> [--force]" ;;
esac
