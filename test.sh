#!/bin/sh
# Compiles the pure parts of the launcher (Sources/Core) together with Tests/ into a
# throwaway test binary and runs it. No XCTest: the project builds with the Command
# Line Tools alone, and XCTest ships only with Xcode.
set -eu

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="${TMPDIR:-/tmp}/aeroapp-launcher-tests"
mkdir -p "$BUILD_DIR"

swiftc -o "$BUILD_DIR/tests" \
    "$SRC_DIR"/Sources/Core/*.swift \
    "$SRC_DIR"/Tests/*.swift

exec "$BUILD_DIR/tests"
