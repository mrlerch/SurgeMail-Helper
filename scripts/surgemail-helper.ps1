<#
.SYNOPSIS
  SurgeMail Helper: Control & Updater (Windows PowerShell)
  Version: 1.15.0 (2025-09-16)

.DESCRIPTION
  Windows PowerShell feature-parity port of the Bash-based "surgemail-helper.sh" v1.15.0.
  Provides SurgeMail server lifecycle commands, update flows, self-update of the helper via GitHub,
  diagnostics, and convenience helpers. Mirrors command names, flags, and behavior where practical
  on Windows. For Unix-like systems use the original Bash script.

.COPYRIGHT
  ©2025 LERCH design. All rights reserved. https://www.lerchdesign.com. DO NOT REMOVE.
#>

# ==============================
#  Globals & Config
# ==============================

$ErrorActionPreference = 'Stop'

# Script/Helper version
$SCRIPT_VERSION  = '1.15.0'
$HELPER_VERSION  = '1.15.0'

# Default install dir (Windows). Override via $Env:SURGEMAIL_DIR
$Global:SURGEMAIL_DIR = if ($Env:SURGEMAIL_DIR) { $Env:SURGEMAIL_DIR } `
  elseif (Test-Path 'C:\Surgemail') { 'C:\Surgemail' } `
  elseif (Test-Path "$Env:ProgramFiles\Surgemail") { "$Env:ProgramFiles\Surgemail" } `
  else { 'C:\Surgemail' }

$Global:STOP_CMD = @(
  (Join-Path $Global:SURGEMAIL_DIR 'surgemail_stop.bat'),
  (Join-Path $Global:SURGEMAIL_DIR 'surgemail_stop.cmd')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$Global:START_CMD = @(
  (Join-Path $Global:SURGEMAIL_DIR 'surgemail_start.bat'),
  (Join-Path $Global:SURGEMAIL_DIR 'surgemail_start.cmd')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$Global:PID_FILE  = Join-Path $Global:SURGEMAIL_DIR 'surgemail.pid'
$Global:ADMIN_URL = 'http://127.0.0.1:7025/'
$Global:CHECK_PORTS = @(25,465,587,110,143,993,995,7025)

# GitHub helper config for self-update (mirrors _gh_helpers.inc.sh)
$Global:GH_OWNER = if ($Env:GH_OWNER) { $Env:GH_OWNER } else { 'mrlerch' }
$Global:GH_REPO  = if ($Env:GH_REPO)  { $Env:GH_REPO }  else { 'SurgeMail-Helper' }
$Global:GH_API   = if ($Env:GH_API)   { $Env:GH_API }   else { 'https://api.github.com' }
$Global:GH_TOKEN = if ($Env:GH_TOKEN) { $Env:GH_TOKEN } elseif ($Env:GITHUB_TOKEN) { $Env:GITHUB_TOKEN } else { '' }

# Verbose flag (0/1). Toggle with --verbose
$Global:VERBOSE = if ($Env:VERBOSE) { [int]$Env:VERBOSE } else { 0 }

# ---------------- Utilities ----------------
function vlog([string]$msg) { if ($Global:VERBOSE -eq 1) { Write-Host "[debug] $msg" } }
function warn([string]$msg) { Write-Warning $msg }
function die([string]$msg)  { throw "Error: $msg" }

function Get-ScriptPath { if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } }
function Get-ScriptDir  { Split-Path -Parent (Get-ScriptPath) }
function Get-ProjectRoot { Split-Path -Parent (Get-ScriptDir) }

function Test-Command([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    die "Please run PowerShell as Administrator."
  }
}

# --------------- HTTP Helpers (GitHub parity) ---------------
function GH-AuthHeaders {
  $h = @{
    'User-Agent' = "surgemail-helper/$HELPER_VERSION"
    'Accept'     = 'application/vnd.github+json'
  }
  if ($Global:GH_TOKEN) { $h['Authorization'] = "Bearer $($Global:GH_TOKEN)" }
  return $h
}

function Invoke-HttpJson($Url) {
  Invoke-RestMethod -Uri $Url -Headers (GH-AuthHeaders) -Method Get -ErrorAction Stop
}

function Invoke-HttpString($Url) {
  $wc = New-Object System.Net.WebClient
  foreach ($k in (GH-AuthHeaders).Keys) { $wc.Headers[$k] = (GH-AuthHeaders)[$k] }
  $wc.Encoding = [System.Text.Encoding]::UTF8
  $wc.DownloadString($Url)
}

function Invoke-HttpDownload($Url, $OutFile) {
  $wc = New-Object System.Net.WebClient
  foreach ($k in (GH-AuthHeaders).Keys) { $wc.Headers[$k] = (GH-AuthHeaders)[$k] }
  $dir = Split-Path -Parent $OutFile
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $wc.DownloadFile($Url, $OutFile)
}

# --------------- Net/Process Helpers ---------------
function Get-NetListeners {
  # Returns objects: PID, Process, Port
  $lines = netstat -ano -p tcp | Select-String -Pattern 'LISTENING'
  foreach ($ln in $lines) {
    $parts = ($ln -replace '\s+', ' ').Trim().Split(' ')
    if ($parts.Count -ge 5) {
      $local = $parts[1]
      $pid   = [int]$parts[-1]
      if ($local -match ':(\d+)$') {
        $port = [int]$Matches[1]
        [pscustomobject]@{
          PID=$pid; Process=(try { (Get-Process -Id $pid -ErrorAction SilentlyContinue).ProcessName } catch { 'unknown' }); Port=$port
        }
      }
    }
  }
}

function Get-BlockersDetailed { Get-NetListeners | Where-Object { $Global:CHECK_PORTS -contains $_.Port } | Select-Object PID,Process,Port }
function Stop-AllBlockers {
  $any = $false
  foreach ($b in (Get-BlockersDetailed)) {
    try {
      vlog "Killing blocker pid=$($b.PID) proc=$($b.Process) port=$($b.Port)"
      Stop-Process -Id $b.PID -Force -ErrorAction SilentlyContinue
      Write-Host "[force] Killed pid $($b.PID): $($b.Process) (port $($b.Port))"
      $any = $true
    } catch {}
  }
  return $any
}

# --------------- tellmail / SurgeMail probes ---------------
function Get-TellmailPath {
  $cand = @('tellmail.exe','tellmail.bat','tellmail.cmd',
            (Join-Path $Global:SURGEMAIL_DIR 'tellmail.exe'),
            (Join-Path $Global:SURGEMAIL_DIR 'tellmail.bat'))
  foreach ($c in $cand) { if (Get-Command $c -ErrorAction SilentlyContinue) { return (Get-Command $c).Source } }
  return $null
}

function Invoke-Tellmail([string[]]$Args) {
  $t = Get-TellmailPath
  if (-not $t) { return $null }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $t
  $psi.Arguments = ($Args -join ' ')
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd()
  $null = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return $out
}

function Test-UrlReachable([string]$Url) {
  try {
    $req = [System.Net.WebRequest]::Create($Url)
    $req.Method = 'GET'
    $req.Timeout = 2000
    $resp = $req.GetResponse()
    $resp.Close()
    $true
  } catch { $false }
}

function Test-SurgeMailReadyQuiet {
  $out = Invoke-Tellmail @('status')
  if ($out) {
    if ($out -match 'Bad Open Response') { return $false }
    if ($out -match 'SurgeMail Version') { return $true }
  }
  if (Test-Path $Global:PID_FILE) {
    try { $pid = Get-Content $Global:PID_FILE | Select-Object -First 1
      if ($pid -and (Get-Process -Id $pid -ErrorAction SilentlyContinue)) { return $true } } catch {}
  }
  if (Test-UrlReachable $Global:ADMIN_URL) { return $true }
  return $false
}

function Test-SurgeMailReady {
  Write-Host "Checking status..."
  Start-Sleep -Seconds 1
  return (Test-SurgeMailReadyQuiet)
}

function Wait-ForReady([int]$TimeoutSec=45) {
  $t=0; while ($t -lt $TimeoutSec) { if (Test-SurgeMailReady) { return $true }; Start-Sleep -Seconds 1; $t++ }
  return $false
}
function Wait-ForStopped([int]$TimeoutSec=20) {
  $t=0; while ($t -lt $TimeoutSec) { if (-not (Test-SurgeMailReady)) { return $true }; Start-Sleep -Seconds 1; $t++ }
  return $false
}

# --------------- Version helpers (server) ---------------
function Normalize-CompactVersion([string]$s) {
  # From "tellmail version" -> "... Version 8.0e, ..." -> "80e"
  if (-not $s) { return '' }
  $m = [regex]::Match($s, 'Version\s+([0-9]+)\.([0-9]+)([A-Za-z])')
  if ($m.Success) { return "$($m.Groups[1].Value)$($m.Groups[2].Value)$($m.Groups[3].Value.ToLower())" }
  return ''
}
function Pretty-FromCompact([string]$n) {
  if ($n -match '^([0-9]{2})([a-z])$') { return ("{0}.{1}{2}" -f $n.Substring(0,1), $n.Substring(1,1), $Matches[1] = $null; $n.Substring(2)) }
  return $n
}
function Compare-Compact($a,$b) {
  if ($a -eq $b) { return 0 }
  $ra = [regex]::Match($a,'^([0-9]+)([A-Za-z])$')
  $rb = [regex]::Match($b,'^([0-9]+)([A-Za-z])$')
  if (-not ($ra.Success -and $rb.Success)) { return 0 }
  $aN = [int]$ra.Groups[1].Value; $aL = $ra.Groups[2].Value.ToLower()
  $bN = [int]$rb.Groups[1].Value; $bL = $rb.Groups[2].Value.ToLower()
  if ($aN -gt $bN) { return 1 }
  if ($aN -lt $bN) { return 2 }
  if ($aL -gt $bL) { return 1 }
  if ($aL -lt $bL) { return 2 }
  return 0
}
function Detect-InstalledServerVersion {
  $out = Invoke-Tellmail @('version')
  if (-not $out) { return '' }
  return (Normalize-CompactVersion $out)
}
function Detect-OsTarget {
  $out = Invoke-Tellmail @('version')
  if ($out) {
    $plat = ($out -replace '\r','') -replace '.*Platform\s+',''
    $p = $plat.ToLower()
    if ($p -match 'linux_64') { return 'linux64' }
    if ($p -match 'linux')    { return 'linux' }
    if ($p -match 'freebsd')  { return 'freebsd64' }
    if ($p -match 'solaris|sunos') { return 'solaris_i64' }
    if ($p -match 'macosx.*arm') { return 'macosx_arm64' }
    if ($p -match 'macosx|darwin') { return 'macosx_intel64' }
    if ($p -match 'windows.*64') { return 'windows64' }
    if ($p -match 'windows') { return 'windows' }
  }
  if ([Environment]::Is64BitOperatingSystem) { return 'windows64' } else { return 'windows' }
}

# --------------- GitHub (_gh_helpers parity) ---------------
function GH-LatestReleaseTag {
  try {
    $json = Invoke-HttpJson "$($Global:GH_API)/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)/releases/latest"
    if ($json.tag_name) { return $json.tag_name }
  } catch {}
  try {
    $tags = Invoke-HttpJson "$($Global:GH_API)/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)/tags?per_page=1"
    if ($tags -and $tags[0].name) { return $tags[0].name }
  } catch {}
  try {
    $repo = Invoke-HttpJson "$($Global:GH_API)/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)"
    if ($repo.default_branch) { return $repo.default_branch }
  } catch {}
  return $null
}
function GH-FirstPrereleaseTag {
  try {
    $rels = Invoke-HttpJson "$($Global:GH_API)/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)/releases?per_page=50"
    foreach ($r in $rels) { if ($r.prerelease -and $r.tag_name) { return $r.tag_name } }
  } catch {}
  return $null
}
function GH-DefaultBranch {
  try {
    $repo = Invoke-HttpJson "$($Global:GH_API)/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)"
    return $repo.default_branch
  } catch {}
  return $null
}

# --------------- Helper SemVer (self_update/check) ---------------
function Normalize-SemVer([string]$v) {
  $v = $v.TrimStart('v','V')
  if ($v -match '^([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?') {
    $a = [int]$Matches[1]; $b = if ($Matches[2]) { [int]$Matches[2] } else { 0 }; $c = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
    return "{0}.{1}.{2}" -f $a,$b,$c
  }
  return '0.0.0'
}
function Compare-SemVer($a,$b) {
  $A = (Normalize-SemVer $a).Split('.'); $B = (Normalize-SemVer $b).Split('.')
  for ($i=0; $i -lt 3; $i++) {
    $ai = [int]$A[$i]; $bi = [int]$B[$i]
    if ($ai -gt $bi) { return 1 }
    if ($ai -lt $bi) { return -1 }
  }
  return 0
}

# --------------- UI / Help ---------------
function Show-MainHelp {
@"
Usage: surgemail <command> [options]

Commands:
  -u | update       Download and install a specified SurgeMail version
                    Options:
                      --version <ver>   e.g. 80e (NOT the full artifact name)
                      --os <target>     windows64 | windows | linux64 | linux |
                                        solaris_i64 | freebsd64 |
                                        macosx_arm64 | macosx_intel64
                      --api             requires --version, no prompts, auto-answers, --force
                      --yes             Auto-answer installer prompts with y (Windows: no-op)
                      --force           Kill ANY processes blocking required ports at start
                      --dry-run         Simulate actions without changes
                      --verbose         Show detailed debug output
  check-update      Detect installed version and compare with latest online
                    Options:
                      --os <target>     Artifact OS (auto-detected if omitted)
                      --auto            If newer exists, run 'update --api' automatically.
                      --verbose         Show details
  self_check_update Checks for newer Helper script version and prompt to update.
                    Format:
                      surgemail self_check_update [--channel <release|prerelease|dev>] [--auto] [--quiet] [--token <gh_token>]
  self_update       Update the Helper script folder (git checkout or ZIP overlay).
                    Format:
                      surgemail self_update [--channel <release|prerelease|dev>] [--auto] [--token <gh_token>]
  stop              Stop SurgeMail AND free required ports (kills blockers)
  start             Start the SurgeMail server (use --force to kill blockers)
  restart           Stop then start the SurgeMail server (use --force to kill blockers)
  -r | reload       Reload SurgeMail configuration via 'tellmail reload'
  -s | status       Show current SurgeMail status via 'tellmail status'
  -v | version      Show installed SurgeMail version via 'tellmail version'
  -w | where        Show helper dir, surgemail server dir, tellmail path.
  -d | diagnostics  Print environment/report.
  -h | --help       Show this help
  man               Show help (Windows).
  debug-gh          Debug GitHub API connectivity and auth

Notes (Windows):
  • update: If the selected artifact is a Windows .exe, the file is downloaded and its path is printed.
            Silent installer flags vary by release; this script does not attempt to run the .exe.
  • start/stop/restart: Uses Windows Service 'SurgeMail' if present, else falls back to surgemail_start/stop.bat.
"@
}

# --------------- Core Commands ---------------
function Resolve-Artifact($Version, $Os) {
  switch ($Os) {
    'windows64' { $suffix='windows64'; $ext='exe' }
    'windows'   { $suffix='windows';   $ext='exe' }
    'linux64'   { $suffix='linux64';   $ext='tar.gz' }
    'linux'     { $suffix='linux';     $ext='tar.gz' }
    'solaris_i64' { $suffix='solaris_i64'; $ext='tar.gz' }
    'freebsd64' { $suffix='freebsd64'; $ext='tar.gz' }
    'macosx_arm64' { $suffix='macosx_arm64'; $ext='tar.gz' }
    'macosx_intel64' { $suffix='macosx_intel64'; $ext='tar.gz' }
    default { die "Unknown --os '$Os'." }
  }
  $artifact = "surgemail_${Version}_${suffix}.${ext}"
  $url = "https://netwinsite.com/ftp/surgemail/$artifact"
  return @{ Artifact=$artifact; Url=$url }
}

function cmd_check_update {
  param([string[]]$Args)
  $TARGET_OS=''; $AUTO=$false
  for ($i=0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      '--os' { $TARGET_OS = $Args[++$i] }
      '--auto' { $AUTO = $true }
      '--verbose' { $Global:VERBOSE = 1 }
      '-h' { Write-Host "Usage: surgemail check-update [--os <target>] [--auto] [--verbose]"; return }
      default {}
    }
  }

  $installed_norm = Detect-InstalledServerVersion
  $installed_pretty = if ($installed_norm) { "{0}.{1}{2}" -f $installed_norm.Substring(0,1), $installed_norm.Substring(1,1), $installed_norm.Substring(2,1) } else { 'unknown' }

  # Scrape latest from website (same approach as Bash)
  $html = $null
  try {
    $html = Invoke-HttpString 'https://surgemail.com/download-surgemail/'
    if (-not $html) { $html = Invoke-HttpString 'https://surgemail.com/knowledge-base/surgemail-change-history/' }
  } catch {}

  $latest_compact=''; $latest_pretty=''; $latest_norm=''
  if ($html) {
    $one = ($html -replace "`r?`n",' ')
    $m = [regex]::Match($one, 'Current\s*Release[^0-9A-Za-z]*([0-9][0-9][A-Za-z])', 'IgnoreCase')
    if ($m.Success) { $latest_compact = $m.Groups[1].Value }
    if (-not $latest_compact) {
      $tokens = [regex]::Matches($html, '[7-9]\.[0-9]+[A-Za-z]') | Select-Object -ExpandProperty Value -Unique
      $bestN=''; $bestP=''
      foreach ($t in $tokens) {
        $n = Normalize-CompactVersion "Version $t,"
        if ($n) {
          if (-not $bestN) { $bestN=$n; $bestP=$t }
          else {
            $cmp = Compare-Compact $n $bestN
            if ($cmp -eq 1) { $bestN=$n; $bestP=$t }
          }
        }
      }
      $latest_norm = $bestN; $latest_pretty = $bestP
    } else {
      $latest_norm = $latest_compact
      $latest_pretty = "{0}.{1}{2}" -f $latest_compact.Substring(0,1), $latest_compact.Substring(1,1), $latest_compact.Substring(2,1)
    }
  }

  Write-Host "Installed SurgeMail version: $installed_pretty"
  if (-not $latest_pretty) {
    Write-Host "Could not parse the latest stable version from the website."
    return
  }
  Write-Host "Latest stable release:       $latest_pretty"

  if (-not $installed_norm) { 
    Write-Host "Note: Unable to compare versions automatically (tellmail not found or unrecognized output)."
    return
  }

  switch (Compare-Compact $installed_norm $latest_norm) {
    0 { Write-Host "You are running the latest stable release."; if ($AUTO) { Write-Host "[auto] No update necessary." } }
    1 { Write-Host "Your installed version appears newer than the published stable. (Installed=$installed_pretty, Latest=$latest_pretty)" }
    2 {
      Write-Host "An update is available. (Installed=$installed_pretty, Latest=$latest_pretty)"
      if ($AUTO) {
        if (-not $TARGET_OS) { $TARGET_OS = Detect-OsTarget }
        if (-not $TARGET_OS) { Write-Host "[auto] Could not determine OS. Pass --os."; return }
        Write-Host "[auto] Updating to $latest_norm for OS $TARGET_OS ..."
        cmd_update @("--version",$latest_norm,"--os",$TARGET_OS,"--api")
      } else {
        $TARGET_OS = if ($TARGET_OS) { $TARGET_OS } else { Detect-OsTarget }
        if ($Host.UI.RawUI -and $Host.UI.RawUI.KeyAvailable) {
          $ans = Read-Host "Upgrade to $latest_pretty now? [y/N]"
          if ($ans -match '^(y|yes)$') {
            if (-not $TARGET_OS) { $TARGET_OS = Read-Host "Select OS (windows64|windows|linux64|linux|freebsd64|solaris_i64|macosx_arm64|macosx_intel64)" }
            Write-Host "Starting upgrade to $latest_pretty for OS $TARGET_OS ..."
            cmd_update @("--version",$latest_norm,"--os",$TARGET_OS)
          } else {
            if ($TARGET_OS) { Write-Host "To update later: surgemail update --version $latest_norm --os $TARGET_OS" }
            else { Write-Host "To update later: surgemail update --version $latest_norm --os (linux64|...)" }
          }
        } else {
          if ($TARGET_OS) { Write-Host "To update now: surgemail update --version $latest_norm --os $TARGET_OS" }
          else { Write-Host "To update now: surgemail update --version $latest_norm --os (linux64|linux|windows64|windows|freebsd64|solaris_i64|macosx_arm64|macosx_intel64)" }
        }
      }
    }
  }
}

function cmd_update {
  param([string[]]$Args)
  $DRY_RUN=$false; $VERSION=''; $TARGET_OS=''; $FORCE=$false; $API=$false; $AUTO_YES=$false
  for ($i=0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      '--dry-run' { $DRY_RUN = $true }
      '--version' { $VERSION = $Args[++$i] }
      '--os'      { $TARGET_OS = $Args[++$i] }
      '--force'   { $FORCE = $true }
      '--api'     { $API = $true; $AUTO_YES=$true; $FORCE=$true }
      '--yes'     { $AUTO_YES=$true }
      '--verbose' { $Global:VERBOSE = 1 }
      '-h' { Show-MainHelp; return }
      default { if (-not $VERSION) { $VERSION = $Args[$i] } elseif (-not $TARGET_OS) { $TARGET_OS = $Args[$i] } }
    }
  }

  Require-Admin
  if (-not $Global:STOP_CMD)  { Write-Host "Stop script not found in $Global:SURGEMAIL_DIR"; return }
  if (-not $Global:START_CMD) { Write-Host "Start script not found in $Global:SURGEMAIL_DIR"; return }

  if (-not $VERSION) {
    if ($API) { Write-Host "--api requires --version <ver>"; return }
    $VERSION = Read-Host "Enter SurgeMail version (e.g. 80e) or leave blank to exit"
    if (-not $VERSION) { Write-Host "`nExiting SurgeMail update without change.`n"; return }
  }
  if (-not $TARGET_OS) {
    $TARGET_OS = Detect-OsTarget
    if (-not $TARGET_OS) {
      if ($API) { Write-Host "--api requires --os when OS cannot be auto-detected"; return }
      $TARGET_OS = Read-Host "Select OS (windows64|windows|linux64|linux|freebsd64|solaris_i64|macosx_arm64|macosx_intel64)"
    }
  }

  $res = Resolve-Artifact $VERSION $TARGET_OS
  $artifact = $res.Artifact; $url = $res.Url

  Write-Host ""
  Write-Host "1) Checking availability: $url"
  try {
    $resp = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing
  } catch { Write-Host "Package not found at: $url (check version/OS)."; return }

  $work = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(),"surgemail-update-"+([System.Guid]::NewGuid()))) -Force
  $FILENAME = Join-Path $work.FullName $artifact
  Write-Host "Using temp dir: $($work.FullName)"

  Write-Host ""
  Write-Host "2) Downloading: $url"
  if (-not $DRY_RUN) {
    Invoke-HttpDownload $url $FILENAME
  } else {
    Set-Content -Path $FILENAME -Value "placeholder`n"
    Write-Host "[dry-run] download simulated -> $FILENAME"
  }
  $fi = Get-Item $FILENAME
  if (-not $fi -or $fi.Length -le 0) { Write-Host "Downloaded file is empty: $FILENAME"; return }
  Write-Host ("Download OK: {0} ({1:N0} bytes)" -f $fi.Name, $fi.Length)

  if ($FILENAME -match '\.exe$') {
    Write-Host ""
    Write-Host "3) Detected Windows artifact (.exe)"
    Write-Host "Saved file: $FILENAME"
    Write-Host "Note: The script does not attempt silent install of the .exe."
    return
  }

  Write-Host ""
  Write-Host "3) Extracting archive (.tar.gz) — Windows host not supported for direct install."
  if (-not $DRY_RUN) {
    Write-Host "Archive saved; manual extraction/transfer may be required for non-Windows targets."
  } else {
    Write-Host "[dry-run] would extract and run installer"
  }

  # Stop/Start around install on Windows is not applicable for .tar.gz flows.
  Write-Host ""
  Write-Host ("All done. Surgemail helper v{0}. Downloaded {1} (OS: {2})." -f $SCRIPT_VERSION, $VERSION, $TARGET_OS)
}

