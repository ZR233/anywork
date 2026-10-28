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

function Assert-StudioSourceIdentity {
    if ($env:GITHUB_RUN_ID -cnotmatch '^[1-9][0-9]*$' -or $env:RELEASE_SHA -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Missing or malformed run / source commit identity'
    }
    if ($env:RELEASE_ID -cnotmatch '^[1-9][0-9]*$' -and $env:RELEASE_ID -cne "rc-$env:GITHUB_RUN_ID") {
        throw 'Missing or malformed release identity'
    }
}

function Assert-StudioProductVersion {
    param([string] $Executable, [string] $Version)
    if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "Expected stable x.y.z version, got $Version"
    }
    $actual = (Get-Item -LiteralPath $Executable).VersionInfo.ProductVersion
    if ($actual -cne $Version) { throw "Executable product version $actual does not equal $Version" }
}

function Get-StudioPdbIdentity {
    param([string] $Pdb)
    $stream = [IO.File]::OpenRead($Pdb)
    try {
        $header = [byte[]]::new(56)
        $stream.ReadExactly($header, 0, $header.Length)
        if ([Text.Encoding]::ASCII.GetString($header, 0, 24) -cne 'Microsoft C/C++ MSF 7.00') { throw "Not an MSF 7 PDB: $Pdb" }
        $blockSize = [BitConverter]::ToUInt32($header, 32)
        $blockCount = [BitConverter]::ToUInt32($header, 40)
        $directorySize = [BitConverter]::ToUInt32($header, 44)
        $blockMap = [BitConverter]::ToUInt32($header, 52)
        if ($blockSize -lt 512 -or $blockSize -gt 65536 -or ($blockSize -band ($blockSize - 1)) -ne 0 -or
            [long]$blockCount * $blockSize -ne $stream.Length -or $blockMap -ge $blockCount -or
            $directorySize -lt 12 -or $directorySize -gt $stream.Length) { throw "Invalid MSF directory: $Pdb" }
        $directoryBlocks = [int][Math]::Ceiling($directorySize / [double]$blockSize)
        if ($directoryBlocks * 4 -gt $blockSize) { throw "MSF directory block map is too large: $Pdb" }
        $map = [byte[]]::new($directoryBlocks * 4)
        $stream.Position = [long]$blockMap * $blockSize
        $stream.ReadExactly($map, 0, $map.Length)
        $directory = [byte[]]::new($directoryBlocks * $blockSize)
        for ($i = 0; $i -lt $directoryBlocks; $i++) {
            $block = [BitConverter]::ToUInt32($map, $i * 4)
            if ($block -ge $blockCount) { throw "Invalid MSF directory block: $Pdb" }
            $stream.Position = [long]$block * $blockSize
            $stream.ReadExactly($directory, $i * $blockSize, $blockSize)
        }
        $streamCount = [BitConverter]::ToUInt32($directory, 0)
        if ($streamCount -lt 2 -or 4 + $streamCount * 4 -gt $directorySize) { throw "PDB info stream missing: $Pdb" }
        $firstSize = [BitConverter]::ToUInt32($directory, 4)
        $infoSize = [BitConverter]::ToUInt32($directory, 8)
        $firstBlocks = if ($firstSize -eq [uint32]::MaxValue) { 0 } else { [int][Math]::Ceiling($firstSize / [double]$blockSize) }
        $infoBlockOffset = 4 + $streamCount * 4 + $firstBlocks * 4
        if ($infoSize -lt 28 -or $infoSize -eq [uint32]::MaxValue -or $infoBlockOffset + 4 -gt $directorySize) { throw "Invalid PDB info stream: $Pdb" }
        $infoBlock = [BitConverter]::ToUInt32($directory, $infoBlockOffset)
        if ($infoBlock -ge $blockCount) { throw "Invalid PDB info block: $Pdb" }
        $info = [byte[]]::new(28)
        $stream.Position = [long]$infoBlock * $blockSize
        $stream.ReadExactly($info, 0, $info.Length)
        return [pscustomobject]@{
            Age = [BitConverter]::ToUInt32($info, 8)
            Guid = [Convert]::ToHexString($info, 12, 16)
        }
    } finally { $stream.Dispose() }
}

