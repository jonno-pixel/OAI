#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project JJSVrij.xcodeproj -scheme JJSVrij -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/JJSVrij.xcarchive archive "$@"
