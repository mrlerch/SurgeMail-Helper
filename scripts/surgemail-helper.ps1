<#
.SYNOPSIS
  SurgeMail Helper (Windows, PowerShell)
  Version: 1.14.10
#>

param(
  [Parameter(Position=0)]
  [string]$Command = "help",
  [string]$Tellmail = "tellmail",
  [string]$Service  = "surgemail",
  [switch]$Unattended,
  [string]$Tag
)

$HelperVersion = "1.14.10"

function Have-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }
function Get-HelperScript { return $MyInvocation.MyCommand.Path }
function Get-HelperBase   { return (Split-Path (Split-Path (Get-HelperScript) -Parent) -Parent) }
function Is-GitCheckout  { Test-Path -LiteralPath (Join-Path (Get-HelperBase) '.git') }

function Map-ShortFlags([string]$cmd) {
  switch ($cmd) {
    "-s" { return "status" }
    "-r" { return "reload" }
    "-u" { return "update" }
    "-d" { return "diagnostics" }
    "-v" { return "version" }
    "-w" { return "where" }
    "-h" { return "help" }
    default { return $cmd }
  }
}
$Command = Map-ShortFlags $Command

# ---- GitHub helpers (self update/check) ----
function Auth-Headers { param([string]$Token)
  $ua = "surgemail-helper/1.14.10"
  if ([string]::IsNullOrWhiteSpace($Token)) { return @{ "User-Agent" = $ua } }
  else { return @{ "User-Agent" = $ua; "Authorization" = "Bearer $Token" } }
}
function Get-LatestRef {
  param([string]$Owner = "mrlerch", [string]$Repo = "SurgeMail-Helper")
  $h = Auth-Headers $env:GH_TOKEN
  try {
    $rel = Invoke-WebRequest -UseBasicParsing -Headers $h -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest" | ConvertFrom-Json
    if ($rel.tag_name) { return $rel.tag_name }
  } catch { }
  try {
    $tags = Invoke-WebRequest -UseBasicParsing -Headers $h -Uri "https://api.github.com/repos/$Owner/$Repo/tags?per_page=1" | ConvertFrom-Json
    if ($tags[0].name) { return $tags[0].name }
  } catch { }
  try {
    $repo = Invoke-WebRequest -UseBasicParsing -Headers $h -Uri "https://api.github.com/repos/$Owner/$Repo" | ConvertFrom-Json
    if ($repo.default_branch) { return $repo.default_branch }
  } catch { }
  return $null
}
function Compare-VersionSemver([string]$A, [string]$B) {
  $a = $A.TrimStart('v').Split('.'); $b = $B.TrimStart('v').Split('.')
  for ($i=0; $i -lt 3; $i++) {
    $ai = [int]($a[$i] | ForEach-Object { if ($_ -eq $null) {0} else {$_} })
    $bi = [int]($b[$i] | ForEach-Object { if ($_ -eq $null) {0} else {$_} })
    if ($ai -gt $bi) { return 1 }
    if ($ai -lt $bi) { return 2 }
  }
  return 0
}
function Download-And-OverlayZip([string]$Ref, [string]$Owner="mrlerch", [string]$Repo="SurgeMail-Helper") {
  $base = Get-HelperBase
  $tmp = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) -Name ("smh_"+[System.Guid]::NewGuid().ToString()) -Force
  $zip = Join-Path $tmp "pkg.zip"
  $url = "https://github.com/$Owner/$Repo/archive/refs/heads/$Ref.zip"
  if ($Ref -match "^v\d+\.\d+\.\d+$") { $url = "https://github.com/$Owner/$Repo/archive/refs/tags/$Ref.zip" }
  Invoke-WebRequest -UseBasicParsing -Headers (Auth-Headers $env:GH_TOKEN) -Uri $url -OutFile $zip
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $extract = Join-Path $tmp "x"
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
  $inner = Get-ChildItem $extract | Where-Object {$_.PSIsContainer} | Select-Object -First 1
  if (-not $inner) { throw "ZIP inner folder not found" }
  Copy-Item -Path (Join-Path $inner.FullName '*') -Destination $base -Recurse -Force
  Write-Output "Helper updated from ZIP to $Ref"
}
function Self-Check-Update { 
  param([string]$Owner="mrlerch",[string]$Repo="SurgeMail-Helper")
  $ref = Get-LatestRef -Owner $Owner -Repo $Repo
  if (-not $ref) { "Could not determine latest helper version from GitHub."; return }
  $target = $ref
  if ($ref -notmatch "^v\d+\.\d+\.\d+$") {
    try {
      $raw = Invoke-WebRequest -UseBasicParsing -Headers (Auth-Headers $env:GH_TOKEN) -Uri "https://raw.githubusercontent.com/$Owner/$Repo/$ref/scripts/surgemail-helper.ps1" | Select-Object -ExpandProperty Content
      $m = [regex]::Match($raw, 'HelperVersion\s*=\s*"(\d+\.\d+\.\d+)"')
      if ($m.Success) { $target = "v" + $m.Groups[1].Value }
    } catch { }
  }
  if (-not $target) { $target = "v0.0.0" }
  $cmp = Compare-VersionSemver ("v" + $HelperVersion) $target
  if ($cmp -eq 2) {
    "You are running SurgeMail Helper script v$HelperVersion. The latest version is $target."
    $ans = Read-Host "Would you like to upgrade? y/n"
    if ($ans -match '^(y|Y)') { Self-Update -Ref $target -Owner $Owner -Repo $Repo }
    else { "Ok, maybe next time. Thanks for using SurgeMail Helper." }
  } else {
    "You are running the latest SurgeMail Helper script version v$HelperVersion"
  }
}
function Self-Update {
  param([string]$Ref,[string]$Owner="mrlerch",[string]$Repo="SurgeMail-Helper")
  if (-not $Ref) { $Ref = Get-LatestRef -Owner $Owner -Repo $Repo }
  if (-not $Ref) { throw "Could not determine latest release/tag/default branch from GitHub." }
  $target = $Ref
  if ($Ref -notmatch "^v\d+\.\d+\.\d+$") {
    try {
      $raw = Invoke-WebRequest -UseBasicParsing -Headers (Auth-Headers $env:GH_TOKEN) -Uri "https://raw.githubusercontent.com/$Owner/$Repo/$Ref/scripts/surgemail-helper.ps1" | Select-Object -ExpandProperty Content
      $m = [regex]::Match($raw, 'HelperVersion\s*=\s*"(\d+\.\d+\.\d+)"')
      if ($m.Success) { $target = "v" + $m.Groups[1].Value }
    } catch { }
  }
  $cmp = Compare-VersionSemver $target ("v" + $HelperVersion)
  if ($cmp -eq 2) {
    $ans = Read-Host "The requested target ($target) is older than current (v$HelperVersion). Do you want to downgrade? y/n"
    if ($ans -notmatch '^(y|Y)') { "Aborting downgrade."; return }
  }
  if (Is-GitCheckout) {
    Push-Location (Get-HelperBase)
    try {
      git fetch --tags | Out-Null
      git checkout $Ref | Out-Null
      git pull --ff-only | Out-Null
      "Helper updated via git to $Ref"
    } finally { Pop-Location }
  } else {
    Download-And-OverlayZip -Ref $Ref -Owner $Owner -Repo $Repo
  }
}

