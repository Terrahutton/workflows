#!/bin/bash
set -euo pipefail

APP_BASE="${1:?Usage: $0 <AppBaseName>}"
SIGN_IDENTITY="Developer ID Application: Terrahutton AB (793U5AWV3W)"
KEYCHAIN_PROFILE="TerrahuttonProfile"

APP_BUNDLE="${APP_BASE}.app"
ENTITLEMENTS="${APP_BASE}.entitlements"
NOTARIZE_ZIP="${APP_BASE}_notarize.zip"
FINAL_ZIP="${APP_BASE}.zip"

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "ERROR: App bundle not found: ${APP_BUNDLE}"
  exit 1
fi

if [[ ! -f "${ENTITLEMENTS}" ]]; then
  echo "ERROR: Entitlements file not found: ${ENTITLEMENTS}"
  exit 1
fi

echo "==> Removing old notarization/final zips"
rm -f "${NOTARIZE_ZIP}" "${FINAL_ZIP}"

echo "==> Clearing extended attributes"
xattr -cr "${APP_BUNDLE}"

echo "==> Signing nested native binaries"

# Sign standalone native libraries/plugins first.
# Important: do NOT pass entitlements to dylibs.
find "${APP_BUNDLE}/Contents" \
  \( -name "*.dylib" -o -name "*.so" -o -name "*.bundle" \) \
  -print0 | while IFS= read -r -d '' ITEM; do
    echo "Signing nested item: ${ITEM}"
    codesign --force --timestamp --options runtime \
      --sign "${SIGN_IDENTITY}" \
      "${ITEM}"
  done

echo "==> Signing frameworks, if any"

if [[ -d "${APP_BUNDLE}/Contents/Frameworks" ]]; then
  find "${APP_BUNDLE}/Contents/Frameworks" \
    \( -name "*.framework" -o -name "*.bundle" \) \
    -type d \
    -print0 | while IFS= read -r -d '' ITEM; do
      echo "Signing framework/bundle: ${ITEM}"
      codesign --force --timestamp --options runtime \
        --sign "${SIGN_IDENTITY}" \
        "${ITEM}"
    done
fi

echo "==> Signing main executable"

MAIN_EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${APP_BUNDLE}/Contents/Info.plist")
MAIN_EXECUTABLE_PATH="${APP_BUNDLE}/Contents/MacOS/${MAIN_EXECUTABLE}"

if [[ ! -f "${MAIN_EXECUTABLE_PATH}" ]]; then
  echo "ERROR: Main executable not found: ${MAIN_EXECUTABLE_PATH}"
  exit 1
fi

chmod +x "${MAIN_EXECUTABLE_PATH}"

codesign --force --timestamp --options runtime \
  --sign "${SIGN_IDENTITY}" \
  "${MAIN_EXECUTABLE_PATH}"

echo "==> Signing outer app bundle"

codesign --force --timestamp --options runtime \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${SIGN_IDENTITY}" \
  "${APP_BUNDLE}"

echo "==> Verifying signature"

codesign --verify --deep --strict --verbose=4 "${APP_BUNDLE}"

echo "==> Creating zip for notarization"

ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${NOTARIZE_ZIP}"

echo "==> Submitting to notarization service"

xcrun notarytool submit "${NOTARIZE_ZIP}" \
  --keychain-profile "${KEYCHAIN_PROFILE}" \
  --wait

echo "==> Stapling notarization ticket"

xcrun stapler staple "${APP_BUNDLE}"

echo "==> Verifying stapled app"

xcrun stapler validate "${APP_BUNDLE}"
spctl --assess --type execute --verbose=4 "${APP_BUNDLE}" || true

echo "==> Creating final zip"

rm -f "${NOTARIZE_ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${FINAL_ZIP}"

echo "==> Done: ${FINAL_ZIP}"