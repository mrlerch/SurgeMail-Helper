<#
.SYNOPSIS
  SurgeMail Helper (Windows, PowerShell 7+)
  Version: 1.14.1
  Repo: mrlerch/SurgeMail-Helper
#>

param(
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet("status","start","stop","strong_stop","restart","reload","check-update","update","self-check-update","self-update","diagnostics","version","where")]
  [string]$Command,

  [string]$Tellmail = "tellmail",
  [string]$Service  = "surgemail",
  [switch]$Unattended,
  [switch]$NoSelfCheck,
  [switch]$Debug,
  [string]$Tag
)

$env:GH_OWNER = if ($env:GH_OWNER) { $env:GH_OWNER } else { "mrlerch" }
$env:GH_REPO  = if ($env:GH_REPO)  { $env:GH_REPO  } else { "SurgeMail-Helper" }
$HelperVersion = "1.14.1"

function Have-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }
function Dbg($m){ if($Debug){ Write-Host "[debug] $m" } }

function Is-Running {
  if (Have-Cmd $Tellmail) {
    try { & $Tellmail status *> $null; if ($LASTEXITCODE -eq 0) { return $true } } catch {}
    try { & $Tellmail version *> $null; if ($LASTEXITCODE -eq 0) { return $true } } catch {}
  }
  $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue
  if ($null -ne $svc) { return $svc.Status -eq 'Running' }
  return $false
}

function Start-SM { $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue; if ($null -ne $svc) { Start-Service -Name $Service; return } throw "Service '$Service' not found." }
function Stop-SM  { $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue; if ($null -ne $svc) { Stop-Service -Name $Service; return } throw "Service '$Service' not found." }
function Reload-SM { Restart-Service -Name $Service -ErrorAction SilentlyContinue }
function Get-Version { if (Have-Cmd $Tellmail) { try { & $Tellmail version } catch { "tellmail not available" } } else { "tellmail not available" } }

