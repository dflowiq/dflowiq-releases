# dFlowIQ Releases

Public, immutable release channel for the dFlowIQ desktop application. GitHub Releases in this repository provide the installers consumed by the product website and desktop updater.

## Why a separate repository

A dedicated public GitHub repository separates public downloads from application development and gives each version stable GitHub Release asset URLs. It is not a substitute for platform trust requirements:

- macOS installers must be Developer ID signed, notarized, and stapled.
- Windows installers must be Authenticode signed and timestamped.
- Linux packages should additionally be distributed through a signed APT repository for `apt` users.

Never replace files in an existing release. Withdraw a faulty release and publish a corrected release with a new identifier instead.

## Published artifacts

Every release includes the available native installers and `SHA256SUMS`:

- `dflowiq-<version>-macos-arm64.dmg`
- `dflowiq-<version>-windows-amd64.msi`
- `dflowiq-<version>-linux-amd64.deb`
- `dflowiq-<version>-linux-arm64.deb`

All required platform installers must be present before publication; partial releases are not supported.

## Release workflow

Build, sign, and verify installers before manually uploading them here with [`scripts/publish-release.ps1`](scripts/publish-release.ps1) from a GitHub-authenticated machine. The script validates the expected filenames, generates `SHA256SUMS`, and creates the immutable GitHub Release.

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