function cmd_stop([string[]]$Args) {
  $Global:VERBOSE = ($Args -contains '--verbose') ? 1 : $Global:VERBOSE
  Require-Admin
  if (-not $Global:STOP_CMD) { die "Stop script missing in $Global:SURGEMAIL_DIR" }
  Write-Host "Requested: stop SurgeMail server."

  $was_running = (Test-SurgeMailReady) ? $true : $false
  if ($was_running) { Write-Host "Status before: running." } else { Write-Host "Status before: not running (or not healthy)." }

  # Try Windows Service first
  $svc = Get-Service -Name 'SurgeMail' -ErrorAction SilentlyContinue
  if ($svc) {
    try {
      if ($svc.Status -ne 'Stopped') { Stop-Service -Name 'SurgeMail' -Force -ErrorAction SilentlyContinue }
    } catch {}
  }

  # Call stop script
  & $Global:STOP_CMD 2>$null | Out-Null

  # Best-effort: kill listeners
  Write-Host "Freeing required ports (25,465,587,110,143,993,995,7025)..."
  if (Stop-AllBlockers) { vlog "Blockers killed during stop." }

  if (Wait-ForStopped 20) {
    Write-Host "Result: SurgeMail server stopped and ports freed."
  } else {
    Write-Host "Result: stop requested; made best effort to free ports."
    if (-not $was_running) { Write-Host "Note: Service appeared down before the stop request." }
  }
}

