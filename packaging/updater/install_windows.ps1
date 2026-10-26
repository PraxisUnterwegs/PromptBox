param(
  [Parameter(Mandatory=$true)][int]$AppPid,
  [Parameter(Mandatory=$true)][string]$Archive,
  [Parameter(Mandatory=$true)][string]$Target,
  [Parameter(Mandatory=$true)][string]$Work
)
$ErrorActionPreference = 'Stop'
$stage = Join-Path $Work 'expanded'
$backup = $null
try {
  Start-Transcript -LiteralPath (Join-Path $Work 'install.log') -Append | Out-Null
  $targetPath = [IO.Path]::GetFullPath($Target).TrimEnd('\')
  $workPath = [IO.Path]::GetFullPath($Work).TrimEnd('\')
  if (-not (Test-Path -LiteralPath (Join-Path $targetPath 'prompt_box.exe'))) { throw 'Invalid application directory' }
  if ($workPath.StartsWith($targetPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Update staging must be outside application directory' }
  Expand-Archive -LiteralPath $Archive -DestinationPath $stage
  foreach ($required in @('prompt_box.exe', 'flutter_windows.dll', 'data')) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $required))) { throw "Incomplete update: $required" }
  }
  # Do not terminate the app: users choose when to save drafts and close it.
  $appProcess = Get-Process -Id $AppPid -ErrorAction SilentlyContinue
  if ($appProcess) { $appProcess.WaitForExit() }
  $backup = $targetPath + '.previous-' + [Guid]::NewGuid().ToString('N')
  Move-Item -LiteralPath $targetPath -Destination $backup
  try {
    Move-Item -LiteralPath $stage -Destination $targetPath
    Start-Process -FilePath (Join-Path $targetPath 'prompt_box.exe') -WorkingDirectory $targetPath
  } catch {
    if (Test-Path -LiteralPath $targetPath) {
      Move-Item -LiteralPath $targetPath -Destination (Join-Path $Work 'failed-install')
    }
    Move-Item -LiteralPath $backup -Destination $targetPath
    $backup = $null
    throw
  }
  # Keep the previous bundle for manual recovery, including any user-added files.
  Write-Output "Updated. Previous version retained at $backup"
} catch {
  Write-Output $_
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.MessageBox]::Show("更新失败，旧版本已保留。请查看 $Work\install.log`n$_", 'PromptBox 更新失败') | Out-Null
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}