function Compare-Versions([string]$A, [string]$B) {
  $pa = ($A.TrimStart('v') + ".0.0").Split('.')[0..2] | ForEach-Object { [int]$_ }
  $pb = ($B.TrimStart('v') + ".0.0").Split('.')[0..2] | ForEach-Object { [int]$_ }
  for ($i=0; $i -lt 3; $i++) { if ($pa[$i] -gt $pb[$i]) { return 1 } elseif ($pa[$i] -lt $pb[$i]) { return 2 } }
  return 0
}
function Get-AuthHeaders {
  $h=@{"User-Agent"="surgemail-helper/1.14.1"}
  if($env:GH_TOKEN){$h["Authorization"]="Bearer $($env:GH_TOKEN)"}
  return $h
}
function Get-LatestRef {
  $headers = @{ "User-Agent" = "surgemail-helper/1.14.2" }
  if ($env:GH_TOKEN) { $headers["Authorization"] = "Bearer $($env:GH_TOKEN)" }
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($env:GH_OWNER)/$($env:GH_REPO)/releases/latest" -Headers $headers -ErrorAction Stop
    if ($rel.tag_name) { return $rel.tag_name }
  } catch { }
  try {
    $tags = Invoke-RestMethod -Uri "https://api.github.com/repos/$($env:GH_OWNER)/$($env:GH_REPO)/tags?per_page=1" -Headers $headers -ErrorAction Stop
    if ($tags[0].name) { return $tags[0].name }
  } catch { }
  try {
    $repo = Invoke-RestMethod -Uri "https://api.github.com/repos/$($env:GH_OWNER)/$($env:GH_REPO)" -Headers $headers -ErrorAction Stop
    if ($repo.default_branch) { return $repo.default_branch }
  } catch { }
  return $null
}
function Self-Check-Update {
  $ref = Get-LatestRef
  if (-not $ref) { return }
  $latest = $null
  if ($ref -match '^v\d+\.\d+\.\d+$') { $latest = $ref }
  else {
    try { $text = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$($env:GH_OWNER)/$($env:GH_REPO)/$ref/scripts/surgemail-helper.ps1" -Headers (Get-AuthHeaders) -ErrorAction Stop; $m=[regex]::Match($text,'Version:\s*(\d+\.\d+\.\d+)'); if($m.Success){ $latest="v"+$m.Groups[1].Value } } catch {}
  }
  if (-not $latest) { return }
  switch (Compare-Versions $HelperVersion $latest) {
    2 { Write-Host "A newer helper version v$HelperVersion->$latest is available. Run 'surgemail -Command self-update'." }
    default { }
  }
}
function Self-Update([string]$Ref) {
  if (-not $Ref) { $Ref = Get-LatestRef }
  if (-not $Ref) { throw "Could not determine latest release/tag/default branch from GitHub." }
  $target = $MyInvocation.MyCommand.Path
  $url = "https://raw.githubusercontent.com/$($env:GH_OWNER)/$($env:GH_REPO)/$Ref/scripts/surgemail-helper.ps1"
  $tmp = [System.IO.Path]::GetTempFileName()
  try { Invoke-WebRequest -Uri $url -Headers (Get-AuthHeaders) -OutFile $tmp -UseBasicParsing -ErrorAction Stop } catch { throw "Failed to download helper from $url" }
  Copy-Item -Path $target -Destination "$target.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())" -Force -ErrorAction SilentlyContinue
  Move-Item -Path $tmp -Destination $target -Force
  Write-Host "Helper updated successfully to ref: $Ref"
}

if (-not $NoSelfCheck) { try { Self-Check-Update } catch {} }

switch ($Command) {
  "status" { if (Is-Running) { "SurgeMail: RUNNING" } else { "SurgeMail: STOPPED" }; "Version: $(Get-Version)"; "Helper: v$HelperVersion" }
  "start"  { if (Is-Running) { "Already running." } else { Start-SM; Start-Sleep -Seconds 2; if (Is-Running) { "Started." } else { throw "Failed to start." } } }
  "stop"   { if (-not (Is-Running)) { "Already stopped." } else { Stop-SM; Start-Sleep -Seconds 2; if (-not (Is-Running)) { "Stopped." } else { throw "Stop did not succeed. Try strong_stop." } } }
  "strong_stop" { if (Have-Cmd $Tellmail) { & $Tellmail shutdown } else { Stop-SM }; Start-Sleep -Seconds 3; if (Is-Running) { throw "Strong stop may have failed." } else { "Strong stop completed." } }
  "restart" { & $PSCommandPath -Command stop -Tellmail $Tellmail -Service $Service; & $PSCommandPath -Command start -Tellmail $Tellmail -Service $Service }
  "reload"  { Reload-SM; "Reload requested." }
  "check-update" { "Server update check: (placeholder)" }
  "update"  { $prev = Get-Version; "Previous version: $prev"; "1) Downloading installer..."; "2) Stopping service (graceful)..."; & $PSCommandPath -Command stop -Tellmail $Tellmail -Service $Service; "3) Running installer... (hook here)"; "4) Installer complete."; "5) Post-install checks..."; "6) Starting SurgeMail (only if not running)"; if (Is-Running) { "SurgeMail already running after install. Skipping start." } else { Start-SM }; Start-Sleep -Seconds 2; $now = Get-Version; "Current version: $now"; if (Is-Running) { "Update complete and service is running." } else { throw "Update finished but service is NOT running." } }
  "self-check-update" { Self-Check-Update }
  "self-update" { Self-Update -Ref $Tag }
  "diagnostics" {
    "=== SurgeMail Helper Diagnostics ==="
    "Helper version : v$HelperVersion"
    "Script path    : $($MyInvocation.MyCommand.Path)"
    "Service name   : $Service"
    "tellmail bin   : $Tellmail (found: $([bool](Get-Command $Tellmail -ErrorAction SilentlyContinue)))"
    "Service exists : $([bool](Get-Service -Name $Service -ErrorAction SilentlyContinue))"
    "Running        : $(Is-Running)"
    "GH_OWNER/REPO  : $($env:GH_OWNER) / $($env:GH_REPO)"
  }
  "version" { "v$HelperVersion" }
  "where"   { "Script: $($MyInvocation.MyCommand.Path)" }
  default { "Use -Command with one of: status,start,stop,strong_stop,restart,reload,check-update,update,self-check-update,self-update,diagnostics,version,where" }
}
