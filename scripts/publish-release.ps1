param(
  [Parameter(Mandatory = $true)]
  [string]$Version,
  [Parameter(Mandatory = $true)]
  [string]$ReleaseNotes,
  [string]$AssetDirectory = (Join-Path $PSScriptRoot "../release-assets")
)

$ErrorActionPreference = "Stop"

if ($Version -notmatch '^[0-9a-fA-F]{7,64}-[0-9]{13}$') {
  throw "Version must use HASH-EPOCHINMILLIS format."
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) is required. Authenticate with 'gh auth login' first."
}
if (-not (Test-Path -Path $ReleaseNotes -PathType Leaf)) {
  throw "Release notes file was not found: $ReleaseNotes"
}

$requiredAssets = @(
  "dflowiq-$Version-macos-arm64.dmg",
  "dflowiq-$Version-windows-amd64.msi",
  "dflowiq-$Version-linux-amd64.deb",
  "dflowiq-$Version-linux-arm64.deb"
)
$assets = foreach ($asset in $requiredAssets) {
  $path = Join-Path $AssetDirectory $asset
  if (-not (Test-Path -Path $path -PathType Leaf)) {
    throw "Required release asset was not found: $path"
  }
  Get-Item $path
}

$checksumPath = Join-Path $AssetDirectory "SHA256SUMS"
$assets | ForEach-Object {
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
  "$hash  $($_.Name)"
} | Set-Content -LiteralPath $checksumPath

$notesPath = Join-Path ([System.IO.Path]::GetTempPath()) "dflowiq-release-notes-$Version.md"
@(
  "# dFlowIQ $Version"
  ""
  (Get-Content -LiteralPath $ReleaseNotes -Raw).Trim()
  ""
  "## Checksums"
  ""
  "See the attached ``SHA256SUMS`` file."
) | Set-Content -LiteralPath $notesPath

try {
  & gh release create $Version $assets.FullName $checksumPath --title "dFlowIQ $Version" --notes-file $notesPath
  if ($LASTEXITCODE -ne 0) { throw "GitHub Release creation failed." }
} finally {
  Remove-Item -LiteralPath $notesPath -ErrorAction SilentlyContinue
}
