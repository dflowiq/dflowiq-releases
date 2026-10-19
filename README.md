# dFlowIQ Releases

Public, immutable release channel for the dFlowIQ desktop application. GitHub Releases in this repository provide the installers consumed by the product website and desktop updater.

## Why a separate repository

A dedicated public GitHub repository separates public downloads from application development and gives each version stable GitHub Release asset URLs. It is not a substitute for platform trust requirements:

- macOS installers must be Developer ID signed, notarized, and stapled.
- Windows installers must be Authenticode signed and timestamped.
- Linux packages should additionally be distributed through a signed APT repository for `apt` users.

Never replace files in a hash-tagged release. Withdraw a faulty hash release and publish a corrected release with a new identifier. The separate `latest` release is intentionally replaced when a new latest release is published.

## Published artifacts

Each release is identified by its commit hash and includes any available native installers, `dflowiq-update-manifest.json`, and `SHA256SUMS`:

- `<hash>/macos-arm64/dflowiq-<hash>-<epochInMillis>-macos-arm64.dmg`
- `<hash>/windows-amd64/dflowiq-<hash>-<epochInMillis>-windows-amd64.msi`
- `<hash>/linux-amd64/dflowiq-<hash>-<epochInMillis>-linux-amd64.deb`
- `<hash>/linux-arm64/dflowiq-<hash>-<epochInMillis>-linux-arm64.deb`

Place each release's assets in `release-assets/<hash>/` with matching platform subdirectories. Each platform may have a different epoch timestamp. Missing platforms are omitted from the release.

With `-Latest` or `--latest`, the scripts also replace a separate `latest` release containing stable asset names such as `dflowiq-macos-arm64.dmg`. This is the versionless download channel for clients.

`dflowiq-update-manifest.json` has schema version `2` and identifies the release commit. Its `platforms` object is keyed by installer target; every available target has a `buildId` and a numeric `buildTimestampMillis`. The timestamp is the platform's installer epoch and may differ between platforms. The publishing scripts generate the manifest once and upload those exact bytes to the immutable hash-tagged release and, when requested, the `latest` release. Each release generates its own `SHA256SUMS`: the immutable release names hash-and-timestamp installers, while `latest` names its stable renamed installers. In both releases, the manifest checksum names `dflowiq-update-manifest.json`.

```json
{
  "schemaVersion": 2,
  "commit": "2419331",
  "platforms": {
    "macos-arm64": {
      "buildId": "2419331-1787863299655",
      "buildTimestampMillis": 1787863299655
    },
    "linux-arm64": {
      "buildId": "2419331-1787863370943",
      "buildTimestampMillis": 1787863370943
    }
  }
}
```

```text
release-assets/
  2419331/
    macos-arm64/dflowiq-2419331-1787863299655-macos-arm64.dmg
    linux-arm64/dflowiq-2419331-1787863370943-linux-arm64.deb
```

## Release workflow

Build, sign, and verify installers before manually uploading them here with [`scripts/publish-release.ps1`](scripts/publish-release.ps1) from a GitHub-authenticated machine. The script validates the expected filenames, generates `dflowiq-update-manifest.json` and `SHA256SUMS`, and creates the immutable GitHub Release.

Configure the repository as private until the signing process, public downloads, and release-owner review are ready. The publishing user needs permission to create releases in this repository.

Detailed prerequisites and manual publishing steps are in [docs/releasing.md](docs/releasing.md). The version-specific notes required for every release are in [docs/release-notes-template.md](docs/release-notes-template.md).

## Local repository setup

Create the remote repository and push this project:

```bash
git branch -M main
git remote add origin https://github.com/dflowiq/dflowiq-releases.git
git add .
git commit -m "Add desktop release pipeline"
git push -u origin main
```

The GitHub CLI is not installed in this workspace, so remote repository creation and publication must be completed from a GitHub-authenticated environment.
