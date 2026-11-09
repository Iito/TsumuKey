#!/bin/sh
# Builds an IPA for sideloading (AltStore, SideStore, Sideloadly, Feather...),
# which re-sign it with the user's own Apple ID.
#
# The app and keyboard are ad-hoc signed ("-") with their entitlements, so the
# re-signing tool sees the App Group they share; AltStore and SideStore rename
# it per Apple ID and record the new name in Info.plist (ALTAppGroups, read by
# Shared/Settings.swift).
#
# usage: Tools/make_ipa.sh      -> dist/TsumuKey-<version>.ipa
# Needs Tools/build_llama_ios.sh to have run once.
set -e
cd "$(dirname "$0")/.."

xcodegen generate -q
xcodebuild -project TsumuKey.xcodeproj -scheme TsumuKey -configuration Release \
  -destination generic/platform=iOS -derivedDataPath build-ipa \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

APP=build-ipa/Build/Products/Release-iphoneos/TsumuKey.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Info.plist")

# Inner bundles first, then the app.
codesign -f -s - --entitlements Keyboard/Keyboard.entitlements "$APP/PlugIns/Keyboard.appex"
codesign -f -s - --entitlements App/TsumuKey.entitlements "$APP"

STAGE=build-ipa/stage
rm -rf "$STAGE" && mkdir -p "$STAGE/Payload" dist
cp -R "$APP" "$STAGE/Payload/"
OUT="dist/TsumuKey-$VERSION.ipa"
rm -f "$OUT"
(cd "$STAGE" && zip -qry -X "../../$OUT" Payload)

SIZE=$(stat -f %z "$OUT")
echo "$OUT  version $VERSION (build $BUILD)  $SIZE bytes"
