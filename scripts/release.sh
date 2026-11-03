#!/usr/bin/env bash
# Builds a universal Release of Volume Customizer signed with the self-signed certificate,
# zips it for GitHub Releases, and fills in the Homebrew cask.
#
# Version comes from CFBundleShortVersionString in project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IDENTITY="Sound Space Self-Signed"
BUILD_DIR=build.noindex  # same as the Makefile; Spotlight skips it
REPOSITORY=$(sed -n 's/^ *VolumeCustomizerGitHubRepository: *//p' project.yml)
VERSION=$(sed -n 's/^ *CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)

fail() { echo "error: $*" >&2; exit 1; }

security find-identity -p codesigning | grep -q "$IDENTITY" \
    || fail "signing identity '$IDENTITY' is not in the keychain (backup: ~/.config/sound-space/signing/signing.p12)"
git diff --quiet && git diff --cached --quiet || fail "commit your changes first"
[[ -n "$VERSION" ]] || fail "could not read CFBundleShortVersionString from project.yml"

echo "==> Volume Customizer $VERSION"
xcodegen generate --quiet

echo "==> Running tests"
xcodebuild -project VolumeCustomizer.xcodeproj -scheme VolumeCustomizer -configuration Debug -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="$IDENTITY" -quiet test

echo "==> Building universal Release"
rm -rf "$BUILD_DIR/release" dist
mkdir -p dist
xcodebuild -project VolumeCustomizer.xcodeproj -scheme VolumeCustomizer -configuration Release -derivedDataPath "$BUILD_DIR/release" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    -quiet build

APP="$BUILD_DIR/release/Build/Products/Release/VolumeCustomizer.app"
codesign --verify --strict "$APP"
codesign -dr - "$APP" 2>&1 | grep -q "certificate leaf" || fail "app is not signed with '$IDENTITY'"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/VolumeCustomizer")
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "expected a universal binary, got: $ARCHS"

ZIP="dist/VolumeCustomizer-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
sed -e "s|{{VERSION}}|$VERSION|g" -e "s|{{SHA256}}|$SHA|g" -e "s|{{REPOSITORY}}|$REPOSITORY|g" \
    packaging/homebrew/volume-customizer.rb.template > dist/volume-customizer.rb

cat <<EOF

==> Done
    $ZIP  ($ARCHS)
    sha256 $SHA
    dist/volume-customizer.rb  (copy to Casks/ in the homebrew-volume-customizer tap)

Publish:
    git tag v$VERSION && git push origin v$VERSION
    gh release create v$VERSION "$ZIP" --repo $REPOSITORY --title "Volume Customizer $VERSION" --generate-notes
EOF
