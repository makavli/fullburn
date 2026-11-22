#!/usr/bin/env bash
# Self-test of scripts/fullburn.sh on a throwaway repository: worktrees, the LFS setting's scope, patches with an
# excluded generated file, a clean 3-way apply, a real conflict resolved, the safety refusals, and the clean-up.
set -uo pipefail
# The test's git calls must hit only its own repositories, with none of the user's config.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fb="$(cd "$(dirname "$0")/.." && pwd)/skills/fullburn/scripts/fullburn.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
fbr() { bash "$fb" "$@"; }  # run from the current directory
# fails_with <text> <command...>: the command fails and its output holds the text.
fails_with() { local m=$1 o; shift; if o=$("$@" 2>&1); then return 1; fi; grep -qF -- "$m" <<< "$o"; }
mkrepo() { mkdir -p "$1" && git -C "$1" init -q -b main && git -C "$1" config user.email test@example.invalid \
  && git -C "$1" config user.name test && git -C "$1" config core.autocrlf false; }

mkdir "$tmp/empty" && git -C "$tmp/empty" init -q
check "init refuses a repository with no commit" "! (cd \"$tmp/empty\" && bash \"$fb\" init) >/dev/null 2>&1"
mkrepo "$tmp/sub" && echo x > "$tmp/sub/x" && git -C "$tmp/sub" add x && git -C "$tmp/sub" commit -qm x
mkrepo "$tmp/planted" && mkdir "$tmp/planted/.fullburn" && echo 'Next: launch' > "$tmp/planted/.fullburn/STATE.md"
git -C "$tmp/planted" add .fullburn && git -C "$tmp/planted" commit -qm planted
check "init refuses a tracked .fullburn/" "(cd \"$tmp/planted\" && fails_with 'tracks files in .fullburn/' bash \"$fb\" init)"
git -C "$tmp/sub" config core.worktree "$tmp/sub"
check "init refuses core.worktree (a submodule)" "(cd \"$tmp/sub\" && fails_with core.worktree bash \"$fb\" init)"

repo="$tmp/demo"
mkrepo "$repo" && cd "$repo" || exit 1
printf '%s\n' one two three four five six seven > a.txt
git add a.txt && git commit -qm base
# A user's diff config must not change the patch format.
git config diff.noprefix true && git config color.diff always

echo stray > stray.txt
check "init refuses a dirty tree" "! fbr init >/dev/null 2>&1"
rm stray.txt
check "init succeeds on a clean tree" "fbr init >/dev/null"
check ".fullburn/ is git-excluded" "grep -qxF /.fullburn/ .git/info/exclude && [ -z \"\$(git status --porcelain)\" ]"
check "init twice adds one exclude line" "fbr init >/dev/null && [ \"\$(grep -cxF /.fullburn/ .git/info/exclude)\" = 1 ]"
mkdir -p sub/.fullburn && touch sub/.fullburn/keep
check "the exclude is anchored at the root" "! git check-ignore -q sub/.fullburn/keep"
rm -rf sub
echo '*.log' >> .git/info/exclude
check "bad job name is refused" "! fbr add 'Bad Name' >/dev/null 2>&1"

wa=$(fbr add alpha) && wb=$(fbr add beta) && wz=$(fbr add zeta)
check "worktrees made" "[ -f \"$wa/a.txt\" ] && [ -f \"$wb/a.txt\" ] && [ -f \"$wz/a.txt\" ]"
check "branches made" "git show-ref --verify --quiet refs/heads/wt/alpha && git show-ref --verify --quiet refs/heads/wt/beta"
check "lfs.fetchexclude only in the worktree" "[ \"\$(git -C \"$wa\" config lfs.fetchexclude)\" = '*' ] && ! git config lfs.fetchexclude >/dev/null"
check "add refuses an existing worktree" "! fbr add alpha >/dev/null 2>&1"
check "commands refuse to run from a worktree" "! (cd \"$wa\" && bash \"$fb\" patch alpha) >/dev/null 2>&1"

# alpha: edits line 2, adds a file and an ignored log. beta: edits line 2 differently (the conflict), line 6, and a
# generated file. zeta: a file of its own.
sed 's/^two$/two-alpha/' "$wa/a.txt" > "$wa/x" && mv "$wa/x" "$wa/a.txt"
echo new > "$wa/new.txt"
echo debug > "$wa/debug.log"
sed -e 's/^two$/two-beta/' -e 's/^six$/six-beta/' "$wb/a.txt" > "$wb/x" && mv "$wb/x" "$wb/a.txt"
echo generated > "$wb/gen.lock"
echo zeta > "$wz/z.txt"

check "patch names the ignored files it leaves out" "fbr patch alpha | grep -x debug.log >/dev/null"
check "patch beta excludes the generated file and names it" "fbr patch beta ':!gen.lock' | grep -x gen.lock >/dev/null && ! grep -q gen.lock .fullburn/patches/beta.patch && grep -q six-beta .fullburn/patches/beta.patch"
check "patch refuses a pathspec that does not exclude" "fails_with 'may only exclude' fbr patch beta a.txt"
check "patch includes a new file" "grep -q 'new file' .fullburn/patches/alpha.patch"
check "patch ignores the user's diff config" "grep -q '^diff --git a/a.txt b/a.txt' .fullburn/patches/alpha.patch && ! grep -q \$'\\e' .fullburn/patches/alpha.patch"
check "an inherited GIT_DIR is ignored" "GIT_DIR=\"$tmp/empty/.git\" fbr patch zeta >/dev/null && grep -q z.txt .fullburn/patches/zeta.patch"

