#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
commit_hash="abcdef1234567"
timestamp_macos="1700000000001"
timestamp_linux="1700000000999"
temp_directory="$(mktemp -d "${TMPDIR:-/tmp}/dflowiq-publish-release-test.XXXXXX")"
trap 'rm -rf "$temp_directory"' EXIT

asset_directory="$temp_directory/release-assets"
release_directory="$asset_directory/$commit_hash"
mkdir -p "$release_directory/macos-arm64" "$release_directory/linux-amd64" "$temp_directory/bin" "$temp_directory/received"
printf 'macOS installer\n' > "$release_directory/macos-arm64/dflowiq-$commit_hash-$timestamp_macos-macos-arm64.dmg"
printf 'Linux installer\n' > "$release_directory/linux-amd64/dflowiq-$commit_hash-$timestamp_linux-linux-amd64.deb"
printf 'Release notes\n' > "$temp_directory/notes.md"
cp "$script_directory/test-fixtures/mock-gh" "$temp_directory/bin/gh"

PATH="$temp_directory/bin:$PATH" GH_CAPTURE="$temp_directory/received" \
  "$script_directory/publish-release.sh" --commit-hash "$commit_hash" --release-notes "$temp_directory/notes.md" --asset-directory "$asset_directory" --latest

expected_manifest=$(printf '{"schemaVersion":2,"commit":"%s","platforms":{"macos-arm64":{"buildId":"%s-%s","buildTimestampMillis":%s},"linux-amd64":{"buildId":"%s-%s","buildTimestampMillis":%s}}}\n' "$commit_hash" "$commit_hash" "$timestamp_macos" "$timestamp_macos" "$commit_hash" "$timestamp_linux" "$timestamp_linux")
immutable_manifest="$temp_directory/received/$commit_hash/dflowiq-update-manifest.json"
latest_manifest="$temp_directory/received/latest/dflowiq-update-manifest.json"
[[ "$(< "$immutable_manifest")" == "${expected_manifest%$'\n'}" ]] || { printf 'Manifest does not match the schema-2 contract.\n' >&2; exit 1; }
cmp -s "$immutable_manifest" "$latest_manifest"
grep -Fqx "$(shasum -a 256 "$immutable_manifest" | cut -d ' ' -f 1)  dflowiq-update-manifest.json" "$temp_directory/received/$commit_hash/SHA256SUMS"
grep -Fqx "$(shasum -a 256 "$latest_manifest" | cut -d ' ' -f 1)  dflowiq-update-manifest.json" "$temp_directory/received/latest/SHA256SUMS"
