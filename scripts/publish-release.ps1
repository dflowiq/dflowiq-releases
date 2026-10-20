param(
  [string]$CommitHash,
  [string]$ReleaseNotes,
  [string]$AssetDirectory = (Join-Path $PSScriptRoot "../release-assets"),
  [switch]$Latest
)

$ErrorActionPreference = "Stop"

if ($PSBoundParameters.Count -eq 0) {
  $CommitHash = Read-Host "Commit hash"
  $ReleaseNotes = Read-Host "Release notes path (blank for release-notes.md in the asset directory)"
  $latestResponse = Read-Host "Publish as latest? [y/N]"
  $Latest = $latestResponse -match '^[Yy]([Ee][Ss])?$'
  $assetDirectoryResponse = Read-Host "Asset directory [$AssetDirectory]"
  if (-not [string]::IsNullOrWhiteSpace($assetDirectoryResponse)) {
    $AssetDirectory = $assetDirectoryResponse
  }
}

if ($CommitHash -notmatch '^[0-9a-fA-F]{7,64}$') {
  throw "CommitHash must contain 7 to 64 hexadecimal characters."
}
$AssetDirectory = (Resolve-Path -LiteralPath $AssetDirectory).Path
if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
  $ReleaseNotes = Join-Path (Join-Path $AssetDirectory $CommitHash) "release-notes.md"
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) is required. Authenticate with 'gh auth login' first."
}
if (-not (Test-Path -Path $ReleaseNotes -PathType Leaf)) {
  throw "Release notes file was not found: $ReleaseNotes"
}

$releaseAssetDirectory = Join-Path $AssetDirectory $CommitHash
if (-not (Test-Path -Path $releaseAssetDirectory -PathType Container)) {
  throw "Release asset directory was not found: $releaseAssetDirectory"
}

$platforms = @(
  @{ Name = "macos-arm64"; Extension = ".dmg" },
  @{ Name = "windows-amd64"; Extension = ".msi" },
  @{ Name = "windows-arm64"; Extension = ".msi" },
  @{ Name = "linux-amd64"; Extension = ".deb" },
  @{ Name = "linux-arm64"; Extension = ".deb" }
)
$assets = @()
$builds = @()
$latestAssetNames = @()
$platformEntries = [ordered]@{}
foreach ($platform in $platforms) {
  $name = $platform.Name
  $directory = Join-Path $releaseAssetDirectory $name
  if (-not (Test-Path -Path $directory -PathType Container)) {
    continue
  }
  $matches = @(Get-ChildItem -Path $directory -Filter "dflowiq-$CommitHash-*-$name$($platform.Extension)" -File)
  if ($matches.Count -eq 0) {
    continue
  }
  if ($matches.Count -ne 1) {
    throw "Expected at most one $name release asset."
  }
  $asset = $matches[0]
  $filePattern = '^dflowiq-' + [regex]::Escape($CommitHash) + '-([0-9]{13})-' + [regex]::Escape($name) + [regex]::Escape($platform.Extension) + '$'
  $match = [regex]::Match($asset.Name, $filePattern)
  if (-not $match.Success) {
    throw "Invalid $name release asset name: $($asset.Name)"
  }
  $timestamp = $match.Groups[1].Value
  $assets += $asset
  $builds += "$name: $CommitHash-$timestamp"
  $latestAssetNames += "dflowiq-$name$($platform.Extension)"
  $platformEntries[$name] = [ordered]@{
    buildId = "$CommitHash-$timestamp"
    buildTimestampMillis = [Int64]$timestamp
  }
}
if ($assets.Count -eq 0) {
  throw "No release assets matching commit hash $CommitHash were found."
}

$manifestPath = Join-Path $releaseAssetDirectory "dflowiq-update-manifest.json"
[ordered]@{
  schemaVersion = 2
  commit = $CommitHash
  platforms = $platformEntries
} | ConvertTo-Json -Compress | Set-Content -LiteralPath $manifestPath -Encoding utf8
$assets += Get-Item -LiteralPath $manifestPath
$latestAssetNames += "dflowiq-update-manifest.json"

$checksumPath = Join-Path $releaseAssetDirectory "SHA256SUMS"
$assets | ForEach-Object {
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
  "$hash  $($_.Name)"
} | Set-Content -LiteralPath $checksumPath

$notesPath = Join-Path ([System.IO.Path]::GetTempPath()) "dflowiq-release-notes-$CommitHash.md"
$latestChecksumPath = Join-Path ([System.IO.Path]::GetTempPath()) "dflowiq-latest-checksums-$CommitHash.txt"
$latestAssetDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "dflowiq-latest-assets-$CommitHash"
@(
  "# dFlowIQ $CommitHash"
  ""
  (Get-Content -LiteralPath $ReleaseNotes -Raw).Trim()
  ""
  "## Builds"
  ""
  ($builds | ForEach-Object { "- ``$_``" })
  ""
  "## Checksums"
  ""
  "See the attached ``SHA256SUMS`` file."
) | Set-Content -LiteralPath $notesPath

try {
  $releaseArguments = @("release", "create", $CommitHash) + $assets.FullName + $checksumPath + @("--target", $CommitHash, "--title", "dFlowIQ $CommitHash", "--notes-file", $notesPath)
  & gh release view $CommitHash 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    if (-not $Latest) { throw "Release already exists: $CommitHash" }
  } else {
    & gh @releaseArguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub Release creation failed." }
  }
  if ($Latest) {
    $hashTagSha = [string](& gh api "repos/{owner}/{repo}/git/ref/tags/$CommitHash" --jq ".object.sha")
    if ($LASTEXITCODE -ne 0) { throw "Could not resolve Git tag $CommitHash." }
    & gh release view latest 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
      & gh release delete latest --yes --cleanup-tag
      if ($LASTEXITCODE -ne 0) { throw "Could not replace the existing latest release." }
    } else {
      & gh api --method DELETE "repos/{owner}/{repo}/git/refs/tags/latest" 2>$null | Out-Null
    }
    New-Item -ItemType Directory -Force -Path $latestAssetDirectory | Out-Null
    $latestAssets = @()
    for ($index = 0; $index -lt $assets.Count; $index++) {
      $latestAsset = Join-Path $latestAssetDirectory $latestAssetNames[$index]
      Copy-Item -LiteralPath $assets[$index].FullName -Destination $latestAsset
      $latestAssets += Get-Item $latestAsset
    }
    $latestAssets | ForEach-Object {
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
      "$hash  $($_.Name)"
    } | Set-Content -LiteralPath $latestChecksumPath
    Copy-Item -LiteralPath $latestChecksumPath -Destination (Join-Path $latestAssetDirectory "SHA256SUMS")
    & gh release create latest $latestAssets.FullName (Join-Path $latestAssetDirectory "SHA256SUMS") --target $hashTagSha --title "dFlowIQ Latest" --notes-file $notesPath --latest
    if ($LASTEXITCODE -ne 0) { throw "Could not create the latest release." }
  }
} finally {
  Remove-Item -LiteralPath $notesPath -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $latestChecksumPath -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $latestAssetDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
