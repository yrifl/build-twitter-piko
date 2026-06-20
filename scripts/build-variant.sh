#!/usr/bin/env bash
# build-variant.sh - Shared build logic for X/Twitter APK variants
# Source this from patch.sh or backfill.sh after setting:
#   PROJECT_DIR, MORPHE_JAR, PIKO_MPP, XSHIM_MPP, X_VERSION, APK_FILE

set -euo pipefail

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

XSHIM_PATCHES=(
    "Piko-Shim"
    "Abstract shim layer"
    "Abstract shim layer for native library"
    "Abstract shim layer for method"
)

build_variant() {
    local variant_name="$1"
    local include_dynamic_color="$2"

    local -a includes=()

    if [ "$variant_name" = "twitter" ]; then
        includes+=(-e "Bring back twitter")
    fi
    if [ "$include_dynamic_color" = "true" ]; then
        includes+=(-e "Dynamic color")
    fi

    local suffix=""
    [ "$include_dynamic_color" = "true" ] && suffix="-material-you"

    local output_name="${variant_name}-piko${suffix}-${X_VERSION}"
    local apk_path="$PROJECT_DIR/output/${output_name}.apk"

    local variant_input="$PROJECT_DIR/cache/${output_name}.apkm"
    cp "$APK_FILE" "$variant_input"

    echo "[build] Building ${output_name}..."
    java -jar "$MORPHE_JAR" patch \
        "${includes[@]}" \
        "${XSHIM_ARGS[@]}" \
        --patches "$PIKO_MPP" \
        --patches "$XSHIM_MPP" \
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

    echo "[build] Done: ${output_name}"
    ls -lh "$apk_path"
    echo ""
}

build_all_variants() {
    local -a xshim_args=()
    for p in "${XSHIM_PATCHES[@]}"; do
        xshim_args+=(-e "$p")
    done
    XSHIM_ARGS=("${xshim_args[@]}")

    mkdir -p "$PROJECT_DIR"/output

    echo "[build] Patching X/Twitter ${X_VERSION}..."
    echo "[build]   Piko + Piko-Shim (${#XSHIM_ARGS[@]} shim patches)"
    echo ""

    local pids=()
    build_variant "x" false & pids+=($!)
    build_variant "x" true  & pids+=($!)
    build_variant "twitter" false & pids+=($!)
    build_variant "twitter" true  & pids+=($!)

    for pid in "${pids[@]}"; do
        wait "$pid" || { echo "[build] ERROR: a variant build failed (pid $pid)" >&2; exit 1; }
    done

    echo "=== All variants built ==="
    ls -lh "$PROJECT_DIR"/output/*.apk
}
