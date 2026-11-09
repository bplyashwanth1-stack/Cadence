#!/bin/zsh
# Ships a new version of Cadence:   scripts/release.sh 1.2
#
# Bumps the version in Info.plist, commits and tags it, waits for GitHub to build and publish Cadence.zip, then
# points the Homebrew formula (in the homebrew-tap repo, ~/Projects/homebrew-tap by default) at the new version.
set -e
cd "$(dirname "$0")/.."

VERSION=$1
if [[ ! "$VERSION" =~ '^[0-9]+(\.[0-9]+)+$' ]]; then
  echo "usage: scripts/release.sh <version>   e.g. scripts/release.sh 1.2"
  exit 1
fi
TAG=v$VERSION
REPO=bplyashwanth1-stack/Cadence
TAP=${CADENCE_TAP:-$HOME/Projects/homebrew-tap}
FORMULA=$TAP/Formula/cadence.rb

fail() { echo "✗ $1"; exit 1; }

# Check everything before changing anything.
[[ "$(git branch --show-current)" == main ]] || fail "Switch to the main branch first."
[[ -z "$(git status --porcelain)" ]] || fail "Commit or stash your changes first."
git fetch -q origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main isn't in sync with GitHub; push or pull first."
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists."
[[ -f "$FORMULA" ]] || fail "Homebrew formula not found at $FORMULA (set CADENCE_TAP to the tap's folder)."
[[ -z "$(git -C "$TAP" status --porcelain)" ]] || fail "The homebrew-tap folder has uncommitted changes."
git -C "$TAP" pull -q --ff-only

echo "→ Releasing Cadence $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Info.plist
git commit -q -m "Cadence $VERSION" Info.plist
git tag -a "$TAG" -m "Cadence $VERSION"
git push -q origin main "$TAG"

echo "→ Waiting for GitHub to build Cadence.zip (a few minutes)…"
RUN=""
for _ in {1..30}; do
  RUN=$(gh run list -R $REPO --workflow Release --branch "$TAG" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
  [[ -n "$RUN" ]] && break
  sleep 5
done
[[ -n "$RUN" ]] || fail "The release build didn't start. Check https://github.com/$REPO/actions"
gh run watch "$RUN" -R $REPO --exit-status --interval 20 >/dev/null \
  || fail "The release build failed. See: gh run view $RUN -R $REPO --log-failed"

echo "→ Updating the Homebrew formula"
SHA=$(curl -sfL "https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz" | shasum -a 256 | cut -d' ' -f1)
[[ ${#SHA} -eq 64 ]] || fail "Couldn't download the $TAG source to checksum it."
sed -i '' -e "s|/tags/v[0-9.]*\.tar\.gz|/tags/$TAG.tar.gz|" -e "s|sha256 \"[0-9a-f]*\"|sha256 \"$SHA\"|" "$FORMULA"
git -C "$TAP" commit -q -m "Cadence $VERSION" Formula/cadence.rb
git -C "$TAP" push -q origin main

echo "✓ Cadence $VERSION is out"
echo "  Release:  https://github.com/$REPO/releases/tag/$TAG"
echo "  Homebrew: brew upgrade cadence"
