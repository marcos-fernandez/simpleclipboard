#!/usr/bin/env bash
# Runs the unit tests.
# With Command Line Tools only, swift-build intermittently fails to resolve the
# Swift Testing macro plugin ("plugin for module 'TestingMacros' not found"),
# so its directory is passed explicitly.
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly PLUGIN_DIR="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"

cd "${ROOT_DIR}"
swift test -Xswiftc -plugin-path -Xswiftc "${PLUGIN_DIR}" "$@"
