#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ASSIGNMENTS_DIR="$REPO_ROOT/assignments"
COMMIT_MESSAGE="${1:-Sync assignment PDFs}"

if [[ ! -d "$ASSIGNMENTS_DIR" ]]; then
  printf 'Missing assignments directory: %s\n' "$ASSIGNMENTS_DIR" >&2
  exit 1
fi

pdf_count="$(find "$ASSIGNMENTS_DIR" -type f -iname '*.pdf' | wc -l | tr -d ' ')"
find "$ASSIGNMENTS_DIR" -type f -iname '*.pdf' -exec cp -p '{}' "$REPO_ROOT/" \;
printf 'Copied %s assignment PDF(s) into the repository root.\n' "$pdf_count"

git -C "$REPO_ROOT" add -A

if git -C "$REPO_ROOT" diff --cached --quiet; then
  printf 'Nothing new to commit.\n'
  exit 0
fi

git -C "$REPO_ROOT" commit -m "$COMMIT_MESSAGE"
git -C "$REPO_ROOT" push origin HEAD
