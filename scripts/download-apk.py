#!/usr/bin/env python3
"""Download APK from ApkMirror with CloudFlare bypass via cloudscraper."""

import argparse
import cloudscraper
import json
import os
import re
import sys
import time

APKMIRROR_BASE = "https://www.apkmirror.com"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
)
REQUEST_DELAY = 3

HAVE_TQDM = False
try:
    from tqdm import tqdm
    HAVE_TQDM = True
except ImportError:
    pass


def make_scraper():
    s = cloudscraper.create_scraper(
        browser={"browser": "chrome", "platform": "linux", "mobile": False}
    )
    s.headers.update({"User-Agent": USER_AGENT})
    return s


def fetch(scraper, url, retries=3):
    for attempt in range(retries):
        resp = scraper.get(url)
        if resp.status_code == 429:
            wait = REQUEST_DELAY * (attempt + 1)
            time.sleep(wait)
            continue
        resp.raise_for_status()
        return resp
    raise RuntimeError(f"Failed to fetch {url} after {retries} retries (rate limited)")


def scrape_versions(scraper, org, repo):
    resp = fetch(scraper, f"{APKMIRROR_BASE}/apk/{org}/{repo}/")
    matches = re.findall(
        rf'/apk/{re.escape(org)}/{re.escape(repo)}/x-(\d+-\d+-\d+)-(.+?)-release/',
        resp.text,
    )
    if not matches:
        raise RuntimeError(f"No release versions found for {org}/{repo}")

    seen = {}
    for nums, channel in matches:
        key = (nums, channel)
        if key not in seen:
            seen[key] = True

    def sort_key(item):
        nums, channel = item
        parts = nums.split("-")
        return tuple(int(p) for p in parts)

    sorted_versions = sorted(seen.keys(), key=sort_key, reverse=True)
    return sorted_versions


def scrape_latest_version(scraper, org, repo):
    sorted_versions = scrape_versions(scraper, org, repo)
    for nums, channel in sorted_versions:
        if "beta" not in channel and "alpha" not in channel:
            version = ".".join(nums.split("-")) + "-" + channel
            return version, nums
    latest_nums, latest_channel = sorted_versions[0]
    version = ".".join(latest_nums.split("-")) + "-" + latest_channel
    return version, latest_nums


def find_version_url(scraper, org, repo, version, latest_slug=None):
    resp = fetch(scraper, f"{APKMIRROR_BASE}/apk/{org}/{repo}/")
    if latest_slug:
        version_slug = latest_slug
    else:
        version_slug = version.lower().replace(".", "-").replace(" ", "-")

    version_links = re.findall(
        rf'href="(/apk/{re.escape(org)}/{re.escape(repo)}/(?:x|twitter|x-formerly-twitter|x-previously-twitter)-{re.escape(version_slug)}[^"]*?-release/)"',
        resp.text,
    )

    if not version_links:
        version_links = re.findall(
            rf'href="(/apk/{re.escape(org)}/{re.escape(repo)}/[^"]*?{re.escape(version_slug)}[^"]*?release/)"',
            resp.text,
        )

    if not version_links:
        raise RuntimeError(f"Version '{version}' not found for {org}/{repo}")

    unique = list(dict.fromkeys(version_links))
    unique.sort(key=lambda p: "beta" in p or "alpha" in p)
    return APKMIRROR_BASE + unique[0]


def find_variant_download_url(scraper, version_url):
    resp = fetch(scraper, version_url)
    time.sleep(REQUEST_DELAY)

    dl_links = re.findall(r'href="(/apk/[^"]*?android-apk-download/)"', resp.text)
    if dl_links:
        return APKMIRROR_BASE + dl_links[0]

    raise RuntimeError("Could not find download link for any variant")


def find_download_key_url(scraper, variant_url):
    resp = fetch(scraper, variant_url)
    time.sleep(REQUEST_DELAY)

    m = re.search(r'downloadButton[^>]*href="([^"]+)"', resp.text)
    if m:
        path = m.group(1)
        return path if path.startswith("http") else APKMIRROR_BASE + path

    raise RuntimeError("Could not find download button on variant page")


def extract_apk_url(scraper, key_url):
    resp = fetch(scraper, key_url)
    time.sleep(REQUEST_DELAY)

    m = re.search(
        r'href="(/wp-content/themes/APKMirror/download\.php[^"]*?)"', resp.text
    )
    if m:
        return APKMIRROR_BASE + m.group(1)

    m = re.search(r"download\.php\?id=(\d+)&key=([a-f0-9]+)", resp.text)
    if m:
        return f"{APKMIRROR_BASE}/wp-content/themes/APKMirror/download.php?id={m.group(1)}&key={m.group(2)}"

    raise RuntimeError("Could not find download.php URL")


