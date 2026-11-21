#!/bin/bash
# Builds build/Calm.pkg. Runs on a Mac (GitHub Actions does this for you).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(tr -d "[:space:]" < VERSION)}"
OUT=build
ROOT="$OUT/root"
rm -rf "$OUT"
mkdir -p "$ROOT/Library/PrivilegedHelperTools" "$ROOT/Library/LaunchDaemons" "$ROOT/Library/LaunchAgents" \
         "$ROOT/Library/Application Support/Calm" "$ROOT/Applications/CalmBar.app/Contents/MacOS"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

cp "$BIN/calmd" "$ROOT/Library/PrivilegedHelperTools/com.calm.calmd"
cp "$BIN/CalmBar" "$ROOT/Applications/CalmBar.app/Contents/MacOS/CalmBar"
cp Resources/app/Info.plist "$ROOT/Applications/CalmBar.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT/Applications/CalmBar.app/Contents/Info.plist"
cp Resources/launchd/com.calm.calmd.plist "$ROOT/Library/LaunchDaemons/"
cp Resources/launchd/com.calm.bar.plist "$ROOT/Library/LaunchAgents/"
cp scripts/reload-bar.sh "$ROOT/Library/Application Support/Calm/reload-bar.sh"
chmod 755 "$ROOT/Library/Application Support/Calm/reload-bar.sh"

# Browser extension: black page instead of an error for blocked sites (Chrome, Comet and other Chromium browsers).
EXT="$ROOT/Library/Application Support/Calm/BlankPage"
mkdir -p "$EXT"
cp Resources/blankpage/* "$EXT/"
"$BIN/calmd" --print-sites > "$EXT/sites.json"

# Adult-site lists (StevenBlack/hosts extensions). The DNS filter is the main defence; this is extra.
ADULT="$ROOT/Library/Application Support/Calm/adult-hosts.txt"
: > "$ADULT"
for list in extensions/porn/sinfonietta/hosts extensions/porn/clefspeare13/hosts; do
    if curl -fsSL --max-time 120 "https://raw.githubusercontent.com/StevenBlack/hosts/master/$list" -o "$OUT/list.tmp"; then
        grep -E '^0\.0\.0\.0[[:space:]]' "$OUT/list.tmp" >> "$ADULT" || true
    else
        echo "warning: could not download $list (continuing; the DNS filter still blocks adult sites)"
    fi
done
sort -u -o "$ADULT" "$ADULT"
echo "adult list: $(wc -l < "$ADULT") sites"

# Desktop widgets: an app extension inside CalmBar.app (sandboxed; signed before the app).
WEX="$ROOT/Applications/CalmBar.app/Contents/PlugIns/CalmWidgets.appex/Contents"
mkdir -p "$WEX/MacOS"
cp "$BIN/CalmWidgets" "$WEX/MacOS/CalmWidgets"
cp Resources/widgets/Info.plist "$WEX/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$WEX/Info.plist"
codesign --force --sign - --entitlements Resources/widgets/CalmWidgets.entitlements \
    "$ROOT/Applications/CalmBar.app/Contents/PlugIns/CalmWidgets.appex"

# Ad-hoc signatures (required on Apple silicon). Not notarized: first open is right-click → Open.
codesign --force --sign - "$ROOT/Library/PrivilegedHelperTools/com.calm.calmd"
codesign --force --sign - "$ROOT/Applications/CalmBar.app"

chmod 755 scripts/pkg-scripts/preinstall scripts/pkg-scripts/postinstall

# Strip extended attributes so the payload has no ._ AppleDouble files.
export COPYFILE_DISABLE=1
xattr -cr "$ROOT"

# Always install CalmBar.app into /Applications (never "relocate" it to another copy).
pkgbuild --analyze --root "$ROOT" "$OUT/components.plist"
count=$(/usr/libexec/PlistBuddy -c "Print" "$OUT/components.plist" | grep -c "RootRelativeBundlePath" || true)
for ((i = 0; i < count; i++)); do
    /usr/libexec/PlistBuddy -c "Set :$i:BundleIsRelocatable false" "$OUT/components.plist" 2>/dev/null || true
done

pkgbuild --root "$ROOT" --component-plist "$OUT/components.plist" --scripts scripts/pkg-scripts \
    --identifier com.calm.pkg --version "$VERSION" --install-location / "$OUT/Calm.pkg"
echo "Built $OUT/Calm.pkg"
