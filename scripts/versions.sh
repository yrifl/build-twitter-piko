#!/usr/bin/env bash
# versions.sh - Resolve latest versions for Piko, X-Shim, Morphe CLI
# Shared by patch.sh (local) and CI workflows.
# Usage: source scripts/versions.sh [target_x_version]
#
# Sets these variables on success:
#   X_VERSION PIKO_VERSION XSHIM_VERSION MORPHE_VERSION
#   PIKO_MPP_URL XSHIM_MPP_URL MORPHE_CLI_URL
#   PIKO_SUPPORTED_MAX

set -euo pipefail

CURL_OPTS=(-sL --connect-timeout 5 --max-time 10)

PIKO_REPO="crimera/piko"
MORPHE_REPO="MorpheApp/morphe-cli"
XSHIM_PROJECT="inotia00%2Fx-shim"  # URL-encoded GitLab project path

# Fallback versions when GitHub/GitLab API is rate-limited
FALLBACK_PIKO_VERSION="3.6.0"
FALLBACK_MORPHE_VERSION="1.9.1"
FALLBACK_XSHIM_VERSION="1.6.2"

# Latest X version Piko currently supports (last resort fallback)
PIKO_SUPPORTED_MAX="12.0.0"

resolve_versions() {
    local target_x="${1:-}"

    echo "[versions] Fetching latest Piko release..."
    PIKO_VERSION=$(curl "${CURL_OPTS[@]}" "https://api.github.com/repos/${PIKO_REPO}/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"v([^"]+)".*/\1/') || true
    if [ -z "$PIKO_VERSION" ]; then
        PIKO_VERSION="$FALLBACK_PIKO_VERSION"
        echo "[versions]   Piko (API failed, fallback): v${PIKO_VERSION}"
    else
        echo "[versions]   Piko: v${PIKO_VERSION}"
    fi

    echo "[versions] Fetching latest X-Shim release..."
    local xshim_json
    xshim_json=$(curl "${CURL_OPTS[@]}" "https://gitlab.com/api/v4/projects/${XSHIM_PROJECT}/releases/permalink/latest") || true
    XSHIM_VERSION=$(echo "$xshim_json" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/') || true
    if [ -z "$XSHIM_VERSION" ]; then
        XSHIM_VERSION="$FALLBACK_XSHIM_VERSION"
        echo "[versions]   X-Shim (API failed, fallback): v${XSHIM_VERSION}"
    else
        echo "[versions]   X-Shim: v${XSHIM_VERSION}"
    fi

    echo "[versions] Fetching latest Morphe CLI release..."
    MORPHE_VERSION=$(curl "${CURL_OPTS[@]}" "https://api.github.com/repos/${MORPHE_REPO}/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"v([^"]+)".*/\1/') || true
    if [ -z "$MORPHE_VERSION" ]; then
        MORPHE_VERSION="$FALLBACK_MORPHE_VERSION"
        echo "[versions]   Morphe CLI (API failed, fallback): v${MORPHE_VERSION}"
    else
        echo "[versions]   Morphe CLI: v${MORPHE_VERSION}"
    fi

    # Resolve target X version
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -z "$target_x" ]; then
        echo "[versions]   Resolving latest X version from ApkMirror..."
        X_VERSION=$(python3 "${script_dir}/download-apk.py" x-corp twitter \
            --latest --print-version 2>/dev/null || echo "")
        if [ -z "$X_VERSION" ]; then
            X_VERSION="$PIKO_SUPPORTED_MAX"
            echo "[versions]   ApkMirror unavailable, using Piko max: v${X_VERSION}"
        else
            echo "[versions]   Latest from ApkMirror: v${X_VERSION}"
        fi
    else
        X_VERSION="$target_x"
        echo "[versions]   Target X version: ${X_VERSION}"
    fi

    # --- Build download URLs ---

    # Piko: fetch .mpp asset name from release API
    local piko_json
    piko_json=$(curl "${CURL_OPTS[@]}" "https://api.github.com/repos/${PIKO_REPO}/releases/tags/v${PIKO_VERSION}") || true
    PIKO_MPP_URL=$(echo "$piko_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].endswith('.mpp'):
        print(asset['browser_download_url'])
        break
" 2>/dev/null || echo "")
    if [ -z "$PIKO_MPP_URL" ]; then
        PIKO_MPP_URL="https://github.com/${PIKO_REPO}/releases/download/v${PIKO_VERSION}/patches-${PIKO_VERSION}.mpp"
    fi
    echo "[versions]   Piko MPP URL: ${PIKO_MPP_URL}"

    # X-Shim: extract .mpp direct asset URL from release JSON
    XSHIM_MPP_URL=$(echo "$xshim_json" \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
for link in data.get('assets', {}).get('links', []):
    name = link.get('name', '')
    if name.endswith('.mpp') and 'x-shim' in name.lower():
        print(link.get('direct_asset_url', ''))
        break
" 2>/dev/null || echo "")
    if [ -z "$XSHIM_MPP_URL" ]; then
        XSHIM_MPP_URL="https://gitlab.com/inotia00/x-shim/-/releases/v${XSHIM_VERSION}/downloads/patches-${XSHIM_VERSION}.mpp"
    fi
    echo "[versions]   X-Shim MPP URL: ${XSHIM_MPP_URL}"

    # Morphe CLI jar
    MORPHE_CLI_URL="https://github.com/${MORPHE_REPO}/releases/download/v${MORPHE_VERSION}/morphe-cli-${MORPHE_VERSION}-all.jar"
    echo "[versions]   Morphe CLI JAR URL: ${MORPHE_CLI_URL}"

    export X_VERSION PIKO_VERSION XSHIM_VERSION MORPHE_VERSION
    export PIKO_MPP_URL XSHIM_MPP_URL MORPHE_CLI_URL
    export PIKO_SUPPORTED_MAX
}