function Show-Help {
@"
Usage: surgemail <command> [options]

Short flags:
  -s status, -r reload, -u update, -d diagnostics, -v version, -w where, -h help

Commands:
  status             Show SurgeMail status (tellmail status)
  start              Start service
  stop               Stop service
  restart            Stop then start
  reload             Reload configuration (tellmail reload)
  update             Update server (call Unix helper for full flow)
  check-update       Check if newer server exists (Unix helper has full flow)
  version            Show version (tellmail version + helper)
  where              Show helper dir / surgemail command / tellmail path / server dir
  diagnostics        Show diagnostics
  self_check_update  Check helper script update (GitHub)
  self_update        Update helper script (GitHub)
  help               Show this help
"@
}

function Cmd-Status { if (Have-Cmd $Tellmail) { & $Tellmail status } else { "tellmail not found" } }
function Cmd-Reload { if (Have-Cmd $Tellmail) { & $Tellmail reload; "SurgMail server configurations reloaded." } else { "SurgMail server configurations reload failed. SurgeMail server not running." } }
function Cmd-Version { if (Have-Cmd $Tellmail) { & $Tellmail version }; "SurgeMail Helper script: v$HelperVersion" }
function Cmd-Where {
  $scriptPath = (Get-HelperScript)
  $bin = (Get-Command surgemail -ErrorAction SilentlyContinue)
  $smcmd = "(not found)"
  if ($bin) { $smcmd = $bin.Source }
  $tell = (Get-Command $Tellmail -ErrorAction SilentlyContinue)
  $tellPath = if ($tell) { $tell.Source } else { "(not found)" }
  $serverDir = "/usr/local/surgemail"
  "helper directory           : " + (Get-HelperBase)
  "surgemail command          : " + $smcmd + " (surgemail helper command)"
  "tellmail path              : " + $tellPath
  "SurgeMail Server directory : " + $serverDir
}
function Cmd-Diagnostics {
  "=== SurgeMail Helper Diagnostics ==="
  "Helper version : v$HelperVersion"
  "Script path    : " + (Get-HelperScript)
  "Service name   : surgemail"
  if (Have-Cmd $Tellmail) { "tellmail bin   : $Tellmail (found: yes)" } else { "tellmail bin   : $Tellmail (found: no)" }
  $mgr = "direct"; if (Have-Cmd "sc.exe") { $mgr = "sc" }
  "Service mgr    : $mgr"
}

switch ($Command) {
  "status" { Cmd-Status }
  "reload" { Cmd-Reload }
  "version" { Cmd-Version }
  "where"  { Cmd-Where }
  "diagnostics" { Cmd-Diagnostics }
  "self_check_update" { Self-Check-Update }
  "self_update" { Self-Update }
  "help" { Show-Help }
  default { Show-Help }
}
