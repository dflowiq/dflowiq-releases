#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
commit_hash="abcdef1234567"
timestamp_macos="1700000000001"
timestamp_windows="1700000000500"
timestamp_linux="1700000000999"
temp_directory="$(mktemp -d "${TMPDIR:-/tmp}/dflowiq-publish-release-test.XXXXXX")"
trap 'rm -rf "$temp_directory"' EXIT

asset_directory="$temp_directory/release-assets"
release_directory="$asset_directory/$commit_hash"
mkdir -p "$release_directory/macos-arm64" "$release_directory/windows-arm64" "$release_directory/linux-amd64" "$temp_directory/bin" "$temp_directory/received"
printf 'macOS installer\n' > "$release_directory/macos-arm64/dflowiq-$commit_hash-$timestamp_macos-macos-arm64.dmg"
printf 'Windows ARM64 installer\n' > "$release_directory/windows-arm64/dflowiq-$commit_hash-$timestamp_windows-windows-arm64.msi"
printf 'Linux installer\n' > "$release_directory/linux-amd64/dflowiq-$commit_hash-$timestamp_linux-linux-amd64.deb"
printf 'Release notes\n' > "$temp_directory/notes.md"
cp "$script_directory/test-fixtures/mock-gh" "$temp_directory/bin/gh"

PATH="$temp_directory/bin:$PATH" GH_CAPTURE="$temp_directory/received" \
  "$script_directory/publish-release.sh" --commit-hash "$commit_hash" --release-notes "$temp_directory/notes.md" --asset-directory "$asset_directory" --latest

expected_manifest=$(printf '{"schemaVersion":2,"commit":"%s","platforms":{"macos-arm64":{"buildId":"%s-%s","buildTimestampMillis":%s},"windows-arm64":{"buildId":"%s-%s","buildTimestampMillis":%s},"linux-amd64":{"buildId":"%s-%s","buildTimestampMillis":%s}}}\n' "$commit_hash" "$commit_hash" "$timestamp_macos" "$timestamp_macos" "$commit_hash" "$timestamp_windows" "$timestamp_windows" "$commit_hash" "$timestamp_linux" "$timestamp_linux")
immutable_manifest="$temp_directory/received/$commit_hash/dflowiq-update-manifest.json"
latest_manifest="$temp_directory/received/latest/dflowiq-update-manifest.json"
[[ "$(< "$immutable_manifest")" == "${expected_manifest%$'\n'}" ]] || { printf 'Manifest does not match the schema-2 contract.\n' >&2; exit 1; }
cmp -s "$immutable_manifest" "$latest_manifest"
immutable_target_is_main=false
expect_target_value=false
while IFS= read -r argument; do
  if [[ "$expect_target_value" == true ]]; then
    if [[ "$argument" == "main" ]]; then
      immutable_target_is_main=true
    fi
    expect_target_value=false
  elif [[ "$argument" == --target ]]; then
    expect_target_value=true
  fi
done < "$temp_directory/received/$commit_hash/arguments"
[[ "$immutable_target_is_main" == true ]] || { printf 'Immutable release target is incorrect.\n' >&2; exit 1; }
for release in "$commit_hash" latest; do
  (cd "$temp_directory/received/$release" && shasum -a 256 -c SHA256SUMS)
done

interactive_commit_hash="1234567"
interactive_release_directory="$asset_directory/$interactive_commit_hash"
interactive_received_directory="$temp_directory/interactive-received"
mkdir -p "$interactive_release_directory/macos-arm64"
printf 'macOS installer\n' > "$interactive_release_directory/macos-arm64/dflowiq-$interactive_commit_hash-$timestamp_macos-macos-arm64.dmg"
printf 'Release notes\n' > "$interactive_release_directory/release-notes.md"

printf '%s\n\n\n%s\n' "$interactive_commit_hash" "$asset_directory" | PATH="$temp_directory/bin:$PATH" GH_CAPTURE="$interactive_received_directory" \
  "$script_directory/publish-release.sh"

[[ -f "$interactive_received_directory/$interactive_commit_hash/dflowiq-update-manifest.json" ]] || { printf 'Interactive publication did not create the immutable release.\n' >&2; exit 1; }
[[ ! -d "$interactive_received_directory/latest" ]] || { printf 'Interactive publication unexpectedly created a latest release.\n' >&2; exit 1; }
