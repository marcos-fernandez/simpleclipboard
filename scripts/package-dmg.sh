#!/usr/bin/env bash
# Packs the app built by build-app.sh into a disk image with a link to /Applications, named after the app's version
# and architecture: SimpleClipboard-1.7.0-universal.dmg for a build that runs on Apple Silicon and Intel, and
# SimpleClipboard-1.7.0-arm64.dmg (or -x86_64) for a build of one of them.
# Both are read from the app itself, so the name cannot say something the build is not.
# APP_BUILD_DIR: the folder of the app and of the disk image (default: build/ in the repository), as in build-app.sh.
set -euo pipefail

readonly APP_NAME="SimpleClipboard"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly ROOT_DIR
readonly BUILD_DIR="${APP_BUILD_DIR:-${ROOT_DIR}/build}"
readonly APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

if [[ ! -d "${APP_DIR}" ]]; then
    echo "error: ${APP_DIR} not found; run scripts/build-app.sh first." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_DIR}/Contents/Info.plist")"
readonly VERSION
ARCHS="$(lipo -archs "${APP_DIR}/Contents/MacOS/${APP_NAME}")"
readonly ARCHS
if [[ " ${ARCHS} " == *" arm64 "* && " ${ARCHS} " == *" x86_64 "* ]]; then
    ARCH_NAME="universal"
else
    ARCH_NAME="${ARCHS// /-}"
fi
readonly ARCH_NAME
readonly DMG="${BUILD_DIR}/${APP_NAME}-${VERSION}-${ARCH_NAME}.dmg"

STAGING_DIR="$(mktemp -d)"
readonly STAGING_DIR
trap 'rm -rf "${STAGING_DIR}"' EXIT

# ditto, not cp: it keeps the signature of the app as it is.
ditto "${APP_DIR}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
# hdiutil, although macOS 27 says it is deprecated in favour of "diskutil image": it is the one that the runner of the
# releases and a local machine both have.
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -format UDZO -ov "${DMG}" >/dev/null

echo "Packed ${DMG}"
