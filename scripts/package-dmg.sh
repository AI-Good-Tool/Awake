#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/app-config.sh"
DIST_DIR="${ROOT_DIR}/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awake-dmg.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT
APP_DIR="${DIST_DIR}/${APP_NAME}.app"

cd "${ROOT_DIR}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    bash "${ROOT_DIR}/scripts/package-local.sh"
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_DIR}/Contents/Info.plist")"
DMG_PATH="${DIST_DIR}/${EXECUTABLE_NAME}-${VERSION}.dmg"

ditto "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s "/Applications" "${STAGING_DIR}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

echo "Created ${DMG_PATH}"
