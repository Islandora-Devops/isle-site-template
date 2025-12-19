#!/usr/bin/env bash

set -eou pipefail

echo "Checking for changes..."

# If there are no changes (untracked, modified, or staged), exit
if [ -z "$(git status --porcelain)" ]; then
    echo "No changes detected."
    exit 0
fi

echo "Changes detected."

if [ "${GITHUB_ACTIONS:-}" != "" ]; then
    echo "Running in GitHub Actions. Committing and creating PR..."
    
    # Configure git
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"

    BRANCH_NAME="chore/update-starter-site"
    git checkout -b $BRANCH_NAME
    
    git add .
    git commit -m "chore: update from islandora-starter-site"
    
    git push origin $BRANCH_NAME --force

    gh pr create \
      --title "Update from Islandora Starter Site" \
      --body "This PR updates the site template from the latest version of the islandora-starter-site repository. This is an automated PR." \
      --head "$BRANCH_NAME" \
      --base "main" \
      --label "automated pr,dependencies"
else
    echo "Not in a GitHub Actions environment. Staging changes."
    git add .
    echo "Changes are staged for commit. Please review and commit manually."
    git status
fi
