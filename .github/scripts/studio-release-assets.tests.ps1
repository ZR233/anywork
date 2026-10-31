$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'studio-release-assets.ps1')

function Assert-Throws {
    param([scriptblock] $Action, [string] $Pattern)
    try {
        & $Action | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected failure matching $Pattern"
}

# Synthetic payloads exercise reconciliation, not the installer/DEB format.
$root = Join-Path ([IO.Path]::GetTempPath()) ("studio-asset-tests-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $version = '1.2.3'
    $names = @(Get-StudioReleaseAssetNames -Version $version)
    foreach ($name in $names) {
        [IO.File]::WriteAllText((Join-Path $root $name), "payload:$name")
    }
    $debName = "anywork-$version-linux-x86_64.deb"
    $debPath = Join-Path $root $debName
    $digest = (Get-FileHash -LiteralPath $debPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sidecar = Join-Path $root "$debName.sha256"
    [IO.File]::WriteAllText($sidecar, "$digest  $debName`n")
    Assert-StudioDebianChecksum -Version $version -AssetDirectory $root

    $assets = @(
        foreach ($name in $names) {
            $file = Get-Item -LiteralPath (Join-Path $root $name)
            [pscustomobject]@{
                name = $name
                state = 'uploaded'
                size = $file.Length
                digest = "sha256:$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
            }
        }
    )
    $release = [pscustomobject]@{ draft = $true; assets = @() }
    $plan = Get-StudioReleaseAssetPlan -Release $release -Version $version -AssetDirectory $root
    if ($plan.Complete -or $plan.MissingNames.Count -ne $names.Count) {
        throw 'Empty draft did not identify all missing platform assets'
    }
    $release.assets = @($assets | Where-Object name -ne $debName)
    $plan = Get-StudioReleaseAssetPlan -Release $release -Version $version -AssetDirectory $root
    if ($plan.MissingNames.Count -ne 1 -or $plan.MissingNames[0] -cne $debName) {
        throw 'Partial draft did not identify the missing DEB'
    }
    $release.assets = $assets
    $release.draft = $false
    if (-not (Get-StudioReleaseAssetPlan -Release $release -Version $version -AssetDirectory $root).Complete) {
        throw 'Complete published Release was not accepted'
    }
    $assets[0].digest = 'sha256:' + ('0' * 64)
    Assert-Throws { Get-StudioReleaseAssetPlan -Release $release -Version $version -AssetDirectory $root } 'digest differs'
    $assets[0].digest = "sha256:$((Get-FileHash -LiteralPath (Join-Path $root $assets[0].name) -Algorithm SHA256).Hash.ToLowerInvariant())"

    $release.assets = @($assets | Where-Object name -ne $debName)
    Assert-Throws { Get-StudioReleaseAssetPlan -Release $release -Version $version -AssetDirectory $root } 'missing assets'
    $release.draft = $true
    $release.assets = @($assets) + @($assets[0])
    Assert-Throws { Get-StudioReleaseAssetPlan -Release $release -Version $version -AssetDirectory $root } 'duplicate'
    $release.assets = @([pscustomobject]@{ name = 'foreign.bin'; state = 'uploaded'; size = 1; digest = 'sha256:' + ('0' * 64) })
    Assert-Throws { Get-StudioReleaseAssetPlan -Release $release -Version $version -AssetDirectory $root } 'unknown'
    $release.assets[0].name = $debName.ToUpperInvariant()
    Assert-Throws { Get-StudioReleaseAssetPlan -Release $release -Version $version -AssetDirectory $root } 'unknown'

    # Equal digest text with another filename must not validate this package.
    [IO.File]::WriteAllText($sidecar, "$digest  other.deb`n")
    Assert-Throws { Assert-StudioDebianChecksum -Version $version -AssetDirectory $root } 'checksum'
    [IO.File]::WriteAllText($sidecar, "$digest  $debName`n")
    [IO.File]::AppendAllText($debPath, 'changed')
    Assert-Throws { Assert-StudioDebianChecksum -Version $version -AssetDirectory $root } 'checksum'
    Write-Host 'Release asset reconciliation and DEB checksum tests passed'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
