#!/usr/bin/env bash
# Regenerates scripts/AppIcon.icns from scripts/make-icon.swift.
# Only needed when the icon design changes; build-app.sh uses the committed .icns.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly ROOT_DIR
WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
readonly ICONSET="${WORK_DIR}/AppIcon.iconset"
trap 'rm -rf "${WORK_DIR}"' EXIT

swift "${ROOT_DIR}/scripts/make-icon.swift" "${WORK_DIR}/icon-1024.png"

mkdir -p "${ICONSET}"
for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${WORK_DIR}/icon-1024.png" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${WORK_DIR}/icon-1024.png" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "${ICONSET}" -o "${ROOT_DIR}/scripts/AppIcon.icns"
echo "Wrote ${ROOT_DIR}/scripts/AppIcon.icns"