function cmd_start([string[]]$Args) {
  $FORCE = ($Args -contains '--force')
  $Global:VERBOSE = ($Args -contains '--verbose') ? 1 : $Global:VERBOSE
  Require-Admin
  if (-not $Global:START_CMD) { die "Start script missing in $Global:SURGEMAIL_DIR" }
  if (Test-SurgeMailReady) { Write-Host "SurgeMail server is already running (or healthy). Proceeding to start anyway." } else { Write-Host "SurgeMail server is currently stopped. Proceeding to start server." }
  Write-Host "Requested: start SurgeMail server."
  if ($FORCE) { if (Stop-AllBlockers) { vlog "Forced kill of blockers before start." } }

  # Prefer Windows Service
  $svc = Get-Service -Name 'SurgeMail' -ErrorAction SilentlyContinue
  if ($svc) {
    try { Start-Service -Name 'SurgeMail' } catch {}
  }

  if ($Global:VERBOSE -eq 1) { & $Global:START_CMD } else { & $Global:START_CMD *> (Join-Path $env:TEMP 'surgemail-start.out') }
  if (Wait-ForReady 45) { Write-Host "Result: SurgeMail server started and is healthy." } else { Write-Host "Result: start issued, but not healthy within 45s. Check $Global:SURGEMAIL_DIR\logs." }
}

