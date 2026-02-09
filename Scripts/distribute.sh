#!/bin/bash
# distribute.sh - Build, sign, notarize, and release ClaudeZellijWhip
#
# Usage: Scripts/distribute.sh <version>
# Example: Scripts/distribute.sh 0.2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"

# Configuration
APP_NAME="ClaudeZellijWhip"
BUNDLE_NAME="$APP_NAME.app"
DEVELOPER_ID="Developer ID Application: Cheol Kang (ESURPGU29C)"
KEYCHAIN_PROFILE="PasteFenceNotarization"

echo "=== $APP_NAME Distribution Script ==="
echo "Project: $PROJECT_DIR"

# Check version argument
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Error: VERSION is required"
    echo "Usage: $0 VERSION"
    echo "Example: $0 0.2.0"
    exit 1
fi

TAG="v$VERSION"
echo "Version: $VERSION (tag: $TAG)"

# Verify prerequisites
for cmd in gh xcrun codesign ditto shasum; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found. Install it first."
        exit 1
    fi
done

if ! gh auth status &>/dev/null; then
    echo "Error: Not authenticated with GitHub CLI. Run: gh auth login"
    exit 1
fi

# Check keychain profile exists
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null 2>&1; then
    echo "Error: Keychain profile '$KEYCHAIN_PROFILE' not found."
    echo "Create it with:"
    echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
    echo "      --apple-id \"me@cheol.me\" \\"
    echo "      --team-id \"ESURPGU29C\" \\"
    echo "      --password \"<app-specific-password>\""
    exit 1
fi

# Clean
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cd "$PROJECT_DIR"

# Step 1: Build
echo ""
echo "=== Step 1: Building Release ==="
make bundle
APP_PATH="$PROJECT_DIR/$BUNDLE_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found at $APP_PATH"
    exit 1
fi

# Step 2: Sign with Developer ID + hardened runtime
echo ""
echo "=== Step 2: Signing App Bundle ==="
echo "Signing with: $DEVELOPER_ID"

# Sign nested binaries first
find "$APP_PATH" -type f \( -name "*.dylib" -o -name "*.framework" \) -exec \
    codesign --force --options runtime --sign "$DEVELOPER_ID" {} \; 2>/dev/null || true

# Sign the main app bundle (no entitlements file needed for this app)
codesign --force --deep --options runtime \
    --sign "$DEVELOPER_ID" \
    "$APP_PATH"

echo "Verifying signature..."
codesign --verify --verbose "$APP_PATH"
echo "App signed successfully"

# Step 3: Create zip for notarization
echo ""
echo "=== Step 3: Creating ZIP for Notarization ==="
ZIP_FILE="$DIST_DIR/$APP_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_FILE"
echo "Created: $ZIP_FILE"

# Step 4: Notarize
echo ""
echo "=== Step 4: Submitting for Notarization ==="
echo "This may take a few minutes..."
xcrun notarytool submit "$ZIP_FILE" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

# Step 5: Staple notarization ticket to the .app
echo ""
echo "=== Step 5: Stapling Notarization Ticket ==="
xcrun stapler staple "$APP_PATH"

# Step 6: Re-zip after stapling (this is the release artifact)
echo ""
echo "=== Step 6: Creating Final ZIP ==="
rm -f "$ZIP_FILE"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_FILE"
echo "Final zip: $ZIP_FILE"

# Step 7: Verify
echo ""
echo "=== Step 7: Verifying ==="
spctl --assess --verbose "$APP_PATH"
echo "App is signed and notarized"

# Step 8: Generate SHA256
echo ""
echo "=== Step 8: Generating SHA256 Checksum ==="
SHA256_VALUE=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')
echo "$SHA256_VALUE  $(basename "$ZIP_FILE")" > "$ZIP_FILE.sha256"
echo "SHA256: $SHA256_VALUE"

# Step 9: Create git tag + GitHub release
echo ""
echo "=== Step 9: Creating GitHub Release ==="

# Create and push tag
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists locally."
else
    echo "Creating tag $TAG..."
    git tag "$TAG"
fi

echo "Pushing tag $TAG to origin..."
git push origin "$TAG" 2>/dev/null || echo "Tag already exists on remote."

# Generate release notes
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
if [ -n "$PREV_TAG" ]; then
    CHANGES=$(git log --pretty=format:"- %s" "$PREV_TAG"..HEAD --no-merges | head -20)
else
    CHANGES=$(git log --pretty=format:"- %s" -10 --no-merges)
fi

RELEASE_NOTES="## What's New

$CHANGES

## Installation

\`\`\`bash
brew install choru-k/tap/claude-zellij-whip
\`\`\`

## Checksum

\`\`\`
SHA256: $SHA256_VALUE
\`\`\`"

# Create or update release
if gh release view "$TAG" &>/dev/null; then
    echo "Release $TAG exists. Uploading assets..."
    gh release upload "$TAG" "$ZIP_FILE" "$ZIP_FILE.sha256" --clobber
else
    echo "Creating new release $TAG..."
    gh release create "$TAG" \
        --title "$APP_NAME $TAG" \
        --notes "$RELEASE_NOTES" \
        "$ZIP_FILE" "$ZIP_FILE.sha256"
fi

echo "Release: https://github.com/choru-k/claude-zellij-whip/releases/tag/$TAG"

# Step 10: Update Homebrew tap
echo ""
echo "=== Step 10: Updating Homebrew Tap ==="

HOMEBREW_TAP_DIRS=(
    "/tmp/homebrew-tap"
    "$HOME/Code/homebrew-tap"
    "$HOME/Projects/homebrew-tap"
    "$(dirname "$PROJECT_DIR")/homebrew-tap"
)

HOMEBREW_TAP_DIR=""
CASK_FILE="Casks/claude-zellij-whip.rb"
for dir in "${HOMEBREW_TAP_DIRS[@]}"; do
    if [ -d "$dir" ] && [ -f "$dir/$CASK_FILE" ]; then
        HOMEBREW_TAP_DIR="$dir"
        break
    fi
done

if [ -n "$HOMEBREW_TAP_DIR" ]; then
    echo "Found tap at: $HOMEBREW_TAP_DIR"
    cd "$HOMEBREW_TAP_DIR"

    sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK_FILE"
    sed -i '' "s/sha256 \".*\"/sha256 \"$SHA256_VALUE\"/" "$CASK_FILE"

    git add "$CASK_FILE"
    git commit -m "Update claude-zellij-whip to v$VERSION" || echo "No changes to commit"
    git push origin main || git push origin master

    echo "Homebrew tap updated"
    cd "$PROJECT_DIR"
else
    echo "Homebrew tap not found. Update manually:"
    echo "  version \"$VERSION\""
    echo "  sha256 \"$SHA256_VALUE\""
fi

# Summary
echo ""
echo "=== Distribution Complete ==="
echo "Files:"
ls -lh "$DIST_DIR"
echo ""
echo "SHA256: $SHA256_VALUE"
echo ""
echo "Next steps:"
echo "  brew reinstall --cask choru-k/tap/claude-zellij-whip"
echo "  spctl --assess --verbose /Applications/$BUNDLE_NAME"
