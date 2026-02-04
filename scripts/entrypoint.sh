#!/bin/bash
# Simple entrypoint: configure git credentials, then run the command
set -e

# Configure git credentials if GITHUB_TOKEN is present
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    git config --global credential.helper /usr/local/bin/git-credential-github-token
    echo "[entrypoint] Git credential helper configured for GitHub"
else
    echo "[entrypoint] Warning: GITHUB_TOKEN not set, git push/pull to GitHub will not work"
fi

exec "$@"
