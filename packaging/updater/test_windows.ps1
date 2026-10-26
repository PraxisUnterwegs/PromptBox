$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('promptbox-installer-test-' + [Guid]::NewGuid().ToString('N'))
$targetName = 'PromptBox ' + [char]0x4e2d + [char]0x6587 + ' [test]'
$target = Join-Path $fixture $targetName
$source = Join-Path $fixture 'new bundle'
$work = Join-Path $fixture 'update work'
foreach ($dir in @($target, $source, $work, (Join-Path $source 'data'))) {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
Set-Content -LiteralPath (Join-Path $target 'prompt_box.exe') -Value 'old'
Set-Content -LiteralPath (Join-Path $source 'prompt_box.exe') -Value 'new'
Set-Content -LiteralPath (Join-Path $source 'flutter_windows.dll') -Value 'fixture'
Set-Content -LiteralPath (Join-Path $source 'data/assets') -Value 'fixture'
Set-Content -LiteralPath (Join-Path $target 'personal-file.txt') -Value 'retained in backup'
$archive = Join-Path $work 'update.zip'
Compress-Archive -Path (Join-Path $source '*') -DestinationPath $archive
$launchState = @{ launched = $false }
# Replace only the application launch; exercise real extraction and replacement.
function Start-Process([string]$FilePath, [string]$WorkingDirectory) {
  if (-not (Test-Path -LiteralPath $FilePath)) { throw 'Missing updated executable' }
  $launchState.launched = $true
}
& (Join-Path $PSScriptRoot 'install_windows.ps1') -AppPid 2147483647 -Archive $archive -Target $target -Work $work
if (-not $launchState.launched) { throw 'Installer did not restart the application' }
if ((Get-Content -LiteralPath (Join-Path $target 'prompt_box.exe') -Raw).Trim() -ne 'new') { throw 'Bundle was not replaced' }
$previous = @(Get-ChildItem -LiteralPath $fixture -Directory | Where-Object { $_.Name.StartsWith($targetName + '.previous-') })
if ($previous.Count -ne 1) { throw 'Expected one previous bundle' }
if ((Get-Content -LiteralPath (Join-Path $previous[0].FullName 'prompt_box.exe') -Raw).Trim() -ne 'old') { throw 'Previous executable missing' }
if (-not (Test-Path -LiteralPath (Join-Path $previous[0].FullName 'personal-file.txt'))) { throw 'Previous user files missing' }
Write-Output 'Windows updater replacement, restart and backup smoke test passed'
