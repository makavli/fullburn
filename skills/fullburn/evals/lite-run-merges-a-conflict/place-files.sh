#!/usr/bin/env bash
# Copies the sample repository in and commits it, so the skill starts from a clean git tree.
set -eu
[ ! -e .git ] || { echo "place-files.sh: this folder is already a git repository" >&2; exit 1; }
cp -R "$(dirname "$0")/files/." .
# usage-watch keeps its state inside this test repository, never in the real ~/.claude/usage-watch.
mkdir -p .claude
printf '{ "env": { "USAGE_WATCH_HOME": "%s" } }\n' "$PWD/.git/usage-watch" > .claude/settings.json
git init -q -b main
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm "textkit 0.1.0"
