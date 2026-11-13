if ($PSVersionTable.PSVersion.Major -ge 6) {
  & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
  if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell native updater test failed' }
  return
}
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('promptbox-native-update-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $fixture 'source'
New-Item -ItemType Directory -Path (Join-Path $source 'data') -Force | Out-Null
$code = @'
using System;
using System.IO;
public class Program {
  [STAThread] public static void Main() {
    File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "restarted.txt"), "real native restart");
  }
}
'@
Add-Type -TypeDefinition $code -OutputAssembly (Join-Path $source 'prompt_box.exe') -OutputType WindowsApplication
Set-Content -LiteralPath (Join-Path $source 'flutter_windows.dll') -Value 'fixture'
Set-Content -LiteralPath (Join-Path $source 'data/assets') -Value 'fixture'
$fontDirectory = Join-Path $source 'data/flutter_assets/packages/flutter_math_fork/lib/katex_fonts/fonts'
New-Item -ItemType Directory -Path $fontDirectory -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fontDirectory 'KaTeX_Caligraphic-Bold.ttf') -Value 'long asset fixture'
$archive = Join-Path $fixture 'update.zip'
Compress-Archive -Path (Join-Path $source '*') -DestinationPath $archive
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$dart = Join-Path (Split-Path (Get-Command flutter).Source -Parent) 'cache/dart-sdk/bin/dart.exe'
$probe = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../tool/windows_update_native_probe.dart')).Path
$installer = Join-Path $PSScriptRoot 'install_windows.ps1'
foreach ($mode in @('reject','cancel','install')) {
  $work = Join-Path $fixture (('nested-staging-' * 5) + $mode + '-work')
  $targetName = $mode + '-application ' + [char]0x4e2d + [char]0x6587 + ' [test]'
  $target = Join-Path $fixture $targetName
  New-Item -ItemType Directory -Path $work, $target -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $target 'prompt_box.exe') -Value 'old executable'
  Set-Content -LiteralPath (Join-Path $target 'personal-file.txt') -Value 'retained'
  $digest = if ($mode -eq 'reject') { '0' * 64 } else { $hash }
  # Reproduce a desktop launcher inheriting an incompatible module search path.
  $originalModulePath = $env:PSModulePath
  try {
    $env:PSModulePath = Join-Path $fixture 'missing-desktop-modules'
    & $dart run $probe $work $installer $archive $target $digest $mode
  } finally { $env:PSModulePath = $originalModulePath }
  if ($LASTEXITCODE -ne 0) { throw "Native probe failed: $mode" }
  if ($mode -eq 'reject') {
    if (-not (Test-Path -LiteralPath (Join-Path $work 'rejection-observed.txt'))) { throw 'Failure was not surfaced to parent' }
  } elseif ($mode -eq 'install') {
    for ($attempt=0; $attempt -lt 200; $attempt++) {
      $statusFile = Join-Path $work 'installer-status.json'
      $status = Get-Content -LiteralPath $statusFile -Raw | ConvertFrom-Json
      if ($status.state -eq 'failed') { throw $status.message }
      if ($status.state -eq 'completed' -and (Test-Path -LiteralPath (Join-Path $target 'restarted.txt'))) { break }
      Start-Sleep -Milliseconds 100
    }
    if ($status.state -ne 'completed') { throw 'Native installer did not survive parent exit' }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'restarted.txt'))) { throw 'Updated native application was not restarted' }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'data/flutter_assets/packages/flutter_math_fork/lib/katex_fonts/fonts/KaTeX_Caligraphic-Bold.ttf'))) { throw 'Long asset path was not extracted' }
    if (-not (Test-Path -LiteralPath (Join-Path $status.backup 'personal-file.txt'))) { throw 'Previous bundle backup lost data' }
  }
  if ($mode -ne 'install' -and (Get-Content -LiteralPath (Join-Path $target 'prompt_box.exe') -Raw).Trim() -ne 'old executable') { throw 'Unapproved update modified the application' }
}
$bundle = Join-Path $PSScriptRoot '../../build/windows/x64/runner/Release'
if (Test-Path -LiteralPath (Join-Path $bundle 'prompt_box.exe')) {
  $fullArchive = Join-Path $fixture 'flutter-bundle.zip'
  Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $fullArchive
  $fullWork = Join-Path $fixture (('nested-staging-' * 5) + 'flutter-work')
  New-Item -ItemType Directory -Path $fullWork -Force | Out-Null
  & $dart run $probe $fullWork $installer $fullArchive $bundle (Get-FileHash -LiteralPath $fullArchive -Algorithm SHA256).Hash cancel
  if ($LASTEXITCODE -ne 0) { throw 'Full Flutter bundle extraction failed' }
  Write-Output 'Full Flutter bundle preflight and cancellation passed'
}
Write-Output 'Real Windows bootstrap, parent exit, native restart, rejection and cancellation passed'
Write-Output "Evidence directory: $fixture"
