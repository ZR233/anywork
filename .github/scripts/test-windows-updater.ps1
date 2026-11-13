param(
  [Parameter(Mandatory)][string]$Compiler,
  [Parameter(Mandatory)][string]$EvidenceDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$root = [IO.Path]::GetFullPath($EvidenceDirectory)
if (Test-Path -LiteralPath $root) { throw "Evidence directory already exists: $root" }
New-Item -ItemType Directory -Path $root | Out-Null
$payload = New-Item -ItemType Directory -Path (Join-Path $root 'payload')
$installed = Join-Path $root 'installed'

# Exercise the production installer code with a tiny executable that holds its
# image open until released, and records whether Setup restarts it. Isolate only
# OS registration and shortcuts; keep the update/wait/run code unchanged.
$script = Get-Content (Join-Path $workspace 'code/anywork/windows/installer/anywork.iss') -Raw
$script = [regex]::Replace($script, '(?ms)^\[(Icons|Dirs|Registry)\]\r?\n.*?(?=^\[|\z)', '')
$script = $script.Replace('[Setup]', "[Setup]`r`nUninstallable=no")
$script = $script.Replace('SetupIconFile=..\runner\resources\app_icon.ico',
  ('SetupIconFile=' + (Join-Path $workspace 'code/anywork/windows/runner/resources/app_icon.ico')))
$script = $script.Replace('MessagesFile: "Languages\ChineseSimplified.isl"',
  ('MessagesFile: "' + (Join-Path $workspace 'code/anywork/windows/installer/Languages/ChineseSimplified.isl') + '"'))
$scriptPath = Join-Path $root 'installer.iss'
Set-Content -LiteralPath $scriptPath -Value $script -Encoding utf8
$fixtureSource = Join-Path $root 'fixture.cs'
@'
using System;
using System.IO;
using System.Threading;
class Fixture {
  static int Main(string[] args) {
    string root = AppDomain.CurrentDomain.BaseDirectory;
    if (args.Length == 0) {
      File.WriteAllText(Path.Combine(root, "restarted"), "yes");
      return 0;
    }
    File.WriteAllText(Path.Combine(root, "ready"), "yes");
    var deadline = DateTime.UtcNow.AddSeconds(25);
    while (!File.Exists(Path.Combine(root, "release"))) {
      if (DateTime.UtcNow >= deadline) return 2;
      Thread.Sleep(20);
    }
    return 0;
  }
}
'@ | Set-Content -LiteralPath $fixtureSource -Encoding utf8
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:winexe "/out:$($payload.FullName)/anywork.exe" $fixtureSource
if ($LASTEXITCODE -ne 0) { throw 'Could not compile the executable fixture' }
Set-Content (Join-Path $payload.FullName 'LICENSE') 'Synthetic updater test payload'
Set-Content (Join-Path $payload.FullName 'version.txt') 'new'
& $Compiler /Q '/DMyAppVersion=1.2.3' "/DSourceDir=$payload" "/DOutputDir=$root" '/DOutputBase=setup' $scriptPath
if ($LASTEXITCODE -ne 0) { throw 'Could not compile the production installer script' }
$setup = Join-Path $root 'setup.exe'
$common = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NORESTARTAPPLICATIONS',
  '/NOCLOSEAPPLICATIONS', "/DIR=`"$installed`"")
function Start-Setup([string[]]$Extra) {
  Start-Process -FilePath $setup -ArgumentList ($common + $Extra) -WindowStyle Hidden -PassThru
}
function Wait-Setup($Process) {
  if (-not $Process.WaitForExit(40000)) { throw 'Installer exceeded its process-wait budget' }
  $Process.Refresh()
}
function Wait-File([string]$Path, $Process) {
  $deadline = [DateTime]::UtcNow.AddSeconds(10)
  while (-not (Test-Path -LiteralPath $Path)) {
    if ($Process.HasExited -or [DateTime]::UtcNow -ge $deadline) {
      throw "Process did not create $Path"
    }
    Start-Sleep -Milliseconds 20
  }
}

$process = Start-Setup @()
Wait-Setup $process
if ($process.ExitCode -ne 0) { throw "Initial install failed: $($process.ExitCode)" }
foreach ($mode in @('exit', '1')) {
  Set-Content (Join-Path $installed 'version.txt') 'old'
  $process = Start-Setup @("/ANYWORKUPDATE=$mode", '/ANYWORKWAITPID=invalid', "/LOG=`"$root/invalid-$mode.log`"")
  Wait-Setup $process
  if ($process.ExitCode -eq 0 -or (Get-Content (Join-Path $installed 'version.txt')).Trim() -ne 'old') {
    throw "Update mode $mode ignored an invalid old-process identity"
  }

  foreach ($marker in @('ready', 'release', 'restarted')) {
    $path = Join-Path $installed $marker
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
  }
  $oldProcess = Start-Process (Join-Path $installed 'anywork.exe') -ArgumentList 'hold' -WindowStyle Hidden -PassThru
  try {
    Wait-File (Join-Path $installed 'ready') $oldProcess
    $log = Join-Path $root "wait-$mode.log"
    $process = Start-Setup @("/ANYWORKUPDATE=$mode", "/ANYWORKWAITPID=$($oldProcess.Id)", "/LOG=`"$log`"")
    # Keep the old image loaded until Setup has observed it. The installer must
    # neither replace files nor finish while that process is alive.
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not ((Test-Path -LiteralPath $log) -and
      (Select-String -LiteralPath $log -SimpleMatch 'Waiting for application process' -Quiet))) {
      if ($process.HasExited -or [DateTime]::UtcNow -ge $deadline) {
        throw "Update mode $mode did not wait for the old application"
      }
      Start-Sleep -Milliseconds 20
    }
    if ((Get-Content (Join-Path $installed 'version.txt')).Trim() -ne 'old') {
      throw 'Installer replaced files before the old application exited'
    }
  } finally {
    Set-Content (Join-Path $installed 'release') 'yes'
    if (-not $oldProcess.WaitForExit(5000)) { throw 'Old application fixture did not exit' }
    if ($null -ne $process -and -not $process.HasExited) { Wait-Setup $process }
  }
  if ($process.ExitCode -ne 0 -or (Get-Content (Join-Path $installed 'version.txt')).Trim() -ne 'new') {
    throw "Update mode $mode failed to upgrade after the old application exited"
  }
  $restarted = Join-Path $installed 'restarted'
  if ($mode -eq '1') {
    Wait-File $restarted ([Diagnostics.Process]::GetCurrentProcess())
  } elseif ((Test-Path -LiteralPath $restarted) -or
    (Select-String -LiteralPath $log -SimpleMatch '-- Run entry --' -Quiet)) {
    throw 'The published exit-only client unexpectedly restarted'
  }
  Write-Output "PASS: mode=$mode rejects invalid PID, waits for real exit, upgrades, restart=$($mode -eq '1')"
}