def format_version_label(nums, channel):
    return ".".join(nums.split("-")) + "-" + channel


def list_versions(scraper, org, repo):
    versions = scrape_versions(scraper, org, repo)
    for nums, channel in versions:
        label = format_version_label(nums, channel)
        is_beta = "beta" in channel or "alpha" in channel
        tag = " [beta]" if is_beta else ""
        print(f"{label}{tag}")
    return versions


def interactive_pick(scraper, org, repo):
    versions = scrape_versions(scraper, org, repo)
    print(f"\nAvailable versions for {org}/{repo}:\n")
    for i, (nums, channel) in enumerate(versions, 1):
        label = format_version_label(nums, channel)
        is_beta = "beta" in channel or "alpha" in channel
        tag = " [beta]" if is_beta else ""
        print(f"  {i:>3}. {label}{tag}")
    print()
    while True:
        try:
            choice = input(f"Choose 1-{len(versions)} (or q to quit): ").strip()
            if choice.lower() in ("q", ""):
                sys.exit(0)
            idx = int(choice) - 1
            if 0 <= idx < len(versions):
                break
        except (ValueError, EOFError):
            pass
        print(f"Invalid choice, try 1-{len(versions)}")
    nums, channel = versions[idx]
    version = format_version_label(nums, channel)
    return version, nums


def main():
    parser = argparse.ArgumentParser(description="Download APK from ApkMirror")
    parser.add_argument("org", help="Organization (e.g., x-corp)")
    parser.add_argument("repo", help="Repo (e.g., twitter)")
    parser.add_argument("--version", "-v", help="Version to download")
    parser.add_argument("--latest", action="store_true", help="Download latest version")
    parser.add_argument("--print-version", action="store_true", help="Print latest version and exit")
    parser.add_argument("--list-versions", action="store_true", help="List available versions and exit")
    parser.add_argument("--interactive", "-i", action="store_true", help="Pick version interactively")
    parser.add_argument("--outdir", "-o", default=".", help="Output directory")
    parser.add_argument("--outfile", "-f", help="Output filename")
    args = parser.parse_args()

    if not args.version and not args.latest and not args.list_versions and not args.interactive:
        parser.error("Specify --version, --latest, --list-versions, or --interactive")

    scraper = make_scraper()

    if args.list_versions:
        list_versions(scraper, args.org, args.repo)
        return

    if args.interactive:
        version, latest_nums = interactive_pick(scraper, args.org, args.repo)
    elif args.latest or args.print_version:
        version, latest_nums = scrape_latest_version(scraper, args.org, args.repo)
        if args.print_version:
            print(version)
            return
    else:
        version = args.version
        latest_nums = None

    version_url = find_version_url(scraper, args.org, args.repo, version, latest_nums)
    variant_url = find_variant_download_url(scraper, version_url)
    key_url = find_download_key_url(scraper, variant_url)
    apk_url = extract_apk_url(scraper, key_url)

    time.sleep(REQUEST_DELAY)
    resp = scraper.get(apk_url, stream=True)
    resp.raise_for_status()

    ctype = resp.headers.get("content-type", "")
    ext = ".apkm" if "vnd.apkm" in ctype else ".apk"
    base = args.outfile or f"{args.repo}-{version}{ext}"
    output_file = os.path.join(args.outdir, base)
    os.makedirs(args.outdir, exist_ok=True)

    total = int(resp.headers.get("content-length", 0))
    desc = f"Downloading {os.path.basename(output_file)}"

    if HAVE_TQDM and total:
        progress = tqdm(total=total, unit="B", unit_scale=True, desc=desc)
    elif HAVE_TQDM:
        progress = tqdm(unit="B", unit_scale=True, desc=desc)
    else:
        progress = None
        if total:
            print(f"[download] {desc} ({total / 1024 / 1024:.1f} MB)", file=sys.stderr)

    with open(output_file, "wb") as f:
        for chunk in resp.iter_content(chunk_size=65536):
            if chunk:
                f.write(chunk)
                if progress:
                    progress.update(len(chunk))

    if progress:
        progress.close()

    if not os.path.getsize(output_file):
        raise RuntimeError("Downloaded file is empty")

    print(json.dumps({"file": os.path.abspath(output_file), "version": version}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)