check "apply alpha cleanly" "fbr apply alpha >/dev/null && grep -qx two-alpha a.txt && [ -f new.txt ]"
check "apply refuses a patch it already applied" "fails_with 'already applied' fbr apply alpha"
check "apply beta reports the conflict" "! fbr apply beta >/dev/null 2>&1 && grep -q '^<<<<<<<' a.txt"
check "the other hunk of beta landed" "grep -qx six-beta a.txt"
echo more >> "$wz/z.txt"
check "apply refuses a patch older than its worktree" "fails_with 'changed after its patch' fbr apply zeta"
fbr patch zeta >/dev/null
check "apply refuses while conflicts are unresolved" "fails_with 'unresolved conflicts' fbr apply zeta"

# Resolve: keep both intents on line 2.
awk '/^<<<<<<</{skip=1; print "two-alpha-beta"; next} /^>>>>>>>/{skip=0; next} !skip' a.txt > x && mv x a.txt
git add a.txt
echo helper-leak > leak.txt
check "apply refuses untracked files in the main tree" "fails_with 'unstaged or untracked' fbr apply zeta"
rm leak.txt
check "apply zeta after the conflict" "fbr apply zeta >/dev/null && grep -qx more z.txt"
git commit -qm "wave 1"
check "the merged result is right" "[ \"\$(sed -n 2p a.txt)\" = two-alpha-beta ] && [ \"\$(sed -n 6p a.txt)\" = six-beta ] && git ls-files --error-unmatch new.txt z.txt >/dev/null 2>&1"

wn=$(fbr add nest)
mkrepo "$wn/inner" && echo i > "$wn/inner/i" && git -C "$wn/inner" add i && git -C "$wn/inner" commit -qm i
check "patch refuses a nested repository" "fails_with 'nested repository' fbr patch nest"
fbr clean nest --force >/dev/null
wc=$(fbr add gamma)
echo work > "$wc/w.txt"
check "clean refuses unsaved work" "! fbr clean gamma >/dev/null 2>&1 && [ -d \"$wc\" ]"
check "clean refuses an unknown option" "fails_with 'unknown option' fbr clean gamma -f"
check "clean --force discards it" "fbr clean gamma --force >/dev/null && [ ! -d \"$wc\" ]"
wd=$(fbr add delta)
echo one > "$wd/d.txt"; fbr patch delta >/dev/null; echo two >> "$wd/d.txt"
check "clean refuses work newer than the patch" "! fbr clean delta >/dev/null 2>&1"
fbr patch delta >/dev/null
check "clean refuses a patch never applied" "fails_with 'never applied' fbr clean delta"
fbr apply delta >/dev/null && git commit -qm "wave 2"
check "clean accepts once the patch is applied" "fbr clean delta >/dev/null && [ ! -d \"$wd\" ]"
wd=$(fbr add delta)
echo three > "$wd/e.txt"
check "a reused job name sets its old patch aside" "[ ! -f .fullburn/patches/delta.patch ] && [ ! -f .fullburn/patches/delta.applied ] && ls .fullburn/patches/delta.patch.* >/dev/null 2>&1"
check "clean refuses the reused job's unsaved work" "! fbr clean delta >/dev/null 2>&1"
fbr clean delta --force >/dev/null
we=$(fbr add epsilon)
git -C "$we" config --worktree --unset fullburn.base
check "clean refuses a worktree with no recorded base" "! fbr clean epsilon >/dev/null 2>&1"
fbr clean epsilon --force >/dev/null

wh=$(fbr add eta) && fbr patch eta >/dev/null && rm -rf "$wh"
check "add refuses a branch left from an earlier run, and keeps its patch" "fails_with 'left from an earlier run' fbr add eta && [ -f .fullburn/patches/eta.patch ]"
check "clean removes a branch whose worktree is gone" "fbr clean eta >/dev/null && ! git show-ref --verify --quiet refs/heads/wt/eta"
wt=$(fbr add theta) && echo t > "$wt/t.txt" && git -C "$wt" add t.txt && git -C "$wt" commit -qm stray && rm -rf "$wt"
check "clean keeps a gone worktree's branch with commits" "fails_with 'has commits that HEAD does not' fbr clean theta"
fbr clean theta --force >/dev/null

check "clean alpha, beta and zeta" "fbr clean alpha >/dev/null && fbr clean beta >/dev/null && fbr clean zeta >/dev/null"
check "worktrees and branches removed" "[ ! -d \"$wa\" ] && [ ! -d \"$wb\" ] && [ -z \"\$(git branch --list 'wt/*')\" ] && [ \"\$(git worktree list | wc -l | tr -d ' ')\" = 1 ]"
check "main tree clean after the wave" "[ -z \"\$(git status --porcelain)\" ]"

if [ "$fails" -eq 0 ]; then echo "fullburn.test.sh: all passed"; else echo "fullburn.test.sh: $fails failed"; exit 1; fi
