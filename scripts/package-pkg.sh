#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/app-config.sh"
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awake-pkg.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    bash "${ROOT_DIR}/scripts/package-local.sh"
fi
codesign --verify --deep --strict "${APP_DIR}"
mkdir -p "${STAGING_DIR}/root/Applications"
ditto "${APP_DIR}" "${STAGING_DIR}/root/Applications/${APP_NAME}.app"

# Pin installation to /Applications, rather than relocating to a developer checkout.
pkgbuild --analyze --root "${STAGING_DIR}/root" "${STAGING_DIR}/components.plist"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "${STAGING_DIR}/components.plist"
/usr/libexec/PlistBuddy -c "Set :0:BundleOverwriteAction upgrade" "${STAGING_DIR}/components.plist"
pkgbuild \
    --root "${STAGING_DIR}/root" \
    --component-plist "${STAGING_DIR}/components.plist" \
    --identifier "${BUNDLE_ID}.installer" \
    --version "${VERSION}" \
    --install-location "/" \
    "${STAGING_DIR}/Awake-component.pkg"

cat > "${STAGING_DIR}/Distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>${APP_NAME}</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <allowed-os-versions><os-version min="26.0"/></allowed-os-versions>
    <choices-outline><line choice="default"><line choice="${BUNDLE_ID}.installer"/></line></choices-outline>
    <choice id="default"/>
    <choice id="${BUNDLE_ID}.installer" visible="false"><pkg-ref id="${BUNDLE_ID}.installer"/></choice>
    <pkg-ref id="${BUNDLE_ID}.installer" version="${VERSION}" onConclusion="none">Awake-component.pkg</pkg-ref>
</installer-gui-script>
XML

PKG_PATH="${DIST_DIR}/${EXECUTABLE_NAME}-${VERSION}.pkg"
productbuild --distribution "${STAGING_DIR}/Distribution.xml" --package-path "${STAGING_DIR}" "${PKG_PATH}"
echo "Created ${PKG_PATH}"
