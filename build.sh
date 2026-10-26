#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="build/CP24 HLS Kiosk.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" releases
xcrun swiftc -O -parse-as-library -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macos13 -framework IOKit -framework ServiceManagement -framework Network -o "$APP/Contents/MacOS/CP24HLSKiosk" Sources/CP24HLSKiosk/*.swift
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/NewsTVKioskIcon.icns "$APP/Contents/Resources/NewsTVKioskIcon.icns"
codesign --force --deep --sign - "$APP"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP" releases/CP24-HLS-Kiosk-v2.23-Apple-Silicon.zip
codesign --verify --deep --strict "$APP"
echo "Built releases/CP24-HLS-Kiosk-v2.23-Apple-Silicon.zip"
