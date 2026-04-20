#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Clarc release script
#
# Usage:   ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.0.1
#
# Prerequisites:
#   - scripts/.env configured (see build_zip.sh)
#   - Developer ID Application certificate installed (see scripts/setup_cert.sh)
#   - gh CLI authenticated (gh auth login)
# ─────────────────────────────────────────────

VERSION=${1:-""}
if [ -z "$VERSION" ]; then
    echo "❌ Version argument required."
    echo "   Usage: ./scripts/release.sh 1.0.1"
    exit 1
fi

TAG="v${VERSION}"
ZIP="build/Clarc-${VERSION}.zip"
META_FILE="build/.sparkle_meta"

echo "▶ Starting Clarc ${TAG} release"
echo ""

# ── 1. Bump version in pbxproj ───────────────
PBXPROJ="Clarc.xcodeproj/project.pbxproj"
APPCAST="appcast.xml"

CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION = " "$PBXPROJ" | sed 's/.*= \([0-9]*\);/\1/')
if ! [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    echo "❌ Could not read CURRENT_PROJECT_VERSION from $PBXPROJ"
    exit 1
fi

APPCAST_MAX=0
if [ -f "$APPCAST" ]; then
    APPCAST_MAX=$(grep -oE "<sparkle:version>[0-9]+</sparkle:version>" "$APPCAST" \
        | grep -oE "[0-9]+" | sort -rn | head -1)
    APPCAST_MAX=${APPCAST_MAX:-0}
fi

if [ "$APPCAST_MAX" -gt "$CURRENT_BUILD" ]; then
    BASE_BUILD=$APPCAST_MAX
else
    BASE_BUILD=$CURRENT_BUILD
fi
NEW_BUILD=$((BASE_BUILD + 1))

echo "🔢 Bumping version"
echo "   MARKETING_VERSION     → ${VERSION}"
echo "   CURRENT_PROJECT_VERSION → ${NEW_BUILD}  (pbxproj=${CURRENT_BUILD}, appcast=${APPCAST_MAX})"

sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"
sed -i '' -E "s/MARKETING_VERSION = [0-9][0-9.]*;/MARKETING_VERSION = ${VERSION};/g" "$PBXPROJ"
echo ""

# ── 2. Build + notarize ──────────────────────
echo "📦 Building and notarizing..."
./scripts/build_zip.sh "$VERSION"
echo ""

# ── 3. Update appcast.xml ────────────────────
if [ -f "$META_FILE" ]; then
    echo "📡 Updating appcast.xml..."
    source "$META_FILE"

    REPO_URL="https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)"
    DOWNLOAD_URL="${REPO_URL}/releases/download/${TAG}/${SPARKLE_ZIP}"
    PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
    BUILD_NUMBER=$NEW_BUILD

    NEW_ITEM="    <item>
      <title>Clarc ${TAG}</title>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url=\"${DOWNLOAD_URL}\"
        length=\"${SPARKLE_SIZE}\"
        type=\"application/octet-stream\"
        sparkle:edSignature=\"${SPARKLE_SIGNATURE}\" />
    </item>"

    # Insert the new item right before </channel>
    python3 -c "
import sys
content = open('appcast.xml').read()
item = '''${NEW_ITEM}'''
content = content.replace('    <!-- Release entries are appended automatically by scripts/release.sh when running /release -->', '')
content = content.replace('  </channel>', item + '\n  </channel>')
open('appcast.xml', 'w').write(content)
"
    echo "✓ appcast.xml updated"
else
    echo "⚠️  Sparkle metadata missing — appcast.xml was not updated."
    echo "   First-time setup: ./scripts/setup_sparkle.sh"
fi
echo ""

# ── 4. Commit version bump + appcast.xml + push current branch ──
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ -f "$META_FILE" ]; then
    echo "📤 Committing version bump + appcast.xml on ${CURRENT_BRANCH}..."
    git add "$PBXPROJ" "$APPCAST"
    git commit -m "chore(release): ${TAG} (build ${NEW_BUILD})"
fi

echo "🔀 Pushing ${CURRENT_BRANCH}..."
git push origin "$CURRENT_BRANCH"
echo ""

# ── 5. Create tag ────────────────────────────
echo "🏷  Creating tag ${TAG}..."
git tag "$TAG"
git push origin "$TAG"
echo ""

# ── 6. Create GitHub Release + upload ZIP ────
echo "🚀 Creating GitHub Release..."
gh release create "$TAG" "$ZIP" \
    --title "Clarc ${TAG}" \
    --notes "## Clarc ${TAG}

### Installation
1. Download \`Clarc-${VERSION}.zip\`
2. Unzip and move \`Clarc.app\` to \`/Applications\`
3. On first launch, right-click → Open

> Existing users will receive this via the in-app auto-updater."
echo ""

echo "─────────────────────────────────────────"
echo "✅ Release complete: ${TAG}"
echo "   Release: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/${TAG}"
echo "   Appcast: https://raw.githubusercontent.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/main/appcast.xml"
echo "─────────────────────────────────────────"