function cmd_restart([string[]]$Args) {
  $FORCE = ($Args -contains '--force')
  $Global:VERBOSE = ($Args -contains '--verbose') ? 1 : $Global:VERBOSE
  Require-Admin
  if (-not $Global:STOP_CMD -or -not $Global:START_CMD) { die "Start/Stop scripts missing in $Global:SURGEMAIL_DIR" }
  Write-Host "Requested: restart SurgeMail server (stop → start)."
  if (Test-SurgeMailReady) { Write-Host "Status before: running." } else { Write-Host "Status before: not running (or not healthy)." }
  cmd_stop @()
  if ($FORCE) { if (Stop-AllBlockers) { vlog "Forced kill of blocked ports before restart." } }
  if ($Global:VERBOSE -eq 1) { & $Global:START_CMD } else { & $Global:START_CMD *> (Join-Path $env:TEMP 'surgemail-restart.out') }
  if (Wait-ForReady 45) { Write-Host "Step 2/2: SurgeMail server started and healthy." } else { Write-Host "Step 2/2: start issued, but not healthy within 45s." }
}

function cmd_reload {
  Write-Host "Requested: reload SurgeMail server configuration."
  $t = Get-TellmailPath
  if ($t) {
    $out = Invoke-Tellmail @('reload')
    if ($LASTEXITCODE -eq 0 -or $out) { Write-Host "Result: configuration reload sent." } else { Write-Host "Result: 'tellmail reload' returned non-zero. Ensure server is running." }
  } else {
    Write-Host "Result: 'tellmail' not found in PATH. Cannot reload configuration."
  }
}