function Assert-StudioMatchingPdb {
    param([string] $Executable, [string] $Pdb)
    # MSVC/Rust use MSF 7 PDBs. CodeView RSDS records bind PE -> PDB GUID + age.
    $pe = [IO.File]::ReadAllBytes($Executable)
    $identity = Get-StudioPdbIdentity -Pdb $Pdb
    $peOffset = [BitConverter]::ToInt32($pe, 0x3c)
    if ([BitConverter]::ToUInt32($pe, $peOffset) -ne 0x4550) { throw "Not a PE executable: $Executable" }
    $sections = [BitConverter]::ToUInt16($pe, $peOffset + 6)
    $optionalSize = [BitConverter]::ToUInt16($pe, $peOffset + 20)
    $optional = $peOffset + 24
    if ([BitConverter]::ToUInt16($pe, $optional) -ne 0x20b) { throw "Expected x64 PE: $Executable" }
    $debugRva = [BitConverter]::ToUInt32($pe, $optional + 112 + 6 * 8)
    $debugSize = [BitConverter]::ToUInt32($pe, $optional + 112 + 6 * 8 + 4)
    $debugOffset = $null
    for ($i = 0; $i -lt $sections; $i++) {
        $section = $optional + $optionalSize + 40 * $i
        $rva = [BitConverter]::ToUInt32($pe, $section + 12)
        $size = [Math]::Max([BitConverter]::ToUInt32($pe, $section + 8), [BitConverter]::ToUInt32($pe, $section + 16))
        if ($debugRva -ge $rva -and $debugRva -lt $rva + $size) {
            $debugOffset = [BitConverter]::ToUInt32($pe, $section + 20) + $debugRva - $rva
            break
        }
    }
    if ($null -eq $debugOffset) { throw "No PE debug directory: $Executable" }
    for ($entry = $debugOffset; $entry + 28 -le $debugOffset + $debugSize; $entry += 28) {
        if ([BitConverter]::ToUInt32($pe, $entry + 12) -ne 2) { continue }
        $record = [BitConverter]::ToUInt32($pe, $entry + 24)
        if ([Text.Encoding]::ASCII.GetString($pe, $record, 4) -cne 'RSDS') { continue }
        $guid = [Convert]::ToHexString($pe, $record + 4, 16)
        $age = [BitConverter]::ToUInt32($pe, $record + 20)
        if ($identity.Guid -ceq $guid -and $identity.Age -eq $age) { return }
        throw "PDB does not match PE CodeView GUID $guid and age $age : $Pdb"
    }
    throw "No RSDS CodeView identity: $Executable"
}

