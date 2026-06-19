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

# All Piko patches. "Bring back twitter" and "Dynamic color" are
# toggled per variant below; everything else applies to all.
PIKO_PATCHES_ALL=(
    "Remove Ads"
    "Download patch"
    "Dynamic color"
    "Enable force HD videos"
    "Enable PiP mode automatically"
    "Enable Undo Posts"
    "Hide Banner"
    "Hide Community Notes"
    "Hide FAB"
    "Hide FAB Menu Buttons"
    "Hide Live Threads"
    "Hide Recommended Users"
    "Hide badges from navigation bar icons"
    "Hide bookmark icon in timeline"
    "Hide community badges"
    "Hide followed by context"
    "Hide hidden replies"
    "Hide immersive player"
    "Hide nudge button"
    "Hide post metrics"
    "Hide promote button"
    "Hide recommendation items"
    "Hook feature flag"
    "Block redirecting to X Lite"
    "Bring back twitter"
    "Clear tracking params"
    "Control video auto scroll"
    "Custom download folder"
    "Custom sharing domain"
    "Customise post font size"
    "Customize Inline action Bar items"
    "Customize Navigation Bar items"
    "Customize default reply sorting"
    "Customize explore tabs"
    "Customize notification tabs"
    "Customize profile tabs"
    "Customize search suggestions"
    "Customize search tab items"
    "Customize side bar items"
    "Customize timeline top bar"
    "Delete from database"
    "Disable auto timeline scroll on launch"
    "Disable chirp font"
    "Export all activities"
    "Force enable translate"
    "Handle custom twitter links"
    "Import/Export login token"
    "Legacy share links"
    "Log server response"
    "Native reader mode"
    "Native translator"
    "No shortened URL"
    "Pause search suggestions"
    "Remove premium upsell"
    "Remove search suggestions"
    "Remove view count"
    "Round off numbers"
    "Selectable Text"
    "Share Tweet as Image"
    "Show changelogs"
    "Show poll results"
    "Show post source label"
    "Show sensitive media"
    "Add ability to copy media link"
    "Change app icon"
    "Change version code"
    "Browse tweet object"
)

# Base set excluding the two togglable patches (no longer used for
# --exclusive; left here for reference of which patches are available)


XSHIM_PATCHES=(
    "Piko-Shim"
    "Abstract shim layer"
    "Abstract shim layer for native library"
    "Abstract shim layer for method"
)

# --- Build one variant ------------------------------------------------
build_variant() {
    local variant_name="$1"
    local include_dynamic_color="$2"

    local -a excludes=()

    if [ "$variant_name" != "twitter" ]; then
        excludes+=(-d "Bring back twitter")
    fi
    if [ "$include_dynamic_color" != "true" ]; then
        excludes+=(-d "Dynamic color")
    fi

    local suffix=""
    [ "$include_dynamic_color" = "true" ] && suffix="-material-you"

    local output_name="${variant_name}-piko${suffix}-${X_VERSION}"
    local apk_path="$PROJECT_DIR/output/${output_name}.apk"

    # Copy to per-variant temp file to avoid merge/patched output races
    local variant_input="$PROJECT_DIR/cache/${output_name}.apkm"
    cp "$APK_FILE" "$variant_input"

    echo "[patch] Building ${output_name}..."
    java -jar "$MORPHE_JAR" patch \
        --patches "$PIKO_MPP" "${excludes[@]}" \
        --patches "$XSHIM_MPP" "${XSHIM_ARGS[@]}" \
        --out "$apk_path" \
        "$variant_input"

    rm -f "$variant_input"

    if [ ! -f "$apk_path" ]; then
        local actual
        actual=$(find "$PROJECT_DIR/output" -name "*${output_name}*" -type f -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
        if [ -n "$actual" ]; then
            mv -f "$actual" "$apk_path"
        fi
    fi

    echo "[patch] Done: ${output_name}"
    ls -lh "$apk_path"
    echo ""
}

# --- Steps ------------------------------------------------------------

source "$SCRIPT_DIR/versions.sh"
resolve_versions "${1:-}"

mkdir -p "$PROJECT_DIR"/{cache,downloads,output}

source "$SCRIPT_DIR/download-apk.sh"
APK_FILE=$(download_apk "$X_VERSION" "$PROJECT_DIR/downloads")
if [ $? -ne 0 ] || [ ! -f "$APK_FILE" ]; then
    echo "FATAL: could not obtain APK for X/Twitter $X_VERSION" >&2
    exit 1
fi

# Cache Morphe CLI
MORPHE_JAR="$PROJECT_DIR/cache/morphe-cli.jar"
if [ ! -f "$MORPHE_JAR" ]; then
    echo "[patch] Downloading Morphe CLI v${MORPHE_VERSION}..."
    curl -fsSL "$MORPHE_CLI_URL" -o "$MORPHE_JAR"
fi

# Cache Piko patches
PIKO_MPP="$PROJECT_DIR/cache/piko-${PIKO_VERSION}.mpp"
if [ ! -f "$PIKO_MPP" ]; then
    echo "[patch] Downloading Piko patches v${PIKO_VERSION}..."
    curl -fsSL "$PIKO_MPP_URL" -o "$PIKO_MPP"
fi

# Cache Piko-Shim patches
XSHIM_MPP="$PROJECT_DIR/cache/x-shim-${XSHIM_VERSION}.mpp"
if [ ! -f "$XSHIM_MPP" ]; then
    echo "[patch] Downloading Piko-Shim patches v${XSHIM_VERSION}..."
    curl -fsSL "$XSHIM_MPP_URL" -o "$XSHIM_MPP"
fi

# Build -e flag arrays for shim patches (shared by all variants)
XSHIM_ARGS=()
for p in "${XSHIM_PATCHES[@]}"; do
    XSHIM_ARGS+=(-e "$p")
done

echo "[patch] Patching X/Twitter ${X_VERSION}..."
echo "[patch]   Piko v${PIKO_VERSION} + Piko-Shim v${XSHIM_VERSION}"
echo ""

pids=()
build_variant "x" false & pids+=($!)
build_variant "x" true  & pids+=($!)
build_variant "twitter" false & pids+=($!)
build_variant "twitter" true  & pids+=($!)

for pid in "${pids[@]}"; do
    wait "$pid" || { echo "[patch] ERROR: a variant build failed (pid $pid)" >&2; exit 1; }
done

echo "=== All variants built ==="
ls -lh "$PROJECT_DIR"/output/*.apk
echo ""
echo "Install examples:"
echo "  adb install output/x-piko-${X_VERSION}.apk"
echo "  adb install output/x-piko-material-you-${X_VERSION}.apk"
echo "  adb install output/twitter-piko-${X_VERSION}.apk"
echo "  adb install output/twitter-piko-material-you-${X_VERSION}.apk"