function cmd_status {
  Write-Host "Requested: status"
  $t = Get-TellmailPath
  if ($t) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $t; $psi.Arguments = 'status'
    $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    if ($p.ExitCode -ne 0) { Write-Host "Note: 'tellmail status' returned non-zero. Service may be down or unresponsive." }
    Write-Host $out
  } else {
    Write-Host "Result: 'tellmail' not found in PATH. Cannot query status."
  }
}

function cmd_version {
  Write-Host "Requested: version"
  $t = Get-TellmailPath
  if (-not $t) { Write-Host "Result: 'tellmail' not found in PATH. Cannot query SurgeMail server version."; return }
  $out = Invoke-Tellmail @('version')
  if (-not $out) { Write-Host "Result: 'tellmail version' produced no output."; return }
  Write-Host $out
  $m = [regex]::Match($out, '([0-9]+\.[0-9]+[A-Za-z])')
  if ($m.Success) { Write-Host "Installed SurgeMail server version (parsed): $($m.Groups[1].Value)" }
  Write-Host "SurgeMail Helper script: v$HELPER_VERSION"
}

function cmd_where {
  $script_path = Get-ScriptPath
  $helper_dir  = Split-Path -Parent (Split-Path -Parent $script_path)
  $smcmd = (Get-Command surgemail -ErrorAction SilentlyContinue)
  $tell  = (Get-TellmailPath) ?? '(not found)'
  $server_dir = $Global:SURGEMAIL_DIR
  Write-Host "helper directory           : $helper_dir"
  Write-Host "surgemail command          : $(if ($smcmd) { $smcmd.Source } else { '(not found)' }) (surgemail helper command)"
  Write-Host "tellmail path              : $tell"
  Write-Host "SurgeMail Server directory : $server_dir"
}