function New-StudioCompileArchive {
    Assert-StudioSourceIdentity
    $workspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd([char[]]@('\', '/'))
    $bundle = Join-Path $workspace 'dist/anywork-release'
    Assert-StudioProductVersion -Executable (Join-Path $bundle 'anywork.exe') -Version $env:RELEASE_VERSION
    $tool = Join-Path $workspace 'target/xtask/debug/pl-xtask.exe'
    $toolHash = (Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash.ToLowerInvariant()
    $root = Join-Path $env:RUNNER_TEMP 'studio-compile-input'
    New-Item -ItemType Directory -Path $root | Out-Null
    Copy-Item -LiteralPath $bundle -Destination (Join-Path $root 'bundle') -Recurse
    Copy-Item -LiteralPath $tool -Destination (Join-Path $root 'pl-xtask.exe')
    $symbols = Join-Path $root 'symbols'
    New-Item -ItemType Directory -Path $symbols | Out-Null
    $roots = @(
        $bundle,
        (Join-Path $workspace 'target/release'),
        (Join-Path $workspace 'code/anywork/build/windows/x64/rust-target/release')
    )
    $matched = @{}
    for ($i = 0; $i -lt $roots.Count; $i++) {
        if (-not (Test-Path -LiteralPath $roots[$i] -PathType Container)) { continue }
        foreach ($pdb in Get-ChildItem -LiteralPath $roots[$i] -Filter *.pdb -File -Recurse) {
            # Keep all real PDBs, preserving relative paths (no basename collisions).
            $header = [IO.File]::OpenRead($pdb.FullName)
            try {
                $magic = [byte[]]::new(24)
                if ($header.Read($magic, 0, 24) -ne 24 -or [Text.Encoding]::ASCII.GetString($magic) -cne 'Microsoft C/C++ MSF 7.00') { continue }
            } finally { $header.Dispose() }
            $relative = [IO.Path]::GetRelativePath($roots[$i], $pdb.FullName)
            $destination = Join-Path $symbols "source-$i/$relative"
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $pdb.FullName -Destination $destination
            if ($pdb.Name -cin @('anywork.pdb', 'pl_studio_bridge.pdb')) {
                $binaryName = if ($pdb.Name -ceq 'anywork.pdb') { 'anywork.exe' } else { 'pl_studio_bridge.dll' }
                Assert-StudioMatchingPdb -Executable (Join-Path $bundle $binaryName) -Pdb $pdb.FullName
                $matched[$pdb.Name] = $true
            }
        }
    }
    foreach ($required in @('anywork.pdb', 'pl_studio_bridge.pdb')) {
        if (-not $matched.ContainsKey($required)) { throw "Missing matching $required" }
    }
    $identity = @{
        runId = $env:GITHUB_RUN_ID
        commit = $env:RELEASE_SHA
        releaseId = $env:RELEASE_ID
        version = $env:RELEASE_VERSION
        workspace = $workspace
        protocolVersion = 2
    }
    $identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'identity.json')
    $identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $symbols 'version-map.json')
    $archive = Join-Path $env:RUNNER_TEMP 'compile.zip'
    Compress-Archive -Path (Join-Path $root '*') -DestinationPath $archive
    $symbolArchive = Join-Path $env:RUNNER_TEMP 'symbols.zip'
    Compress-Archive -Path (Join-Path $symbols '*') -DestinationPath $symbolArchive
    "archiveSha256=$((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant())" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8
    "toolSha256=$toolHash" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8
    "toolWorkspace=$workspace" | Out-File $env:GITHUB_OUTPUT -Append -Encoding utf8
}

function Restore-StudioCompileArchive {
    # All expected identities come from producer outputs / immutable resolve, never
    # from the downloaded archive alone. Verify the zip before expanding any bytes.
    Assert-StudioSourceIdentity
    Assert-StudioArtifactId -Id $env:COMPILE_ARTIFACT_ID
    $archive = Join-Path $env:RUNNER_TEMP 'studio-compile/compile.zip'
    Assert-StudioSha256 -Path $archive -Expected $env:COMPILE_SHA256
    $workspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd([char[]]@('\', '/'))
    if ([string]::IsNullOrWhiteSpace($env:TOOL_WORKSPACE) -or -not [string]::Equals($workspace, $env:TOOL_WORKSPACE, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Compile tool workspace identity does not match this checkout'
    }
    $root = Join-Path $env:RUNNER_TEMP 'studio-compile-restored'
    Expand-Archive -LiteralPath $archive -DestinationPath $root
    $identity = Get-Content -LiteralPath (Join-Path $root 'identity.json') -Raw | ConvertFrom-Json
    foreach ($pair in @(
        @('runId', $env:GITHUB_RUN_ID), @('commit', $env:RELEASE_SHA),
        @('releaseId', $env:RELEASE_ID), @('version', $env:RELEASE_VERSION), @('workspace', $env:TOOL_WORKSPACE)
    )) {
        if ([string]::IsNullOrWhiteSpace($pair[1]) -or $identity.($pair[0]) -cne $pair[1]) { throw "Compile identity mismatch: $($pair[0])" }
    }
    if ($identity.protocolVersion -ne 2) { throw 'Compile protocol version mismatch' }
    $tool = Join-Path $root 'pl-xtask.exe'
    Assert-StudioSha256 -Path $tool -Expected $env:TOOL_SHA256
    $bundle = Join-Path $root 'bundle'
    Assert-StudioProductVersion -Executable (Join-Path $bundle 'anywork.exe') -Version $env:RELEASE_VERSION
    "STUDIO_RELEASE_TOOL=$tool" | Out-File $env:GITHUB_ENV -Append -Encoding utf8
    "STUDIO_RELEASE_BUNDLE=$bundle" | Out-File $env:GITHUB_ENV -Append -Encoding utf8
}

function Restore-StudioReleaseAssets {
    Assert-StudioArtifactId -Id $env:ASSET_ARTIFACT_ID
    $archive = Join-Path $env:RUNNER_TEMP 'studio-assets/assets.zip'
    Assert-StudioSha256 -Path $archive -Expected $env:ASSET_SHA256
    $destination = Join-Path $env:GITHUB_WORKSPACE "dist/studio-release/$env:RELEASE_VERSION"
    Expand-Archive -LiteralPath $archive -DestinationPath $destination
    Assert-StudioSha256 -Path (Join-Path $destination "anywork-$env:RELEASE_VERSION-windows-x86_64-setup.exe") -Expected $env:INSTALLER_SHA256
}
