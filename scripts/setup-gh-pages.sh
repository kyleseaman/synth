#!/usr/bin/env bash
set -euo pipefail

# Creates the gh-pages branch with a placeholder appcast.xml.
# Run once from the repo root, then enable GitHub Pages on the gh-pages branch.

BRANCH="gh-pages"

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "Branch '$BRANCH' already exists locally. Aborting."
  exit 1
fi

git checkout --orphan "$BRANCH"
git rm -rf . > /dev/null 2>&1 || true
git clean -fd > /dev/null 2>&1 || true

cat > appcast.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Synth</title>
    <!-- Stable and beta items are managed by the release workflow -->
  </channel>
</rss>
EOF

git add appcast.xml
git commit -m "chore: initialize gh-pages with placeholder appcast"

echo ""
echo "Done. gh-pages branch created locally."
echo "Switch back to your working branch with: git checkout main"
echo "Then enable GitHub Pages in repo Settings → Pages → Source: gh-pages branch."
