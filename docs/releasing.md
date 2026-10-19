# Release Runbook

## One-time configuration

1. Create the GitHub repository as `dflowiq/dflowiq-releases`.
2. Grant the release managers permission to create releases and upload assets in this repository.
3. Install the GitHub CLI on the publishing machine and authenticate it with `gh auth login`.
4. Configure macOS and Windows signing before allowing a production release. Do not ship unsigned installers.
5. Configure the website values in dflowiq-ui: `NEXT_PUBLIC_RELEASES_URL`, and optionally the direct platform URLs described below.

## Versioning

GitHub Release tags use the commit hash, for example `a1b2c3d`. Each platform installer uses `HASH-EPOCHINMILLIS`, where the hash is 7 to 64 hexadecimal characters and the epoch timestamp is 13 digits.

All available installer hashes must match the GitHub Release tag. Platform epoch timestamps may differ.

## Update manifest

Every hash-tagged release includes `dflowiq-update-manifest.json` with this schema:

```json
{
  "schemaVersion": 2,
  "commit": "a1b2c3d",
  "platforms": {
    "macos-arm64": {
      "buildId": "a1b2c3d-1735689600000",
      "buildTimestampMillis": 1735689600000
    },
    "windows-amd64": {
      "buildId": "a1b2c3d-1735689700000",
      "buildTimestampMillis": 1735689700000
    }
  }
}
```

`schemaVersion` is always the numeric value `2`, and `commit` is the GitHub Release commit hash. `platforms` contains one entry for each available installer, keyed by target (`macos-arm64`, `windows-amd64`, `linux-amd64`, or `linux-arm64`). Each entry has a `buildId` of `<commit>-<epochInMillis>` and a numeric `buildTimestampMillis` matching that target's installer filename. Entries are omitted for unavailable platforms, and platform timestamps may differ.

The publishing scripts generate this manifest once from the selected installers and upload it unchanged with its `SHA256SUMS` checksum entry to the immutable hash-tagged release and, with `-Latest` or `--latest`, the mutable `latest` release.

## Manual publication

After building and verifying installers, place each available file in its platform directory under `release-assets/<hash>/`. Create release notes from [release-notes-template.md](release-notes-template.md), then run:

```powershell
./scripts/publish-release.ps1 -CommitHash a1b2c3d -ReleaseNotes ./docs/release-notes/a1b2c3d.md -Latest
```

```bash
./scripts/publish-release.sh --commit-hash a1b2c3d --release-notes ./docs/release-notes/a1b2c3d.md --latest
```

The scripts select at most one valid installer from each platform directory, skip missing platforms, and create `SHA256SUMS` from the exact uploaded files, including `dflowiq-update-manifest.json`. Add `-Latest` or `--latest` to create or replace a separate `latest` release and tag. It contains the same installers under stable names, plus the unchanged manifest, so clients can download them without a hash or epoch timestamp. Hash-tagged releases remain unchanged. `release-assets/` is intentionally ignored by Git; do not commit installers to repository history.

The `latest` release and its tag must remain deletable. Do not enable a repository-wide immutable-release policy if this mutable download channel is required.

## Pre-release checklist

1. Prepare user-facing release notes using [release-notes-template.md](release-notes-template.md).
2. Run application checks and platform smoke tests.
3. Build, sign, and verify the macOS, Windows, and Linux installers on trusted machines.
4. Notarize and staple the macOS DMG. Verify with `spctl`.
5. Verify the Windows Authenticode signature, including a timestamp.
6. Test clean install, upgrade, launch, and removal for every supported target.
7. Make the completed installers and release notes available on the publishing machine.

## Publish and verify

Run the publishing script after every available installer is verified. It uploads `dflowiq-update-manifest.json` and `SHA256SUMS` generated from the exact assets uploaded to GitHub.

After publication:

1. Download each asset from the GitHub Release and compare it with `SHA256SUMS`.
2. Install and launch each platform package from the public URL.
3. Confirm the product website's **Release history and checksums** link opens this repository.
4. Confirm the desktop updater can read `https://api.github.com/repos/dflowiq/dflowiq-releases/releases/latest`.
5. Publish any Homebrew, winget, and signed APT metadata only after the GitHub asset checksum is final.

## Direct website asset URLs

GitHub provides immutable asset URLs for a given tag:

```text
https://github.com/dflowiq/dflowiq-releases/releases/download/a1b2c3d/dflowiq-a1b2c3d-1735689600000-macos-arm64.dmg
https://github.com/dflowiq/dflowiq-releases/releases/download/a1b2c3d/dflowiq-a1b2c3d-1735689700000-windows-amd64.msi
https://github.com/dflowiq/dflowiq-releases/releases/download/a1b2c3d/dflowiq-a1b2c3d-1735689800000-linux-amd64.deb
https://github.com/dflowiq/dflowiq-releases/releases/download/a1b2c3d/dflowiq-a1b2c3d-1735689900000-linux-arm64.deb
```

Set direct URLs only after the relevant asset has been released. Otherwise, point users to the GitHub Releases page.

## Latest asset URLs

When published with `-Latest` or `--latest`, clients can use these mutable URLs:

```text
https://github.com/dflowiq/dflowiq-releases/releases/download/latest/dflowiq-macos-arm64.dmg
https://github.com/dflowiq/dflowiq-releases/releases/download/latest/dflowiq-windows-amd64.msi
https://github.com/dflowiq/dflowiq-releases/releases/download/latest/dflowiq-linux-amd64.deb
https://github.com/dflowiq/dflowiq-releases/releases/download/latest/dflowiq-linux-arm64.deb
```
