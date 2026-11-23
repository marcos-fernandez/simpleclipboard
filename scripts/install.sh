#!/usr/bin/env bash
# Downloads the latest release and installs it in /Applications, or updates the copy that is there. Meant to be piped
# from curl, which does not quarantine what it downloads, so macOS opens the app without "Open Anyway":
#   curl -fsSL https://raw.githubusercontent.com/marcos-fernandez/simpleclipboard/main/scripts/install.sh | bash
# Works in a new temporary folder, removed at the end, and stops at the first step that fails.
# INSTALL_DIR moves the folder the app is installed in (default: /Applications).
set -euo pipefail

readonly APP_NAME="SimpleClipboard"
readonly REPOSITORY="marcos-fernandez/simpleclipboard"
readonly INSTALL_DIR="${INSTALL_DIR:-/Applications}"
readonly API_TIMEOUT=30
readonly CONNECT_TIMEOUT=10
# For the whole disk image, a few MB, as the app's own download of an update.
readonly DOWNLOAD_TIMEOUT=300
# How long a running copy is given to quit (its last changes are written on the way out).
readonly QUIT_TIMEOUT=30

WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
readonly MOUNT_POINT="${WORK_DIR}/mount"

cleanup() {
    if [[ -d "${MOUNT_POINT}/${APP_NAME}.app" ]]; then
        hdiutil detach -quiet "${MOUNT_POINT}" || true
    fi
    rm -rf "${WORK_DIR}"
}

fail() {
    echo "error: $*" >&2
    exit 1
}

# Everything runs from here, called on the last line: a download cut short never runs half of the script.
main() {
    local release
    local version
    local image
    trap cleanup EXIT

    if ! release="$(curl -fsSL --connect-timeout "${CONNECT_TIMEOUT}" --max-time "${API_TIMEOUT}" \
        "https://api.github.com/repos/${REPOSITORY}/releases/latest")"; then
        fail "cannot ask GitHub for the latest release (offline, or rate-limited); try again later."
    fi
    # Only plain digits and dots: nothing else from the answer reaches a URL or a path.
    version="$(sed -n 's/.*"tag_name": *"v\([0-9.]*\)".*/\1/p' <<<"${release}")"
    if [[ -z "${version}" ]]; then
        fail "the latest release on GitHub has no version like v1.2.3."
    fi
    image="${WORK_DIR}/${APP_NAME}-${version}-universal.dmg"

    echo "Downloading ${APP_NAME} ${version}..."
    curl -fL --connect-timeout "${CONNECT_TIMEOUT}" --max-time "${DOWNLOAD_TIMEOUT}" -o "${image}" \
        "https://github.com/${REPOSITORY}/releases/download/v${version}/${APP_NAME}-${version}-universal.dmg" \
        || fail "cannot download the disk image of ${version}."
    hdiutil attach -nobrowse -readonly -noautoopen -quiet -mountpoint "${MOUNT_POINT}" "${image}" \
        || fail "cannot open the disk image of ${version}."
    if [[ ! -d "${MOUNT_POINT}/${APP_NAME}.app" ]]; then
        fail "the disk image of ${version} has no ${APP_NAME}.app."
    fi

    # A normal quit, so the last changes are written, and not before the new copy is at hand.
    if pgrep -xq "${APP_NAME}"; then
        echo "Quitting ${APP_NAME}..."
        osascript -e "quit app \"${APP_NAME}\""
        local waited=0
        while pgrep -xq "${APP_NAME}"; do
            if ((waited >= QUIT_TIMEOUT * 5)); then
                fail "${APP_NAME} did not quit; quit it and run this again."
            fi
            sleep 0.2
            waited=$((waited + 1))
        done
    fi
    # Replaced whole, not copied over: a file the new version no longer has would break its signature.
    rm -rf "${INSTALL_DIR:?}/${APP_NAME}.app"
    # ditto, not cp: it keeps the signature of the app as it is.
    ditto "${MOUNT_POINT}/${APP_NAME}.app" "${INSTALL_DIR}/${APP_NAME}.app"
    echo "Installed ${INSTALL_DIR}/${APP_NAME}.app (${version})"
    open "${INSTALL_DIR}/${APP_NAME}.app"
}

main "$@"