function cmd_diagnostics {
  Write-Host "=== SurgeMail Helper Diagnostics ==="
  Write-Host ("SurgeMail Helper version : v{0}" -f $HELPER_VERSION)
  Write-Host ("Script path    : {0}" -f (Get-ScriptPath))
  Write-Host ("Service name   : SurgeMail")
  $t = Get-TellmailPath
  Write-Host ("tellmail bin   : {0} (found: {1})" -f ($t ?? 'tellmail'), ([bool]$t))
  $svc = Get-Service -Name 'SurgeMail' -ErrorAction SilentlyContinue
  Write-Host ("Service mgr    : {0}" -f ($(if ($svc) {'WindowsService'} else {'direct'})))
  $running = (Test-SurgeMailReadyQuiet)
  Write-Host ("Running        : {0}" -f ($(if ($running) {'yes'} else {'no'})))
  Write-Host ("GH_OWNER/REPO  : {0} / {1}" -f $Global:GH_OWNER, $Global:GH_REPO)
}

# -------- self_check_update / self_update (helper) --------
function cmd_self_check_update([string[]]$Args) {
  $CHANNEL='release'; $AUTO=$false; $QUIET=$false; $TOKEN=''
  for ($i=0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      '--channel' { $CHANNEL = $Args[++$i] }
      '--auto'    { $AUTO = $true }
      '--quiet'   { $QUIET = $true }
      '--verbose' { $Global:VERBOSE = 1 }
      '--token'   { $TOKEN = $Args[++$i]; $Global:GH_TOKEN = $TOKEN }
      '-h' { Write-Host "Usage: surgemail self_check_update [--channel <release|prerelease|dev>] [--auto] [--quiet] [--token <gh_token>]"; return }
      default {}
    }
  }

  switch ($CHANNEL) {
    'dev' {
      $branch = GH-DefaultBranch
      if (-not $branch) { Write-Host "Could not determine default branch from GitHub."; return }
      if ($AUTO) { cmd_self_update @('--channel','dev'); return }
      $ans = Read-Host "Update to development branch '$branch' now? [y/N]"
      if ($ans -match '^(y|yes)$') { cmd_self_update @('--channel','dev') } else { if (-not $QUIET) { Write-Host "Ok, maybe next time. Exiting." } }
      return
    }
    default {
      $remote = if ($CHANNEL -eq 'prerelease') { GH-FirstPrereleaseTag } else { GH-LatestReleaseTag }
      if (-not $remote) { Write-Host "Could not determine latest helper version from GitHub."; return }
      $local = $HELPER_VERSION
      $cmp = Compare-SemVer $local $remote
      if ($cmp -ge 0) {
        if (-not $QUIET) { Write-Host "Already up to date ($remote) or local is newer ($local)." }
        return
      }
      if ($AUTO) { cmd_self_update @('--channel',$CHANNEL); return }
      $ans = Read-Host "Update from $local to '$remote' now? [y/N]"
      if ($ans -match '^(y|yes)$') { cmd_self_update @('--channel',$CHANNEL) } else { if (-not $QUIET) { Write-Host "Ok, maybe next time. Exiting." } }
    }
  }
}

