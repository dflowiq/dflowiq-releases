#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--commit-hash HASH] [--release-notes PATH] [--asset-directory PATH] [--no-latest]\n' "$0" >&2
  exit 1
}

commit_hash=''
release_notes=''
asset_directory="$(dirname "$0")/../release-assets"
latest=true
interactive=false

[[ $# -eq 0 ]] && interactive=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit-hash)
      commit_hash="${2:-}"
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
    --latest)
      latest=true
      shift
      ;;
    --no-latest)
      latest=false
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [[ "$interactive" == true ]]; then
  read -r -p 'Commit hash: ' commit_hash
  read -r -p 'Release notes path (blank for release-notes.md in the asset directory): ' release_notes
  read -r -p 'Publish as latest? [Y/n]: ' latest_response
  [[ "$latest_response" =~ ^[Nn]([Oo])?$ ]] && latest=false
  read -r -p "Asset directory [$asset_directory]: " asset_directory_response
  [[ -n "$asset_directory_response" ]] && asset_directory="$asset_directory_response"
fi

asset_directory="$(cd "$asset_directory" && pwd)"
[[ "$commit_hash" =~ ^[0-9a-fA-F]{7,64}$ ]] || { printf 'Commit hash must contain 7 to 64 hexadecimal characters.\n' >&2; exit 1; }
command -v gh >/dev/null || { printf "GitHub CLI (gh) is required. Authenticate with 'gh auth login' first.\n" >&2; exit 1; }
[[ -n "$release_notes" ]] || release_notes="$asset_directory/$commit_hash/release-notes.md"
[[ -f "$release_notes" ]] || { printf 'Release notes file was not found: %s\n' "$release_notes" >&2; exit 1; }
release_asset_directory="$asset_directory/$commit_hash"
[[ -d "$release_asset_directory" ]] || { printf 'Release asset directory was not found: %s\n' "$release_asset_directory" >&2; exit 1; }

shopt -s nullglob
assets=()
builds=()
latest_asset_names=()
platform_entries=()
platforms=("macos-arm64:.dmg" "windows-amd64:.msi" "windows-arm64:.msi" "linux-amd64:.deb" "linux-arm64:.deb")
for platform in "${platforms[@]}"; do
  target="${platform%%:*}"
  extension="${platform#*:}"
  matches=("$release_asset_directory/$target/dflowiq-$commit_hash-"*"-$target$extension")
  [[ ${#matches[@]} -le 1 ]] || { printf 'Expected at most one %s release asset.\n' "$target" >&2; exit 1; }
  [[ ${#matches[@]} -eq 1 ]] || continue
  asset="${matches[0]}"
  filename="${asset##*/}"
  extension_pattern="${extension/./\\.}"
  [[ "$filename" =~ ^dflowiq-${commit_hash}-([0-9]{13})-${target}${extension_pattern}$ ]] || { printf 'Invalid %s release asset name: %s\n' "$target" "$filename" >&2; exit 1; }
  timestamp="${BASH_REMATCH[1]}"
  assets+=("$asset")
  builds+=("$target: $commit_hash-$timestamp")
  latest_asset_names+=("dflowiq-$target$extension")
  platform_entries+=("\"$target\":{\"buildId\":\"$commit_hash-$timestamp\",\"buildTimestampMillis\":$timestamp}")
done

[[ ${#assets[@]} -gt 0 ]] || { printf 'No release assets matching commit hash %s were found.\n' "$commit_hash" >&2; exit 1; }

manifest_path="$release_asset_directory/dflowiq-update-manifest.json"
{
  printf '{"schemaVersion":2,"commit":"%s","platforms":{' "$commit_hash"
  for index in "${!platform_entries[@]}"; do
    [[ "$index" -gt 0 ]] && printf ','
    printf '%s' "${platform_entries[$index]}"
  done
  printf '}}\n'
} > "$manifest_path"
assets+=("$manifest_path")
latest_asset_names+=("dflowiq-update-manifest.json")

checksum_path="$release_asset_directory/SHA256SUMS"
for asset in "${assets[@]}"; do
  read -r hash _ < <(shasum -a 256 "$asset")
  printf '%s  %s\n' "$hash" "${asset##*/}"
done > "$checksum_path"

notes_path="$(mktemp "${TMPDIR:-/tmp}/dflowiq-release-notes-$commit_hash.XXXXXX")"
latest_checksum_path="$(mktemp "${TMPDIR:-/tmp}/dflowiq-latest-checksums-$commit_hash.XXXXXX")"
latest_asset_directory="$(mktemp -d "${TMPDIR:-/tmp}/dflowiq-latest-assets-$commit_hash.XXXXXX")"
trap 'rm -f "$notes_path" "$latest_checksum_path"; rm -rf "$latest_asset_directory"' EXIT
{
  printf '# dFlowIQ %s\n\n' "$commit_hash"
  cat "$release_notes"
  printf '\n\n## Builds\n\n'
  for build in "${builds[@]}"; do printf -- '- `%s`\n' "$build"; done
  printf '\n## Checksums\n\nSee the attached `SHA256SUMS` file.\n'
} > "$notes_path"

release_arguments=(release create "$commit_hash" "${assets[@]}" "$checksum_path" --target main --title "dFlowIQ $commit_hash" --notes-file "$notes_path")
if gh release view "$commit_hash" >/dev/null 2>&1; then
  [[ "$latest" == true ]] || { printf 'Release already exists: %s\n' "$commit_hash" >&2; exit 1; }
else
  gh "${release_arguments[@]}"
fi

if [[ "$latest" == true ]]; then
  hash_tag_sha="$(gh api "repos/{owner}/{repo}/git/ref/tags/$commit_hash" --jq '.object.sha')"
  if gh release view latest >/dev/null 2>&1; then
    gh release delete latest --yes --cleanup-tag
  else
    gh api --method DELETE "repos/{owner}/{repo}/git/refs/tags/latest" >/dev/null 2>&1 || true
  fi
  latest_assets=()
  for index in "${!assets[@]}"; do
    latest_asset="$latest_asset_directory/${latest_asset_names[$index]}"
    cp "${assets[$index]}" "$latest_asset"
    latest_assets+=("$latest_asset")
    read -r hash _ < <(shasum -a 256 "$latest_asset")
    printf '%s  %s\n' "$hash" "${latest_asset_names[$index]}"
  done > "$latest_checksum_path"
  cp "$latest_checksum_path" "$latest_asset_directory/SHA256SUMS"
  gh release create latest "${latest_assets[@]}" "$latest_asset_directory/SHA256SUMS" --target "$hash_tag_sha" --title "dFlowIQ Latest" --notes-file "$notes_path" --latest
fi
