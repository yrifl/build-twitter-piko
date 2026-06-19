#!/usr/bin/env bash
# download-apk.sh - Download X/Twitter APK from ApkMirror
# Shared by patch.sh (local) and CI workflows.
#
# Order of precedence:
#   1. APK_URL env var (direct download URL)
#   2. APK_PATH env var (local file path, copied)
#   3. Python cloudscraper downloader (handles CloudFlare)
#   4. Interactive picker (TTY) or error (CI)

set -euo pipefail

download_apk() {
    local version="$1"
    local output_dir="$2"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    echo "[download] output_dir=${output_dir}" >&2
    echo "[download] version=${version}" >&2
    mkdir -p "$output_dir"

    # 1. Direct URL
    local apk_url="${APK_URL:-}"
    if [ -n "$apk_url" ]; then
        echo "[download] Downloading from APK_URL..." >&2
        local outfile="${output_dir}/X-${version}.apk"
        if curl -fsSL "$apk_url" -o "$outfile" && [ -s "$outfile" ]; then
            echo "[download] Saved: ${outfile}" >&2
            echo "$outfile"
            return 0
        fi
        echo "[download] APK_URL download failed, trying next method..." >&2
    fi

    # 2. Local file
    local apk_path="${APK_PATH:-}"
    if [ -n "$apk_path" ]; then
        if [ -f "$apk_path" ]; then
            local outfile="${output_dir}/X-${version}.apk"
            echo "[download] Using APK from APK_PATH: ${apk_path}" >&2
            cp "$apk_path" "$outfile"
            echo "$outfile"
            return 0
        fi
        echo "[download] APK_PATH set but not found: ${apk_path}" >&2
    fi

    # 3. Python cloudscraper downloader (handles CloudFlare)
    if command -v python3 &>/dev/null; then
        local py_args=()
        if [ "$version" = "latest" ] || [ "$version" = "auto" ]; then
            py_args=(--latest)
            echo "[download] Resolving latest version from ApkMirror..." >&2
        else
            py_args=(--version "$version")
        fi

        echo "[download] Running download-apk.py (org=x-corp, repo=twitter)..." >&2
        result=$(python3 "${script_dir}/download-apk.py" x-corp twitter \
            "${py_args[@]}" \
            --outdir "$output_dir")
        echo "[download] Python stdout (result) raw:" >&2
        echo "${result}" >&2

        if [ -n "$result" ]; then
            local dl_file dl_version

            if echo "$result" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
                dl_file=$(echo "$result" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['file'])")
                dl_version=$(echo "$result" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['version'])")
                echo "[download] Parsed: version=${dl_version}" >&2
                echo "[download] Parsed: file=${dl_file}" >&2
            else
                echo "[download] Invalid JSON from Python (raw first 200 chars):" >&2
                echo "${result}" | head -c 200 >&2
                echo >&2
                dl_file=""
            fi

            if [ -n "$dl_file" ] && [ -s "$dl_file" ]; then
                echo "[download] Saved: ${dl_file}" >&2
                echo "$dl_file"
                return 0
            else
                echo "[download] File check failed: dl_file='${dl_file}' exists=$([ -f "${dl_file}" ] && echo yes || echo no) size=$([ -f "${dl_file}" ] && stat -c%s "${dl_file}" || echo N/A)" >&2
            fi
        fi

        echo "[download] Python downloader failed" >&2
    else
        echo "[download] python3 not available" >&2
    fi

    # 4. Interactive picker (TTY only)
    if [ -t 0 ]; then
        echo "[download] Automatic download failed." >&2
        echo "[download] Showing version picker..." >&2
        if command -v python3 &>/dev/null; then
            result=$(python3 "${script_dir}/download-apk.py" x-corp twitter --interactive --outdir "$output_dir")
            if [ -n "$result" ]; then
                dl_file=$(echo "$result" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['file'])" 2>/dev/null || echo "")
                if [ -n "$dl_file" ] && [ -s "$dl_file" ]; then
                    echo "[download] Saved: ${dl_file}" >&2
                    echo "$dl_file"
                    return 0
                fi
            fi
        fi

        echo "[download] Interactive download also failed." >&2
        read -r -p "Enter path to X/Twitter APK: " apk_path
        if [ -n "$apk_path" ] && [ -f "$apk_path" ]; then
            local outfile="${output_dir}/X-${version}.apk"
            cp "$apk_path" "$outfile"
            echo "[download] Copied: ${outfile}" >&2
            echo "$outfile"
            return 0
        fi
        read -r -p "Enter direct download URL: " apk_url
        if [ -n "$apk_url" ]; then
            local outfile="${output_dir}/X-${version}.apk"
            curl -fsSL "$apk_url" -o "$outfile" && [ -s "$outfile" ] && {
                echo "[download] Saved: ${outfile}" >&2
                echo "$outfile"
                return 0
            }
        fi
    fi

    cat >&2 <<FAIL
[download] ERROR: Could not obtain X/Twitter APK.
Options:
  - Export APK_PATH=/path/to/X.apk and re-run
  - Export APK_URL=<direct-download-url> and re-run
  - Manually download from: https://www.apkmirror.com/apk/x-corp/twitter/
FAIL
    return 1
}
