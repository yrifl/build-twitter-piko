# build-twitter-piko

Patch X/Twitter with [Piko](https://github.com/crimera/piko) + [Piko-Shim](https://gitlab.com/inotia00/x-shim).

Builds 4 variants in `output/`:
- `x-piko-<ver>.apk` / `x-piko-material-you-<ver>.apk`
- `twitter-piko-<ver>.apk` / `twitter-piko-material-you-<ver>.apk`

## Usage

```bash
bash scripts/patch.sh                # latest X version
bash scripts/patch.sh 11.99.0-release-1  # specific version
```

## CI/CD

Trigger **Build Piko X** from Actions tab, or runs every Sunday.
