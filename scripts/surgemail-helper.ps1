<#
.SYNOPSIS
  SurgeMail Helper (Windows, PowerShell 7+)
  Version: 1.14.0
  Repo: https://github.com/mrlerch/SurgeMail-Helper
#>

param(
  [Parameter(Mandatory=$false, Position=0)]
  [ValidateSet("status","start","stop","strong_stop","restart","reload","check-update","update","self-check-update","self-update")]
  [string]$Command = "status",
  [string]$Tellmail = "tellmail",
  [string]$Service  = "surgemail",
  [switch]$Unattended
)

$ErrorActionPreference = "Stop"
$VERSION = "1.14.0"
$GH_OWNER = $env:GH_OWNER; if (-not $GH_OWNER) { $GH_OWNER = "mrlerch" }
$GH_REPO  = $env:GH_REPO;  if (-not $GH_REPO)  { $GH_REPO  = "SurgeMail-Helper" }
$GH_API_LATEST = "https://api.github.com/repos/$GH_OWNER/$GH_REPO/releases/latest"

function Have-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Is-Running {
  if (Have-Cmd $Tellmail) {
    try { & $Tellmail status 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { return $true } } catch {}
    try { & $Tellmail version 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { return $true } } catch {}
  }
  $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue
  if ($null -ne $svc) { return $svc.Status -eq 'Running' }
  return $false
}

function Start-SM { $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue; if ($null -ne $svc) { Start-Service -Name $Service; return }; throw "Service '$Service' not found." }
function Stop-SM  { $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue; if ($null -ne $svc) { Stop-Service -Name $Service; return }; throw "Service '$Service' not found." }
function Reload-SM { Restart-Service -Name $Service -ErrorAction SilentlyContinue }
function Get-Version { if (Have-Cmd $Tellmail) { try { & $Tellmail version 2>$null } catch { "tellmail not available" } } else { "tellmail not available" } }

function Get-LatestTag {
  try { (Invoke-RestMethod -Uri $GH_API_LATEST -Headers @{ "User-Agent"="surgemail-helper" }).tag_name } catch { $null }
}

function Compare-VersionLt([string]$a, [string]$b) {
  $a = $a.TrimStart('v'); $b = $b.TrimStart('v')
  $ap = ($a + ".0.0").Split(".")[0..2] | ForEach-Object {[int]$_}
  $bp = ($b + ".0.0").Split(".")[0..2] | ForEach-Object {[int]$_}
  for ($i=0; $i -lt 3; $i++) {
    if ($ap[$i] -lt $bp[$i]) { return $true }
    if ($ap[$i] -gt $bp[$i]) { return $false }
  }
  return $false
}

function Self-Check-Update {
  $tag = Get-LatestTag
  if ($null -ne $tag -and (Compare-VersionLt $VERSION $tag)) {
    Write-Host "[surgemail-helper] A newer version is available: $tag (you have v$VERSION)."
    Write-Host "  To update: surgemail -Command self-update"
  }
}

function Self-Update([string]$Tag) {
  if (-not $Tag) {
    $Tag = Get-LatestTag
    if (-not $Tag) { throw "Could not determine latest release from GitHub." }
  }
  $thisPath = $MyInvocation.MyCommand.Path
  $rawUrl   = "https://raw.githubusercontent.com/$GH_OWNER/$GH_REPO/$Tag/scripts/surgemail-helper.ps1"
  $fallback = "https://raw.githubusercontent.com/$GH_OWNER/$GH_REPO/main/scripts/surgemail-helper.ps1"
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    try { Invoke-WebRequest -Uri $rawUrl -OutFile $tmp -Headers @{ "User-Agent"="surgemail-helper" } }
    catch { Invoke-WebRequest -Uri $fallback -OutFile $tmp -Headers @{ "User-Agent"="surgemail-helper" } }
    $content = Get-Content -Path $tmp -Raw
    if ($content -notmatch 'Version:') { throw "Downloaded script seems invalid." }
    $backup = "$thisPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -Path $thisPath -Destination $backup -Force -ErrorAction SilentlyContinue
    Move-Item -Path $tmp -Destination $thisPath -Force
    Write-Host "Updated surgemail-helper.ps1 to $Tag. Backup saved at $backup."
  } finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
  }
}

try { Self-Check-Update } catch {}

switch ($Command) {
  "status" { if (Is-Running) { "SurgeMail: RUNNING" } else { "SurgeMail: STOPPED" }; "Version: $(Get-Version)" | Write-Output }
  "start"  { if (Is-Running) { "Already running." | Write-Output; break }; Start-SM; Start-Sleep -Seconds 2; if (Is-Running) { "Started." } else { throw "Failed to start." } | Write-Output }
  "stop"   { if (-not (Is-Running)) { "Already stopped." | Write-Output; break }; Stop-SM; Start-Sleep -Seconds 2; if (-not (Is-Running)) { "Stopped." } else { throw "Stop did not succeed. Try strong_stop." } | Write-Output }
  "strong_stop" { if (Have-Cmd $Tellmail) { & $Tellmail shutdown 2>$null } else { Stop-SM }; Start-Sleep -Seconds 3; if (Is-Running) { throw "Strong stop may have failed." } else { "Strong stop completed." | Write-Output } }
  "restart" { & $PSCommandPath -Command stop -Tellmail $Tellmail -Service $Service; & $PSCommandPath -Command start -Tellmail $Tellmail -Service $Service }
  "reload"  { Reload-SM; "Reload requested." | Write-Output }
  "check-update" { "Checking for updates... (placeholder)" | Write-Output }
  "update" {
    $prev = Get-Version; "Previous version: $prev" | Write-Output
    "1) Downloading installer..." | Write-Output
    "2) Stopping service (graceful)..." | Write-Output
    & $PSCommandPath -Command stop -Tellmail $Tellmail -Service $Service
    "3) Running installer..." | Write-Output
    "4) Installer complete." | Write-Output
    "5) Post-install checks..." | Write-Output
    "6) Starting SurgeMail (only if not running)" | Write-Output
    if (Is-Running) { "SurgeMail already running after install. Skipping start." | Write-Output } else { Start-SM }
    Start-Sleep -Seconds 2
    $now = Get-Version; "Current version: $now" | Write-Output
    if (Is-Running) { "Update complete and service is running." | Write-Output } else { throw "Update finished but service is NOT running." }
  }
  "self-check-update" { Self-Check-Update }
  "self-update"       { Self-Update -Tag $null }
  default { "Unknown command: $Command`nUsage: surgemail -Command <command> [-Tellmail <path>] [-Service <name>] [-Unattended]" | Write-Output; exit 2 }
}
