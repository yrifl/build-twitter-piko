#!/usr/bin/env bash
# patch.sh - Build patched X/Twitter APKs with Piko + Piko-Shim
#
# Usage:
#   ./scripts/patch.sh                          # auto: latest supported X version
#   ./scripts/patch.sh 12.0.0-release.0         # specific version
#   APK_PATH=/path/to/x.apk ./scripts/patch.sh  # use local APK
#   APK_URL=https://... ./scripts/patch.sh       # download from URL
#
# Output (4 variants):
#   ./output/x-piko-<version>.apk
#   ./output/x-piko-material-you-<version>.apk
#   ./output/twitter-piko-<version>.apk
#   ./output/twitter-piko-material-you-<version>.apk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/versions.sh"
resolve_versions "${1:-}"

source "$SCRIPT_DIR/build-variant.sh"
source "$SCRIPT_DIR/download-apk.sh"

mkdir -p "$PROJECT_DIR"/{cache,downloads,output}

APK_FILE=$(download_apk "$X_VERSION" "$PROJECT_DIR/downloads")
if [ $? -ne 0 ] || [ ! -f "$APK_FILE" ]; then
    echo "FATAL: could not obtain APK for X/Twitter $X_VERSION" >&2
    exit 1
fi

MORPHE_JAR="$PROJECT_DIR/cache/morphe-cli.jar"
if [ ! -f "$MORPHE_JAR" ]; then
    echo "[patch] Downloading Morphe CLI v${MORPHE_VERSION}..."
    curl -fsSL "$MORPHE_CLI_URL" -o "$MORPHE_JAR"
fi

PIKO_MPP="$PROJECT_DIR/cache/piko-${PIKO_VERSION}.mpp"
if [ ! -f "$PIKO_MPP" ]; then
    echo "[patch] Downloading Piko patches v${PIKO_VERSION}..."
    curl -fsSL "$PIKO_MPP_URL" -o "$PIKO_MPP"
fi

XSHIM_MPP="$PROJECT_DIR/cache/x-shim-${XSHIM_VERSION}.mpp"
if [ ! -f "$XSHIM_MPP" ]; then
    echo "[patch] Downloading Piko-Shim patches v${XSHIM_VERSION}..."
    curl -fsSL "$XSHIM_MPP_URL" -o "$XSHIM_MPP"
fi

build_all_variants

echo ""
echo "Install examples:"
echo "  adb install output/x-piko-${X_VERSION}.apk"
echo "  adb install output/x-piko-material-you-${X_VERSION}.apk"
echo "  adb install output/twitter-piko-${X_VERSION}.apk"
echo "  adb install output/twitter-piko-material-you-${X_VERSION}.apk"
