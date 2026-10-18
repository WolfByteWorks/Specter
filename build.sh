#!/bin/bash
# Builds Specter, assembles the .app bundle in "Specter v<version>/", and makes the
# release zip and Sparkle update feed (appcast.xml) next to it for GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="01.04.04"
BUILD="17"
# GitHub repo whose Releases host the zip and appcast.xml.
REPO="WolfByteWorks/Specter"
# Sparkle public key. The private key is stored only locked (Signing/sparkle-key.locked); it is
# unlocked through the "Specter Sparkle" SSH key in Bitwarden to sign the update feed (never Keychain).
ED_KEY="wX6AfTLpt7q5OcZwMeVxb5fJNY/vnNWP4XIkgq8RHvA="
LOCKED_KEY="${SPARKLE_LOCKED_KEY:-Signing/sparkle-key.locked}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
OUT="Specter v$VERSION"
APP="$OUT/Specter_v$VERSION.app"

swift build -c release --arch arm64 --disable-sandbox
PRODUCTS="$(swift build -c release --arch arm64 --disable-sandbox --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/Specter" "$APP/Contents/MacOS/Specter"
cp -R "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/"
# Sparkle's license (with its bsdiff and ed25519 notices) must ship with the app.
mkdir -p "$APP/Contents/Resources/Licenses"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Licenses/Sparkle-LICENSE.txt"
cp -R Resources/1-second-of-silence.mp3 Resources/Logo.png Resources/MenuBarIcon.png Resources/MenuBarIconBlack.png Resources/MenuBarTemplate.png Resources/MenuBarTemplate@2x.png Resources/Branding "$APP/Contents/Resources/"
# App icon in the macOS 26 icon format (Icon Composer). actool writes Assets.car plus an
# AppIcon.icns fallback for older macOS.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon \
    --platform macosx --minimum-deployment-target 13.0 \
    --output-partial-info-plist "${TMPDIR:-/tmp}/specter-actool-partial.plist" >/dev/null
# actool can report errors and still exit 0, so make sure the icon is really there.
if [ ! -f "$APP/Contents/Resources/Assets.car" ] || [ ! -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    echo "App icon was not compiled (actool). Not building a release without it." >&2; exit 1
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Specter</string>
    <key>CFBundleDisplayName</key><string>Specter</string>
    <key>CFBundleExecutable</key><string>Specter</string>
    <key>CFBundleIdentifier</key><string>works.wolfbyte.Specter</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/$REPO/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>$ED_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"

# Release zip and update feed for this version (upload both to the GitHub release v$VERSION).
ZIP="$OUT/Specter_v$VERSION.zip"
rm -f "$ZIP" "$OUT/appcast.xml"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
if python3 -I scripts/sparkle-key.py unlock "$LOCKED_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" -o "$OUT/appcast.xml" "$OUT"; then
    echo "Signed $OUT/appcast.xml"
else
    echo "appcast.xml not made: unlock Bitwarden (with its SSH agent on) and run again."
fi
echo "Built $APP, $ZIP and $OUT/appcast.xml"
