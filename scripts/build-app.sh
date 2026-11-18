#!/usr/bin/env bash
# Builds build/SimpleClipboard.app from the SwiftPM release binary and signs it.
# Signs with the "Clipboard Local Signing" certificate when present so the
# Accessibility permission survives rebuilds; falls back to ad-hoc signing.
set -euo pipefail

readonly APP_NAME="SimpleClipboard"
# SwiftPM executable target (internal name, kept from before the rename).
readonly PRODUCT_NAME="Clipboard"
readonly SIGNING_IDENTITY="Clipboard Local Signing"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly ROOT_DIR
readonly APP_DIR="${ROOT_DIR}/build/${APP_NAME}.app"

cd "${ROOT_DIR}"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
readonly BIN_DIR

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${PRODUCT_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${ROOT_DIR}/scripts/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${ROOT_DIR}/scripts/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

if security find-identity -p codesigning | grep -q "${SIGNING_IDENTITY}"; then
    codesign --force --sign "${SIGNING_IDENTITY}" "${APP_DIR}"
else
    echo "warning: certificate '${SIGNING_IDENTITY}' not found; signing ad-hoc." >&2
    echo "         Accessibility permission will have to be granted again after every build." >&2
    echo "         Create it in Keychain Access > Certificate Assistant > Create a Certificate…" >&2
    echo "         (Name: ${SIGNING_IDENTITY}, Identity Type: Self Signed Root, Certificate Type: Code Signing)." >&2
    codesign --force --sign - "${APP_DIR}"
fi

echo "Built ${APP_DIR}"
