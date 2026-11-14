#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Xcode op macOS is vereist.'; exit 1; }
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
sdk_major="${sdk_version%%.*}"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :objects:00000000000000000000000C:buildSettings:IPHONEOS_DEPLOYMENT_TARGET' ClockChat.xcodeproj/project.pbxproj)"
if (( sdk_major < ${minimum%%.*} )); then
  echo "Dit project vereist iOS SDK $minimum of nieuwer. Gevonden: $sdk_version. Kies nieuwere Xcode, of verlaag bewust de minimumversie in beide projectconfiguraties."
  exit 1
fi
xcodebuild -project ClockChat.xcodeproj -scheme ClockChat -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -archivePath build/ClockChat.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
mkdir -p build/package/Payload
ditto build/ClockChat.xcarchive/Products/Applications/ClockChat.app build/package/Payload/ClockChat.app
(cd build/package && /usr/bin/zip -qry ../ClockChat-unsigned.ipa Payload)
echo 'Gemaakt: build/ClockChat-unsigned.ipa — moet nog door AltStore worden ondertekend.'
