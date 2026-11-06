#!/bin/zsh
# Builds a signed Release copy of Still and packages it for GitHub Releases.
#
#   zsh scripts/build-release.sh 0.2.0 [build-number]
#
# Produces dist/Still-<version>.dmg (first install) and dist/Still-<version>.zip (in-app updates).
# Set STILL_SIGNING_IDENTITY to a certificate's SHA-1 hash to sign with it. Without it the app is
# ad hoc signed, which runs locally but can't install updates in place.
set -euo pipefail
cd "${0:A:h:h}"

version=${1:?usage: build-release.sh <version> [build-number]}
version=${version#v}
build=${2:-1}
if [[ ! $version =~ '^[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z.]+)?$' ]]; then
  print -u2 "Version must look like 1.2.3 (got $version)."
  exit 1
fi
marketing=${version%%-*}
identity=${STILL_SIGNING_IDENTITY:--}
if [[ -z ${DEVELOPER_DIR:-} && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

derived=build/release
app=$derived/Build/Products/Release/StillPlayer.app
log=build/release.log
rm -rf "$derived/Build/Products" dist
mkdir -p dist build

print "Building Still $version ($build)…"
if ! xcodebuild -project StillPlayer.xcodeproj -scheme StillPlayer -configuration Release \
  -derivedDataPath "$derived" MARKETING_VERSION="$marketing" CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGNING_ALLOWED=NO build >"$log" 2>&1; then
  grep -E 'error:' "$log" || tail -40 "$log"
  print -u2 "Build failed. Full log: $log"
  exit 1
fi

codesign --force --options runtime --timestamp=none --entitlements Config/StillPlayer.entitlements \
  --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"
codesign --display --requirements - "$app" 2>&1 | grep designated

ditto -c -k --sequesterRsrc --keepParent "$app" "dist/Still-$version.zip"

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/StillPlayer.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Still $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov \
  "dist/Still-$version.dmg" >/dev/null

(cd dist && shasum -a 256 Still-* > SHA256SUMS.txt && cat SHA256SUMS.txt)
