#!/usr/bin/env bash
# Self-test of scripts/fullburn.sh on a throwaway repository: worktrees, the LFS setting's scope, patches with an
# excluded generated file, a clean 3-way apply, a real conflict resolved, the safety refusals, and the clean-up.
set -uo pipefail

fb="$(cd "$(dirname "$0")/.." && pwd)/skills/fullburn/scripts/fullburn.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
fbr() { bash "$fb" "$@"; }  # run from the current directory

mkdir "$tmp/empty" && git -C "$tmp/empty" init -q
check "init refuses a repository with no commit" "! (cd \"$tmp/empty\" && bash \"$fb\" init) >/dev/null 2>&1"

repo="$tmp/demo"
mkdir -p "$repo" && cd "$repo" || exit 1
git init -q -b main
git config user.email test@example.invalid
git config user.name test
git config core.autocrlf false
printf '%s\n' one two three four five six seven > a.txt
git add a.txt && git commit -qm base

echo stray > stray.txt
check "init refuses a dirty tree" "! fbr init >/dev/null 2>&1"
rm stray.txt
check "init succeeds on a clean tree" "fbr init >/dev/null"
check ".fullburn/ is git-excluded" "grep -qxF .fullburn/ .git/info/exclude && [ -z \"\$(git status --porcelain)\" ]"
check "init twice adds one exclude line" "fbr init >/dev/null && [ \"\$(grep -cxF .fullburn/ .git/info/exclude)\" = 1 ]"
check "bad job name is refused" "! fbr add 'Bad Name' >/dev/null 2>&1"

wa=$(fbr add alpha) && wb=$(fbr add beta)
check "worktrees made" "[ -f \"$wa/a.txt\" ] && [ -f \"$wb/a.txt\" ]"
check "branches made" "git show-ref --verify --quiet refs/heads/wt/alpha && git show-ref --verify --quiet refs/heads/wt/beta"
check "lfs.fetchexclude only in the worktree" "[ \"\$(git -C \"$wa\" config lfs.fetchexclude)\" = '*' ] && ! git config lfs.fetchexclude >/dev/null"
check "add refuses an existing worktree" "! fbr add alpha >/dev/null 2>&1"
check "commands refuse to run from a worktree" "! (cd \"$wa\" && bash \"$fb\" patch alpha) >/dev/null 2>&1"

# alpha: edits line 2 and adds a file. beta: edits line 2 differently (the conflict), line 6, and a generated file.
sed 's/^two$/two-alpha/' "$wa/a.txt" > "$wa/x" && mv "$wa/x" "$wa/a.txt"
echo new > "$wa/new.txt"
sed -e 's/^two$/two-beta/' -e 's/^six$/six-beta/' "$wb/a.txt" > "$wb/x" && mv "$wb/x" "$wb/a.txt"
echo generated > "$wb/gen.lock"

check "patch alpha" "fbr patch alpha >/dev/null"
check "patch beta excludes the generated file" "fbr patch beta ':!gen.lock' >/dev/null && ! grep -q gen.lock .fullburn/patches/beta.patch && grep -q six-beta .fullburn/patches/beta.patch"
check "patch includes a new file" "grep -q 'new file' .fullburn/patches/alpha.patch"

check "apply alpha cleanly" "fbr apply alpha >/dev/null && grep -qx two-alpha a.txt && [ -f new.txt ]"
check "apply beta reports the conflict" "! fbr apply beta >/dev/null 2>&1 && grep -q '^<<<<<<<' a.txt"
check "the other hunk of beta landed" "grep -qx six-beta a.txt"
check "apply refuses while conflicts are unresolved" "! fbr apply alpha >/dev/null 2>&1"

# Resolve: keep both intents on line 2.
awk '/^<<<<<<</{skip=1; print "two-alpha-beta"; next} /^>>>>>>>/{skip=0; next} !skip' a.txt > x && mv x a.txt
echo helper-leak > leak.txt
check "apply refuses untracked files in the main tree" "! fbr apply alpha >/dev/null 2>&1"
rm leak.txt
git add a.txt
git commit -qm "wave 1"
check "the merged result is right" "[ \"\$(sed -n 2p a.txt)\" = two-alpha-beta ] && [ \"\$(sed -n 6p a.txt)\" = six-beta ] && git ls-files --error-unmatch new.txt >/dev/null 2>&1"

wc=$(fbr add gamma)
echo work > "$wc/w.txt"
check "clean refuses unsaved work" "! fbr clean gamma >/dev/null 2>&1 && [ -d \"$wc\" ]"
check "clean --force discards it" "fbr clean gamma --force >/dev/null && [ ! -d \"$wc\" ]"
wd=$(fbr add delta)
echo one > "$wd/d.txt"; fbr patch delta >/dev/null; echo two >> "$wd/d.txt"
check "clean refuses work newer than the patch" "! fbr clean delta >/dev/null 2>&1"
fbr patch delta >/dev/null
check "clean accepts once the patch is current" "fbr clean delta >/dev/null && [ ! -d \"$wd\" ]"
wd=$(fbr add delta)
echo three > "$wd/e.txt"
check "a reused job name sets its old patch aside" "[ ! -f .fullburn/patches/delta.patch ] && ls .fullburn/patches/delta.patch.* >/dev/null 2>&1"
check "clean refuses the reused job's unsaved work" "! fbr clean delta >/dev/null 2>&1"
fbr clean delta --force >/dev/null
check "clean alpha and beta" "fbr clean alpha >/dev/null && fbr clean beta >/dev/null"
check "worktrees and branches removed" "[ ! -d \"$wa\" ] && [ ! -d \"$wb\" ] && [ -z \"\$(git branch --list 'wt/*')\" ] && [ \"\$(git worktree list | wc -l | tr -d ' ')\" = 1 ]"
check "main tree clean after the wave" "[ -z \"\$(git status --porcelain)\" ]"

if [ "$fails" -eq 0 ]; then echo "fullburn.test.sh: all passed"; else echo "fullburn.test.sh: $fails failed"; exit 1; fi