function Expand-ZipOverlayToRoot($Url) {
  $root = Get-ProjectRoot
  $tmp  = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(),"surgemail-helper-zip-"+([System.Guid]::NewGuid()))) -Force
  $zip  = Join-Path $tmp.FullName 'update.zip'
  Invoke-HttpDownload $Url $zip
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $unpack = Join-Path $tmp.FullName 'unpack'
  New-Item -ItemType Directory -Path $unpack | Out-Null
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $unpack)
  $payload = Get-ChildItem $unpack | Where-Object { $_.PSIsContainer } | Select-Object -First 1
  if (-not $payload) { die "ZIP payload not found." }
  # Overlay files (excluding .git)
  $files = Get-ChildItem -Recurse -File $payload.FullName
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($payload.FullName.Length).TrimStart('\')
    if ($rel.StartsWith('.git')) { continue }
    $dest = Join-Path $root $rel
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Copy-Item -Path $f.FullName -Destination $dest -Force
  }
  Write-Host "Helper updated via ZIP overlay."
}

function cmd_self_update([string[]]$Args) {
  $CHANNEL='release'; $TOKEN=''
  for ($i=0; $i -lt $Args.Count; $i++) {
    switch ($Args[$i]) {
      '--channel' { $CHANNEL = $Args[++$i] }
      '--verbose' { $Global:VERBOSE = 1 }
      '--token'   { $TOKEN = $Args[++$i]; $Global:GH_TOKEN = $TOKEN }
      '-h' { Write-Host "Usage: surgemail self_update [--channel <release|prerelease|dev>] [--token <gh_token>]"; return }
      default {}
    }
  }

  $root = Get-ProjectRoot
  $isGit = Test-Path (Join-Path $root '.git')
  if ($CHANNEL -eq 'dev') {
    $branch = GH-DefaultBranch
    if (-not $branch) { Write-Host "Could not determine default branch."; return }
    if ($isGit -and (Test-Command 'git')) {
      Write-Host "Detected git checkout. Updating via git..."
      Push-Location $root
      try {
        git fetch origin $branch | Out-Null
        git checkout -q $branch
        git pull --ff-only origin $branch | Out-Null
        Write-Host "Helper updated via git to $branch."
      } catch {
        Write-Host "Git update failed; falling back to ZIP..."
        $url = "https://api.github.com/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)/zipball/$branch"
        Expand-ZipOverlayToRoot $url
      } finally { Pop-Location }
      return
    } else {
      Write-Host "No git checkout detected. Updating via ZIP..."
      $url = "https://api.github.com/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)/zipball/$branch"
      Expand-ZipOverlayToRoot $url
      return
    }
  }

  $tag = if ($CHANNEL -eq 'prerelease') { GH-FirstPrereleaseTag } else { GH-LatestReleaseTag }
  if (-not $tag) { Write-Host "Could not determine remote tag."; return }

  if ($isGit -and (Test-Command 'git')) {
    Write-Host "Detected git checkout. Updating via git..."
    Push-Location $root
    try {
      git fetch --tags origin | Out-Null
      $stashed = $false
      $dirty = $false
      try { git diff --quiet; git diff --cached --quiet } catch { $dirty = $true }
      if ($dirty) {
        Write-Host "Local changes detected; stashing..."
        git stash push -u -m "surgemail-helper auto-stash before update" | Out-Null
        $stashed = $true
      }
      try { git checkout -q "tags/$tag" } catch { git checkout -q "refs/tags/$tag" }
      Write-Host "Helper updated via git to $tag."
      if ($stashed) { Write-Host "Note: your local edits were stashed." }
    } catch {
      Write-Host "Git update failed; falling back to ZIP..."
      $url = "https://api.github.com/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)/zipball/$tag"
      Expand-ZipOverlayToRoot $url
    } finally { Pop-Location }
  } else {
    Write-Host "No git checkout detected. Updating via ZIP..."
    $url = "https://api.github.com/repos/$($Global:GH_OWNER)/$($Global:GH_REPO)/zipball/$tag"
    Expand-ZipOverlayToRoot $url
  }
}

