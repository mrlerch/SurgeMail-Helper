<# 
Install-WindowsHelper.ps1
Installs the SurgeMail-Helper on Windows by copying the helper files and wiring PATH.
- Scope: CurrentUser (default) or AllUsers
- TargetDir: install destination (default depends on scope)
This script only ADDS files / PATH entries; it does not remove or modify unrelated content.
#>

param(
  [ValidateSet("CurrentUser","AllUsers")]
  [string]$Scope = "CurrentUser",
  [string]$TargetDir
)

function Write-Info($m){ Write-Host $m -ForegroundColor Cyan }
function Write-Err($m){ Write-Host $m -ForegroundColor Red }

# Resolve defaults
if (-not $TargetDir -or $TargetDir.Trim() -eq "") {
  if ($Scope -eq "AllUsers") {
    $TargetDir = Join-Path $env:ProgramFiles "SurgeMail-Helper"
  } else {
    $TargetDir = Join-Path $env:LOCALAPPDATA "SurgeMail-Helper"
  }
}

Write-Info "Installing to: $TargetDir  (Scope: $Scope)"

# Ensure target directory
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

# Source directory = this script's folder's parent (project root) or scripts
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Files to copy
$files = @(
  "scripts\surgemail-helper.ps1",
  "scripts\surgemail-helper.bat",
  "scripts\surgemail.bat"
)

foreach ($rel in $files) {
  $src = Join-Path $ProjectRoot $rel
  if (Test-Path $src) {
    $dst = Join-Path $TargetDir (Split-Path -Leaf $src)
    Copy-Item $src -Destination $dst -Force
    Unblock-File -Path $dst -ErrorAction SilentlyContinue
    Write-Info "Copied: $rel"
  } else {
    Write-Err "Missing expected file: $rel"
  }
}

# Add TargetDir to PATH (CurrentUser or AllUsers)
function Add-ToPath($path, [switch]$Machine) {
  $scope = $Machine ? "Machine" : "User"
  $current = [Environment]::GetEnvironmentVariable("Path", $scope)
  if (-not $current) { $current = "" }
  $parts = $current.Split(';') | Where-Object { $_ -and $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }
  if ($parts -notcontains $path) {
    $new = ($current.TrimEnd(';') + ';' + $path).Trim(';')
    [Environment]::SetEnvironmentVariable("Path", $new, $scope)
    Write-Info "Added to $scope PATH: $path"
  } else {
    Write-Info "$scope PATH already contains: $path"
  }
}

# Prefer placing the 'surgemail.bat' shim somewhere already on PATH.
# If we are AllUsers and elevated, copy to System32; else add TargetDir to PATH.
$shim = Join-Path $TargetDir "surgemail.bat"
$system32 = Join-Path $env:WINDIR "System32"

function Test-IsAdmin {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

$didPlaceShim = $false
if ($Scope -eq "AllUsers" -and (Test-IsAdmin)) {
  try {
    Copy-Item $shim -Destination (Join-Path $system32 "surgemail.bat") -Force
    Write-Info "Installed shim to %WINDIR%\System32\surgemail.bat"
    $didPlaceShim = $true
  } catch {
    Write-Err "Failed to copy shim to System32. Will add TargetDir to PATH instead."
  }
}

if (-not $didPlaceShim) {
  if ($Scope -eq "AllUsers" -and (Test-IsAdmin)) {
    Add-ToPath $TargetDir -Machine
  } else {
    Add-ToPath $TargetDir
  }
}

Write-Info "Verifying installation..."
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
try {
  & surgemail -v
} catch {
  Write-Err "Could not run 'surgemail -v' from PATH. You may need to start a new shell."
}

Write-Host "`nDone." -ForegroundColor Green
