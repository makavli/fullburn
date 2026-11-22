#!/usr/bin/env bash
# Copies the sample repository in and commits it, so the skill starts from a clean git tree.
set -eu
cp -R "$(dirname "$0")/files/." .
git init -q -b main
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm "textkit 0.1.0"
