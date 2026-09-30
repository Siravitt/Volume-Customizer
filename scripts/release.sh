#!/usr/bin/env bash
# Builds a universal Release of Sound Space signed with the self-signed certificate,
# zips it for GitHub Releases, and fills in the Homebrew cask.
#
# Version comes from CFBundleShortVersionString in project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
IDENTITY="Sound Space Self-Signed"
REPOSITORY=$(sed -n 's/^ *SoundSpaceGitHubRepository: *//p' project.yml)
VERSION=$(sed -n 's/^ *CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)

fail() { echo "error: $*" >&2; exit 1; }

security find-identity -p codesigning | grep -q "$IDENTITY" \
    || fail "signing identity '$IDENTITY' is not in the keychain (backup: ~/.config/sound-space/signing/signing.p12)"
git diff --quiet && git diff --cached --quiet || fail "commit your changes first"
[[ -n "$VERSION" ]] || fail "could not read CFBundleShortVersionString from project.yml"

echo "==> Sound Space $VERSION"
xcodegen generate --quiet

echo "==> Running tests"
xcodebuild -project SoundSpace.xcodeproj -scheme SoundSpace -configuration Debug -derivedDataPath build \
    CODE_SIGN_IDENTITY="$IDENTITY" -quiet test

echo "==> Building universal Release"
rm -rf build/release dist
mkdir -p dist
xcodebuild -project SoundSpace.xcodeproj -scheme SoundSpace -configuration Release -derivedDataPath build/release \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    -quiet build

APP=build/release/Build/Products/Release/SoundSpace.app
codesign --verify --strict "$APP"
codesign -dr - "$APP" 2>&1 | grep -q "certificate leaf" || fail "app is not signed with '$IDENTITY'"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/SoundSpace")
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || fail "expected a universal binary, got: $ARCHS"

ZIP="dist/SoundSpace-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
sed -e "s|{{VERSION}}|$VERSION|g" -e "s|{{SHA256}}|$SHA|g" -e "s|{{REPOSITORY}}|$REPOSITORY|g" \
    packaging/homebrew/sound-space.rb.template > dist/sound-space.rb

cat <<EOF

==> Done
    $ZIP  ($ARCHS)
    sha256 $SHA
    dist/sound-space.rb  (copy to Casks/ in the homebrew-sound-space tap)

Publish:
    git tag v$VERSION && git push origin v$VERSION
    gh release create v$VERSION "$ZIP" --repo $REPOSITORY --title "Sound Space $VERSION" --generate-notes
EOF
