#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/app-config.sh"

UNIVERSAL=1 BUILD_CONFIGURATION=release bash "${ROOT_DIR}/scripts/package-local.sh"
SKIP_BUILD=1 bash "${ROOT_DIR}/scripts/package-dmg.sh"
SKIP_BUILD=1 bash "${ROOT_DIR}/scripts/package-pkg.sh"

APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
codesign --verify --deep --strict "${APP_DIR}"
for BINARY in "${EXECUTABLE_NAME}" "${WATCHDOG_NAME}"; do
    for ARCH in arm64 x86_64; do
        lipo "${APP_DIR}/Contents/MacOS/${BINARY}" -verify_arch "${ARCH}"
    done
done
cd "${ROOT_DIR}/dist"
shasum -a 256 "${EXECUTABLE_NAME}-${VERSION}.dmg" "${EXECUTABLE_NAME}-${VERSION}.pkg" "${EXECUTABLE_NAME}-${VERSION}.zip" > "SHA256SUMS.txt"
shasum -a 256 -c "SHA256SUMS.txt"
