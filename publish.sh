#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
gh auth status >/dev/null
repo="TaZ1kS/omarchy-tweaks"
if gh repo view "$repo" >/dev/null 2>&1; then
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/$repo.git"
  fi
  git push -u origin main
else
  gh repo create "$repo" --public --source=. --remote=origin --push
fi
