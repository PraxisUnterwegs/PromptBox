param(
  [Parameter(Mandatory=$true)][int]$AppPid,
  [Parameter(Mandatory=$true)][string]$Archive,
  [Parameter(Mandatory=$true)][string]$Target,
  [Parameter(Mandatory=$true)][string]$Work,
  [string]$ExpectedSha256 = ''
)
# Desktop launchers can inherit PowerShell 7's module path. This helper runs
# Windows PowerShell 5.1 and must load its own compatible built-in modules.
$env:PSModulePath = "$PSHOME\Modules"
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$workPath = [IO.Path]::GetFullPath($Work).TrimEnd('\')
$targetPath = [IO.Path]::GetFullPath($Target).TrimEnd('\')
$stage = Join-Path $workPath 'expanded'
$backup = $null
function Write-InstallerStatus([string]$State, [string]$Message) {
  $status = @{ state=$State; message=$Message; backup=$backup; pid=$PID }
  $tempStatus = Join-Path $workPath 'installer-status.tmp'
  $status | ConvertTo-Json | Set-Content -LiteralPath $tempStatus -Encoding UTF8
  Move-Item -LiteralPath $tempStatus -Destination (Join-Path $workPath 'installer-status.json') -Force
}
try {
  Write-InstallerStatus 'starting' 'Preparing update'
  Start-Transcript -LiteralPath (Join-Path $workPath 'install.log') -Append | Out-Null
  if (-not (Test-Path -LiteralPath (Join-Path $targetPath 'prompt_box.exe'))) { throw 'Invalid application directory' }
  if ($workPath.StartsWith($targetPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Update staging must be outside application directory' }
  if ($ExpectedSha256) {
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $ExpectedSha256) { throw 'Archive SHA-256 mismatch' }
  }
  # Expand-Archive on Windows PowerShell fails beyond MAX_PATH. Flutter's
  # bundled font paths can exceed that limit under a nested staging folder.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $longStage = if ($stage.StartsWith('\\')) { '\\?\UNC\' + $stage.Substring(2) } else { '\\?\' + $stage }
  $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    foreach ($entry in $zip.Entries) {
      $name = $entry.FullName.Replace('/', '\')
      if ([IO.Path]::IsPathRooted($name) -or $name -match '(^|\\)\.\.?(\\|$)|:') { throw 'Unsafe archive entry' }
      $destination = $longStage + '\' + $name
      if ($name.EndsWith('\')) {
        [IO.Directory]::CreateDirectory($destination) | Out-Null
      } else {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination)
      }
    }
  } finally { $zip.Dispose() }
  foreach ($required in @('prompt_box.exe', 'flutter_windows.dll', 'data')) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $required))) { throw "Incomplete update: $required" }
  }
  # Verify write permission before the application exits.
  $parent = [IO.Path]::GetDirectoryName($targetPath)
  $probe = Join-Path $parent ('.promptbox-write-test-' + [Guid]::NewGuid().ToString('N'))
  [IO.File]::WriteAllText($probe, 'test')
  Remove-Item -LiteralPath $probe
  Write-InstallerStatus 'ready' 'Update verified; waiting for application approval'
  $deadline = [DateTime]::UtcNow.AddMinutes(3)
  while (-not (Test-Path -LiteralPath (Join-Path $workPath 'install.requested'))) {
    if (Test-Path -LiteralPath (Join-Path $workPath 'install.cancelled')) { Write-InstallerStatus 'cancelled' 'Application cancelled update'; exit 0 }
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Application approval timed out' }
    Start-Sleep -Milliseconds 150
  }
  Write-InstallerStatus 'waiting_for_exit' 'Waiting for the application to close'
  $deadline = [DateTime]::UtcNow.AddMinutes(2)
  while (Get-Process -Id $AppPid -ErrorAction SilentlyContinue) {
    if (Test-Path -LiteralPath (Join-Path $workPath 'install.cancelled')) { Write-InstallerStatus 'cancelled' 'Application cancelled update'; exit 0 }
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Application did not exit; no files were replaced' }
    Start-Sleep -Milliseconds 150
  }
  if (Test-Path -LiteralPath (Join-Path $workPath 'install.cancelled')) { Write-InstallerStatus 'cancelled' 'Application cancelled update'; exit 0 }
  Write-InstallerStatus 'installing' 'Replacing the application'
  $backup = $targetPath + '.previous-' + [Guid]::NewGuid().ToString('N')
  for ($attempt=0; $attempt -lt 40; $attempt++) {
    try { Move-Item -LiteralPath $targetPath -Destination $backup; break }
    catch { if ($attempt -eq 39) { throw }; Start-Sleep -Milliseconds 250 }
  }
  try {
    Move-Item -LiteralPath $stage -Destination $targetPath
    # ProcessStartInfo treats paths literally (PowerShell's WorkingDirectory
    # parameter otherwise expands [] as a wildcard).
    $restart = New-Object System.Diagnostics.ProcessStartInfo
    $restart.FileName = Join-Path $targetPath 'prompt_box.exe'
    $restart.WorkingDirectory = $targetPath
    $restart.UseShellExecute = $false
    [System.Diagnostics.Process]::Start($restart) | Out-Null
  } catch {
    if (Test-Path -LiteralPath $targetPath) {
      Move-Item -LiteralPath $targetPath -Destination (Join-Path $Work 'failed-install')
    }
    Move-Item -LiteralPath $backup -Destination $targetPath
    $backup = $null
    throw
  }
  Write-InstallerStatus 'completed' 'Updated and restarted successfully'
} catch {
  Write-InstallerStatus 'failed' $_.Exception.Message
  Write-Output $_
  if (Test-Path -LiteralPath (Join-Path $workPath 'install.requested')) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("PromptBox update failed. The previous version was retained. See $workPath\install.log`n$_", 'PromptBox update failed') | Out-Null
  }
  exit 1
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}
