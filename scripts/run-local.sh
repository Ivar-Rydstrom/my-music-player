#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -project StillPlayer.xcodeproj -scheme StillPlayer -configuration Debug \
  -derivedDataPath build CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
open build/Build/Products/Debug/StillPlayer.app --args "$@"
