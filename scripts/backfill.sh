#!/usr/bin/env bash
# backfill.sh - Build and release all missing X/Twitter versions
#
# Scans ApkMirror for every stable version, checks which ones
# already have a GitHub release, and builds+releases the rest
# in ascending order (oldest missing first).
#
# Usage:
#   GITHUB_TOKEN=... ./scripts/backfill.sh          # build+release all missing
#   ./scripts/backfill.sh --dry-run                 # just list what would be built

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

source "$SCRIPT_DIR/build-variant.sh"
source "$SCRIPT_DIR/versions.sh"
source "$SCRIPT_DIR/download-apk.sh"

mkdir -p "$PROJECT_DIR"/{cache,downloads,output}

# --- One-time: resolve tool versions and cache binaries ------------------

echo "[backfill] Resolving tool versions..."
resolve_versions ""

echo "[backfill] Caching tools..."
MORPHE_JAR="$PROJECT_DIR/cache/morphe-cli.jar"
if [ ! -f "$MORPHE_JAR" ]; then
    echo "[backfill] Downloading Morphe CLI v${MORPHE_VERSION}..."
    curl -fsSL "$MORPHE_CLI_URL" -o "$MORPHE_JAR"
fi

PIKO_MPP="$PROJECT_DIR/cache/piko-${PIKO_VERSION}.mpp"
if [ ! -f "$PIKO_MPP" ]; then
    echo "[backfill] Downloading Piko patches v${PIKO_VERSION}..."
    curl -fsSL "$PIKO_MPP_URL" -o "$PIKO_MPP"
fi

XSHIM_MPP="$PROJECT_DIR/cache/x-shim-${XSHIM_VERSION}.mpp"
if [ ! -f "$XSHIM_MPP" ]; then
    echo "[backfill] Downloading Piko-Shim patches v${XSHIM_VERSION}..."
    curl -fsSL "$XSHIM_MPP_URL" -o "$XSHIM_MPP"
fi

# --- Get all stable versions (ascending) ---------------------------------

echo "[backfill] Fetching available versions from ApkMirror..."
ALL_VERSIONS=$(python3 "$SCRIPT_DIR/download-apk.py" x-corp twitter \
    --list-versions 2>/dev/null | sed 's/ *\[.*\]$//' || true)

if [ -z "$ALL_VERSIONS" ]; then
    echo "[backfill] Could not fetch version list from ApkMirror" >&2
    exit 1
fi

# Reverse to ascending order (ApkMirror lists newest first)
ALL_VERSIONS=$(echo "$ALL_VERSIONS" | tac)

# --- Iterate and build missing releases ----------------------------------

BUILT=0
SKIPPED=0

while IFS= read -r version; do
    [ -z "$version" ] && continue

    # Skip if already released on GitHub
    if gh release view "$version" &>/dev/null 2>&1; then
        echo "[backfill] Already released: ${version}"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo ""
    echo "================================================"
    echo "[backfill] Building missing version: ${version}"
    echo "================================================"

    if $DRY_RUN; then
        echo "[backfill]   (dry-run — would build)"
        BUILT=$((BUILT + 1))
        continue
    fi

    # Set X_VERSION and download APK for this version
    X_VERSION="$version"

    APK_FILE=$(download_apk "$X_VERSION" "$PROJECT_DIR/downloads")
    if [ -z "$APK_FILE" ] || [ ! -f "$APK_FILE" ]; then
        echo "[backfill] WARNING: download failed for ${version}, skipping" >&2
        continue
    fi

    # Build 4 variants
    build_all_variants

    # Create GitHub release
    echo "[backfill] Creating release ${version}..."
    NOTES=$(printf "Built with:\n- [Piko v${PIKO_VERSION}](https://github.com/crimera/piko/releases/tag/v${PIKO_VERSION})\n- [X-Shim v${XSHIM_VERSION}](https://gitlab.com/inotia00/x-shim/-/releases/v${XSHIM_VERSION})\n- [Morphe CLI v${MORPHE_VERSION}](https://github.com/MorpheApp/morphe-cli/releases/tag/v${MORPHE_VERSION})")
    gh release create "$version" \
        "$PROJECT_DIR"/output/*.apk \
        --title "$version" \
        --notes "$NOTES"

    echo "[backfill] Released: ${version}"

    # Clean output for next iteration
    rm -f "$PROJECT_DIR"/output/*.apk
    rm -f "$PROJECT_DIR"/cache/*.apkm

    BUILT=$((BUILT + 1))
done <<< "$ALL_VERSIONS"

echo ""
echo "=== Backfill complete ==="
echo "  Built + released: ${BUILT}"
echo "  Already existed:  ${SKIPPED}"
