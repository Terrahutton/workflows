#!/bin/bash
set -euo pipefail

APP_BASE="${1:?Usage: $0 <AppBaseName>}"
SIGN_IDENTITY="Developer ID Application: Terrahutton AB (793U5AWV3W)"
KEYCHAIN_PROFILE="TerrahuttonProfile"

APP_BUNDLE="${APP_BASE}.app"
ENTITLEMENTS="${APP_BASE}.entitlements"
NOTARIZE_ZIP="${APP_BASE}_notarize.zip"
FINAL_ZIP="${APP_BASE}.zip"

echo "==> Signing ${APP_BUNDLE}"
codesign --deep --force --verify --verbose --timestamp --options runtime \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${SIGN_IDENTITY}" \
  "${APP_BUNDLE}"

echo "==> Creating zip for notarization"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${NOTARIZE_ZIP}"

echo "==> Submitting to notarization service"
xcrun notarytool submit "${NOTARIZE_ZIP}" \
  --keychain-profile "${KEYCHAIN_PROFILE}" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "${APP_BUNDLE}"

echo "==> Creating final zip"
rm -f "${NOTARIZE_ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${FINAL_ZIP}"

echo "==> Done: ${FINAL_ZIP}"
