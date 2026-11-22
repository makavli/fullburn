#!/usr/bin/env bash
# The repository's own check, the same locally and in CI: skill frontmatter, plugin JSON, relative links in every
# tracked Markdown file, shellcheck on every script, then the script's self-test.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fails=0
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

skill=skills/fullburn/SKILL.md
fm=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$skill")
[ -n "$fm" ] || bad "$skill: no frontmatter"
grep -qx 'name: fullburn' <<< "$fm" || bad "$skill: name must be fullburn (the folder name)"
desc=$(awk '/^description:/{sub(/^description: */,""); print}' <<< "$fm")
[ -n "$desc" ] || bad "$skill: empty description"
[ "${#desc}" -le 1024 ] || bad "$skill: description over 1024 characters (${#desc})"
case "$desc" in *'<'*|*'>'*) bad "$skill: description holds angle brackets" ;; esac

for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$j" 2>/dev/null || bad "$j: invalid JSON"
done
v=$(node -p 'require("./.claude-plugin/plugin.json").version')
grep -q "^## $v " CHANGELOG.md || bad "CHANGELOG.md has no entry for $v"

# Relative links: [text](target) where target is not a URL or an anchor.
while IFS= read -r md; do
  dir=$(dirname "$md")
  while IFS= read -r target; do
    t=${target%%#*}
    [ -z "$t" ] && continue
    [ -e "$dir/$t" ] || bad "$md: broken link $target"
  done < <(grep -oE '\]\([^)[:space:]]+\)' "$md" | sed -E 's/^\]\((.*)\)$/\1/' | grep -vE '^(https?:|mailto:|#)')
done < <(git ls-files '*.md')

scripts=$(git ls-files '*.sh')
if command -v shellcheck >/dev/null; then
  # shellcheck disable=SC2086  # one word per tracked script path
  shellcheck $scripts || bad "shellcheck"
elif [ -n "${CI:-}" ] && [ "$(uname -s)" = Linux ]; then
  bad "shellcheck is not installed"  # CI's Linux image has it; its Windows image does not
else
  echo "skip shellcheck: not installed here (CI runs it)"
fi

log=$(mktemp)
bash tests/fullburn.test.sh > "$log" 2>&1 || { tail -20 "$log"; bad "tests/fullburn.test.sh"; }
rm -f "$log"

if [ "$fails" -eq 0 ]; then echo "check.sh: all passed"; else echo "check.sh: $fails failed"; exit 1; fi
