Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Install-StudioInnoSetup {
    $isccCandidates = @(
      'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
      'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    $iscc = $isccCandidates |
      Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
      Select-Object -First 1
    if ($null -eq $iscc) {
      choco install innosetup --version=6.4.3 --yes --no-progress
      if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Inno Setup 6.4.3 (choco exit $LASTEXITCODE)"
      }
      $iscc = $isccCandidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    }
    if ($null -eq $iscc) {
      throw 'Inno Setup 6 compiler was not found after installation'
    }
    $isccVersion = [Version](Get-Item -LiteralPath $iscc).VersionInfo.FileVersion
    if ($isccVersion -eq [Version]'0.0.0.0') {
      Write-Warning "Inno Setup at $iscc does not expose meaningful file-version metadata; package staging will validate the compiler"
    } elseif ($isccVersion.Major -ne 6 -or $isccVersion -lt [Version]'6.4.3') {
      throw "Unsupported Inno Setup compiler version $isccVersion at $iscc"
    } else {
      Write-Output "Using Inno Setup compiler $isccVersion at $iscc"
    }
    "ISCC_PATH=$iscc" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8

}

function Install-StudioMinisign {
    $archive = Join-Path $env:RUNNER_TEMP 'minisign-0.12-win64.zip'
    Invoke-WebRequest -Uri 'https://github.com/jedisct1/minisign/releases/download/0.12/minisign-0.12-win64.zip' -OutFile $archive
    $actualHash = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
    if ($actualHash -ne '37b600344e20c19314b2e82813db2bfdcc408b77b876f7727889dbd46d539479') {
      throw "Unexpected Minisign archive SHA-256: $actualHash"
    }
    $toolDir = Join-Path $env:RUNNER_TEMP 'minisign-0.12'
    Expand-Archive -LiteralPath $archive -DestinationPath $toolDir
    $minisign = Join-Path $toolDir 'minisign-win64\x86_64\minisign.exe'
    if (-not (Test-Path -LiteralPath $minisign -PathType Leaf)) {
      throw 'x86_64 minisign.exe not found in verified archive'
    }
    (Split-Path -Parent $minisign) | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8
}

function Test-StudioInstaller {
    $releaseDir = Join-Path $env:GITHUB_WORKSPACE "dist/studio-release/$env:RELEASE_VERSION"
    $installer = Join-Path $releaseDir "anywork-$env:RELEASE_VERSION-windows-x86_64-setup.exe"
    $installDir = Join-Path $env:RUNNER_TEMP 'anywork-smoke'
    $process = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',"/DIR=$installDir" -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installer exited with $($process.ExitCode)" }
    $executable = Join-Path $installDir 'anywork.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Installed executable missing' }
    $productVersion = (Get-Item -LiteralPath $executable).VersionInfo.ProductVersion
    if ($productVersion -cne $env:RELEASE_VERSION) {
      throw "Installed version $productVersion does not match $env:RELEASE_VERSION"
    }
    $uninstallRoots = @(
      'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
      'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $uninstall = @(
      foreach ($root in $uninstallRoots) {
        if (Test-Path -LiteralPath $root) {
          Get-ChildItem -LiteralPath $root |
            Get-ItemProperty |
            Where-Object {
              $_.PSObject.Properties['DisplayName'] -and $_.PSObject.Properties['DisplayVersion'] -and
              ($_.DisplayName -like 'anywork*' -or $_.DisplayName -like '糊来帮*') -and
              $_.DisplayVersion -eq $env:RELEASE_VERSION
            }
        }
      }
    )
    if ($uninstall.Count -ne 1) {
      throw "Expected one per-user uninstall registration for $env:RELEASE_VERSION, found $($uninstall.Count)"
    }
}
