#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/app-config.sh"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICONSET_DIR="${DIST_DIR}/AwakeIcon.iconset"

cd "${ROOT_DIR}"

# Full Xcode supplies SwiftUI macro plugins missing from some Command Line Tools SDKs.
# Select it for these subprocesses only; do not change the machine's xcode-select setting.
SWIFT=(/usr/bin/xcrun swift)
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    SWIFT=(/usr/bin/env "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" /usr/bin/xcrun swift)
fi
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

if [[ "${UNIVERSAL}" == "1" ]]; then
    BINARIES=()
    for ARCH in arm64 x86_64; do
        BUILD_FLAGS=(-c "${BUILD_CONFIGURATION}" --triple "${ARCH}-apple-macosx26.0" --scratch-path "${ROOT_DIR}/.build/${ARCH}")
        "${SWIFT[@]}" build "${BUILD_FLAGS[@]}" --product "${EXECUTABLE_NAME}"
        BUILD_DIR="$("${SWIFT[@]}" build "${BUILD_FLAGS[@]}" --show-bin-path)"
        BINARIES+=("${BUILD_DIR}/${EXECUTABLE_NAME}")
    done
    /usr/bin/lipo -create "${BINARIES[@]}" -output "${MACOS_DIR}/${EXECUTABLE_NAME}"
else
    "${SWIFT[@]}" build -c "${BUILD_CONFIGURATION}" --product "${EXECUTABLE_NAME}"
    BUILD_DIR="$("${SWIFT[@]}" build -c "${BUILD_CONFIGURATION}" --show-bin-path)"
    cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
fi
cp "${MACOS_DIR}/${EXECUTABLE_NAME}" "${MACOS_DIR}/${WATCHDOG_NAME}"

"${SWIFT[@]}" "${ROOT_DIR}/scripts/make-app-icon.swift" "${ICONSET_DIR}" "${ROOT_DIR}/Assets/Brand/AppIcon.png"
iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Awake. All rights reserved.</string>
</dict>
</plist>
PLIST

printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

codesign --force --deep --sign - "${APP_DIR}"

touch "${APP_DIR}"

ditto -c -k --keepParent "${APP_DIR}" "${DIST_DIR}/${EXECUTABLE_NAME}-${VERSION}.zip"

echo "Built ${APP_DIR}"
echo "Created ${DIST_DIR}/${EXECUTABLE_NAME}-${VERSION}.zip"
echo "Install locally: open ${APP_DIR}"
