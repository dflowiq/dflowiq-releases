$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $PSCommandPath
$commitHash = "abcdef1234567"
$timestampMacos = "1700000000001"
$timestampLinux = "1700000000999"
$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("dflowiq-publish-release-test-" + [Guid]::NewGuid())
$assetDirectory = Join-Path $tempDirectory "release-assets"
$releaseDirectory = Join-Path $assetDirectory $commitHash
$receivedDirectory = Join-Path $tempDirectory "received"

function gh {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

  if ($Arguments[0] -eq "release" -and $Arguments[1] -eq "view") {
    $global:LASTEXITCODE = 1
    return
  }
  if ($Arguments[0] -eq "api" -and $Arguments[1] -like "repos/{owner}/{repo}/git/ref/tags/*") {
    $global:LASTEXITCODE = 0
    "tag-sha"
    return
  }
  if ($Arguments[0] -eq "api" -and $Arguments[1] -eq "--method") {
    $global:LASTEXITCODE = 0
    return
  }
  if ($Arguments[0] -eq "release" -and $Arguments[1] -eq "create") {
    $destination = Join-Path $receivedDirectory $Arguments[2]
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    foreach ($argument in $Arguments[3..($Arguments.Count - 1)]) {
      if ($argument.StartsWith("--")) { break }
      Copy-Item -LiteralPath $argument -Destination $destination
    }
    $global:LASTEXITCODE = 0
    return
  }
  throw "Unexpected gh command: $($Arguments -join ' ')"
}

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $releaseDirectory "macos-arm64"), (Join-Path $releaseDirectory "linux-amd64") | Out-Null
  Set-Content -LiteralPath (Join-Path $releaseDirectory "macos-arm64/dflowiq-$commitHash-$timestampMacos-macos-arm64.dmg") -Value "macOS installer"
  Set-Content -LiteralPath (Join-Path $releaseDirectory "linux-amd64/dflowiq-$commitHash-$timestampLinux-linux-amd64.deb") -Value "Linux installer"
  $notesPath = Join-Path $tempDirectory "notes.md"
  Set-Content -LiteralPath $notesPath -Value "Release notes"

  & (Join-Path $scriptDirectory "publish-release.ps1") -CommitHash $commitHash -ReleaseNotes $notesPath -AssetDirectory $assetDirectory -Latest

  $immutableManifest = Join-Path $receivedDirectory "$commitHash/dflowiq-update-manifest.json"
  $latestManifest = Join-Path $receivedDirectory "latest/dflowiq-update-manifest.json"
  $manifest = Get-Content -LiteralPath $immutableManifest -Raw | ConvertFrom-Json
  if ($manifest.schemaVersion -ne 2 -or $manifest.commit -ne $commitHash) { throw "Manifest schema or commit is incorrect." }
  foreach ($platform in @(
    @{ Name = "macos-arm64"; Timestamp = [Int64]$timestampMacos },
    @{ Name = "linux-amd64"; Timestamp = [Int64]$timestampLinux }
  )) {
    $entry = $manifest.platforms.($platform.Name)
    if ($entry.buildId -ne "$commitHash-$($platform.Timestamp)" -or $entry.buildTimestampMillis -ne $platform.Timestamp) { throw "Manifest entry for $($platform.Name) is incorrect." }
    if ($null -ne $entry.PSObject.Properties["timestamp"]) { throw "Manifest entry for $($platform.Name) contains obsolete timestamp." }
  }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $immutableManifest).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $latestManifest).Hash) { throw "Immutable and latest manifests differ." }
  foreach ($release in @($commitHash, "latest")) {
    $manifestPath = Join-Path $receivedDirectory "$release/dflowiq-update-manifest.json"
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant()
    $checksum = "$hash  dflowiq-update-manifest.json"
    if (-not (Select-String -LiteralPath (Join-Path $receivedDirectory "$release/SHA256SUMS") -SimpleMatch $checksum -Quiet)) { throw "Manifest checksum missing from $release release." }
  }
} finally {
  Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
