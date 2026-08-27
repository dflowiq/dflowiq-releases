#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s --version HASH-EPOCHINMILLIS --release-notes PATH [--asset-directory PATH]\n' "$0" >&2
  exit 1
}

version=''
release_notes=''
asset_directory="$(dirname "$0")/../release-assets"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      version="${2:-}"
      shift 2
      ;;
    --release-notes)
      release_notes="${2:-}"
      shift 2
      ;;
    --asset-directory)
      asset_directory="${2:-}"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

asset_directory="$(cd "$asset_directory" && pwd)"
[[ "$version" =~ ^[0-9a-fA-F]{7,64}-[0-9]{13}$ ]] || { printf 'Version must use HASH-EPOCHINMILLIS format.\n' >&2; exit 1; }
command -v gh >/dev/null || { printf "GitHub CLI (gh) is required. Authenticate with 'gh auth login' first.\n" >&2; exit 1; }
[[ -f "$release_notes" ]] || { printf 'Release notes file was not found: %s\n' "$release_notes" >&2; exit 1; }

assets=(
  "$asset_directory/dflowiq-$version-macos-arm64.dmg"
  "$asset_directory/dflowiq-$version-windows-amd64.msi"
  "$asset_directory/dflowiq-$version-linux-amd64.deb"
  "$asset_directory/dflowiq-$version-linux-arm64.deb"
)

for asset in "${assets[@]}"; do
  [[ -f "$asset" ]] || { printf 'Required release asset was not found: %s\n' "$asset" >&2; exit 1; }
done

checksum_path="$asset_directory/SHA256SUMS"
(
  cd "$asset_directory"
  shasum -a 256 "${assets[@]##*/}" > "$checksum_path"
)

notes_path="$(mktemp "${TMPDIR:-/tmp}/dflowiq-release-notes-$version.XXXXXX")"
trap 'rm -f "$notes_path"' EXIT
{
  printf '# dFlowIQ %s\n\n' "$version"
  cat "$release_notes"
  printf '\n\n## Checksums\n\nSee the attached `SHA256SUMS` file.\n'
} > "$notes_path"

gh release create "$version" "${assets[@]}" "$checksum_path" --title "dFlowIQ $version" --notes-file "$notes_path"
