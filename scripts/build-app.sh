#!/usr/bin/env bash
# Builds build/SimpleClipboard.app from the SwiftPM release binary and signs it.
# Signs with the "Clipboard Local Signing" certificate when present so the
# Accessibility permission survives rebuilds; falls back to ad-hoc signing.
# Releases set UNIVERSAL=1 (one binary for Apple Silicon and Intel), APP_VERSION and SIGNING_IDENTITY.
# APP_VERSION defaults to the latest git tag without its leading v.
# APP_BUILD_DIR moves the folder the app is created in (default: build/ in the repository), and SwiftPM's own
# SWIFTPM_BUILD_DIR moves .build: both together keep every build product out of the repository.
set -euo pipefail

readonly APP_NAME="SimpleClipboard"
# SwiftPM executable target (internal name, kept from before the rename).
readonly PRODUCT_NAME="Clipboard"
readonly SIGNING_IDENTITY="${SIGNING_IDENTITY:-Clipboard Local Signing}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly ROOT_DIR
readonly APP_DIR="${APP_BUILD_DIR:-${ROOT_DIR}/build}/${APP_NAME}.app"
readonly APP_BINARY="${APP_DIR}/Contents/MacOS/${APP_NAME}"

cd "${ROOT_DIR}"
# A local build would otherwise say Info.plist's 1.0 and report every release as an update: it takes the latest tag's
# version instead. Without a tag (or without git) Info.plist's is kept.
if [[ -z "${APP_VERSION:-}" ]]; then
    LATEST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    APP_VERSION="${LATEST_TAG#v}"
fi
readonly APP_VERSION
BUILD_ARGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
readonly BUILD_ARGS
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
readonly BIN_DIR

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${PRODUCT_NAME}" "${APP_BINARY}"
cp "${ROOT_DIR}/scripts/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${ROOT_DIR}/scripts/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" "${APP_DIR}/Contents/Info.plist"
fi

# With Command Line Tools only, SwiftPM stamps the binary with the deployment target as the SDK it was built with
# (sdk 14.0), and macOS then draws and treats the app as one built for macOS 14. The stamp is set to the SDK in use;
# a binary that already names its SDK, as the ones built with Xcode do, is left alone. Before signing: it changes
# the binary.
BUILD_VERSION="$(vtool -show-build "${APP_BINARY}")"
readonly BUILD_VERSION
MIN_OS_VERSION="$(awk '$1 == "minos" { print $2; exit }' <<<"${BUILD_VERSION}")"
readonly MIN_OS_VERSION
STAMPED_SDK_VERSION="$(awk '$1 == "sdk" { print $2; exit }' <<<"${BUILD_VERSION}")"
readonly STAMPED_SDK_VERSION
if [[ "${STAMPED_SDK_VERSION}" == "${MIN_OS_VERSION}" ]]; then
    SDK_VERSION="$(xcrun --show-sdk-version)"
    readonly SDK_VERSION
    vtool -set-build-version macos "${MIN_OS_VERSION}" "${SDK_VERSION}" -replace -output "${APP_BINARY}" "${APP_BINARY}"
fi

# No grep -q in a pipe: under pipefail, grep exiting on the first match while the writer is still writing fails the
# pipeline. Not find-identity -v: the self-signed certificate is listed as CSSMERR_TP_NOT_TRUSTED, which -v leaves
# out; only expired ones are skipped.
IDENTITIES="$(security find-identity -p codesigning || true)"
readonly IDENTITIES
if grep -F "\"${SIGNING_IDENTITY}\"" <<<"${IDENTITIES}" | grep -v "CSSMERR_TP_CERT_EXPIRED" >/dev/null; then
    codesign --force --sign "${SIGNING_IDENTITY}" "${APP_DIR}"
else
    echo "warning: certificate '${SIGNING_IDENTITY}' not found; signing ad-hoc." >&2
    echo "         Accessibility permission will have to be granted again after every build." >&2
    echo "         Create it in Keychain Access > Certificate Assistant > Create a Certificate…" >&2
    echo "         (Name: ${SIGNING_IDENTITY}, Identity Type: Self Signed Root, Certificate Type: Code Signing)." >&2
    codesign --force --sign - "${APP_DIR}"
fi

echo "Built ${APP_DIR}"