function cmd_debug_gh([string[]]$Args) {
  Write-Host "=== GitHub Debug ==="
  Write-Host ("GH_OWNER       : {0}" -f $Global:GH_OWNER)
  Write-Host ("GH_REPO        : {0}" -f $Global:GH_REPO)
  Write-Host ("GH_API         : {0}" -f $Global:GH_API)
  Write-Host ("Token present  : {0}" -f ($(if ($Global:GH_TOKEN) {'yes'} else {'no'})))
  try {
    $branch = GH-DefaultBranch
    Write-Host ("Default branch : {0}" -f ($branch ?? '(unknown)'))
  } catch { Write-Host "Default branch : (error: $($_.Exception.Message))" }
  try {
    $latest = GH-LatestReleaseTag
    Write-Host ("Latest release : {0}" -f ($latest ?? '(unknown)'))
  } catch { Write-Host "Latest release : (error)" }
  try {
    $pre = GH-FirstPrereleaseTag
    Write-Host ("First prerelease tag : {0}" -f ($pre ?? '(none)'))
  } catch { Write-Host "First prerelease tag : (error)" }
  try {
    $rl = Invoke-HttpJson "$($Global:GH_API)/rate_limit"
    $core = $rl.resources.core
    Write-Host ("Rate limit     : {0}/{1} remaining; resets at {2}" -f $core.remaining, $core.limit, ([DateTime]::UnixEpoch.AddSeconds($core.reset).ToLocalTime()))
  } catch { Write-Host "Rate limit     : (unable to query)" }
}

# --------------- Router ---------------
function Invoke-Main {
  param([string[]]$argv)
  if (-not $argv -or $argv.Count -eq 0) { Show-MainHelp; return }

  $cmd = $argv[0]
  $rest = @()
  if ($argv.Count -gt 1) { $rest = $argv[1..($argv.Count-1)] }

  switch ($cmd) {
    'debug-gh' { cmd_debug_gh $rest }
    '-u' { cmd_update $rest }
    'update' { cmd_update $rest }
    'check-update' { cmd_check_update $rest }
    'self_check_update' { cmd_self_check_update $rest }
    'self_update' { cmd_self_update $rest }
    'stop' { cmd_stop $rest }
    'start' { cmd_start $rest }
    'restart' { cmd_restart $rest }
    '-r' { cmd_reload }
    'reload' { cmd_reload }
    '-s' { cmd_status }
    'status' { cmd_status }
    '-v' { cmd_version }
    'version' { cmd_version }
    '-w' { cmd_where }
    'where' { cmd_where }
    '-d' { cmd_diagnostics }
    'diagnostics' { cmd_diagnostics }
    '-h' { Show-MainHelp }
    '--help' { Show-MainHelp }
    'man' { Show-MainHelp }
    default {
      Write-Host "Unknown command: $cmd`n"
      Show-MainHelp
      exit 1
    }
  }
}

# Entry
Invoke-Main $args
