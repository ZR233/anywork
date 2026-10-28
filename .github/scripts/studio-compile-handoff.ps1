Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-StudioArtifactId {
    param([string] $Id)
    if ($Id -cnotmatch '^[1-9][0-9]*$') { throw "Missing or invalid producer artifact ID: $Id" }
}

function Assert-StudioSha256 {
    param([string] $Path, [string] $Expected)
    if ($Expected -cnotmatch '^[0-9a-f]{64}$') { throw 'Missing or malformed producer SHA-256' }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $Expected) { throw "SHA-256 mismatch for $Path" }
}

function Assert-StudioProductVersion {
    param([string] $Executable, [string] $Version)
    if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "Expected stable x.y.z version, got $Version"
    }
    $actual = (Get-Item -LiteralPath $Executable).VersionInfo.ProductVersion
    if ($actual -cne $Version) { throw "Executable product version $actual does not equal $Version" }
}

function New-StudioCompileCheckpoint {
    # build-gui owns runtime collection. Archive its entire output without another
    # file-selection rule, symbol pass, or self-reported source manifest.
    $bundle = Join-Path $env:GITHUB_WORKSPACE 'dist/anywork-release'
    $archive = Join-Path $env:RUNNER_TEMP 'bundle.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($bundle, $archive, [IO.Compression.CompressionLevel]::Fastest, $false)
    $tool = Join-Path $env:GITHUB_WORKSPACE 'target/xtask/debug/pl-xtask.exe'
    $workspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd([char[]]@('\', '/'))
    "bundleSha256=$((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant())" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8
    "toolSha256=$((Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToLowerInvariant())" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8
    "toolWorkspace=$workspace" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8
}

function Restore-StudioBundle {
    Assert-StudioArtifactId -Id $env:BUNDLE_ARTIFACT_ID
    $archive = Join-Path $env:RUNNER_TEMP 'studio-bundle/bundle.zip'
    Assert-StudioSha256 -Path $archive -Expected $env:BUNDLE_SHA256
    $bundle = Join-Path $env:RUNNER_TEMP 'studio-bundle-restored'
    Expand-Archive -LiteralPath $archive -DestinationPath $bundle
    "STUDIO_RELEASE_BUNDLE=$bundle" | Out-File $env:GITHUB_ENV -Append -Encoding utf8
}

function Restore-StudioReleaseTool {
    Assert-StudioArtifactId -Id $env:TOOL_ARTIFACT_ID
    $workspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd([char[]]@('\', '/'))
    if ([string]::IsNullOrWhiteSpace($env:TOOL_WORKSPACE) -or -not [string]::Equals($workspace, $env:TOOL_WORKSPACE, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Compile tool workspace identity does not match this checkout'
    }
    $tool = Join-Path $env:RUNNER_TEMP 'studio-tool/pl-xtask.exe'
    Assert-StudioSha256 -Path $tool -Expected $env:TOOL_SHA256
    "STUDIO_RELEASE_TOOL=$tool" | Out-File $env:GITHUB_ENV -Append -Encoding utf8
}

function Restore-StudioReleaseAssets {
    Assert-StudioArtifactId -Id $env:ASSET_ARTIFACT_ID
    $archive = Join-Path $env:RUNNER_TEMP 'studio-assets/assets.zip'
    Assert-StudioSha256 -Path $archive -Expected $env:ASSET_SHA256
    $destination = Join-Path $env:GITHUB_WORKSPACE "dist/studio-release/$env:RELEASE_VERSION"
    Expand-Archive -LiteralPath $archive -DestinationPath $destination
}
