<#
.SYNOPSIS
  SurgeMail Helper (Windows, PowerShell)
  Version: 1.14.6
  Repo: mrlerch/SurgeMail-Helper
#>

param(
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet("status","start","stop","strong_stop","restart","reload","check_update","update","self_check_update","self_update","diagnostics","version","where")]
  [string]$Command,

  [string]$Tellmail = "tellmail",
  [string]$Service  = "surgemail",
  [switch]$Unattended,
  [string]$Tag
)

$env:GH_OWNER = if ($env:GH_OWNER) { $env:GH_OWNER } else { "mrlerch" }
$env:GH_REPO  = if ($env:GH_REPO)  { $env:GH_REPO  } else { "SurgeMail-Helper" }
$HelperVersion = "1.14.6"

function Have-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }
function Get-AuthHeaders { $h=@{'User-Agent'='surgemail-helper/1.14.6'}; if($env:GH_TOKEN){ $h['Authorization']="Bearer $($env:GH_TOKEN)" }; $h }

function Status-Running {
  if (Have-Cmd $Tellmail) {
    try { $out=& $Tellmail status 2>&1; if ($out -match '^SurgeMail Version \d+\.\d+[a-z]') { return $true }; if ($out -match 'Bad Open Response') { return $false } } catch { }
  }
  $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue
  if ($svc) { return $svc.Status -eq 'Running' } else { return $false }
}

function Start-SM {
  $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue
  if ($svc) { Start-Service -Name $Service } else { & "C:\usr\local\surgemail\surgemail_start.bat" 2>$null }
  Start-Sleep -s 1
  if (-not (Status-Running)) { throw "Failed to start." }
}
function Stop-SM {
  if (Have-Cmd $Tellmail) { try { & $Tellmail shutdown } catch { } }
  else { $svc=Get-Service -Name $Service -ErrorAction SilentlyContinue; if($svc){ Stop-Service -Name $Service } }
  Start-Sleep -s 1
  if (Status-Running) { throw "Stop did not fully succeed." }
}
function Reload-SM {
  if (Have-Cmd $Tellmail) { try { & $Tellmail reload } catch { }; "SurgMail server configurations reloaded." }
  else { "SurgMail server configurations reload failed. SurgeMail server not running." }
}

function Get-VersionText {
  if (Have-Cmd $Tellmail) { try { & $Tellmail version } catch { "tellmail not available" } } else { "tellmail not available" }
  "Helper: v$HelperVersion"
}

function Where-Info {
  $scriptPath = $MyInvocation.MyCommand.Path
  $bin = (Get-Command surgemail -ErrorAction SilentlyContinue)
  if ($bin) { "surgemail binary : " + $bin.Source } else { "surgemail binary : (not found)" }
  "helper script    : $scriptPath"
}

switch ($Command) {
  "status" { if (Have-Cmd $Tellmail) { & $Tellmail status } else { if(Status-Running){"SurgeMail: RUNNING"} else {"SurgeMail: STOPPED"} } }
  "start"  { Start-SM; "Started." }
  "stop"   { Stop-SM; "Stopped." }
  "strong_stop" { Stop-SM; "Strong stop completed." }
  "restart" { Stop-SM; Start-SM; "Restarted." }
  "reload" { Reload-SM }
  "version" { Get-VersionText }
  "where"  { Where-Info }
  "diagnostics" { "Helper: v$HelperVersion"; "GH_OWNER/REPO: $($env:GH_OWNER)/$($env:GH_REPO)"; "Service: $Service"; }
  "check_update" { "Use Unix helper for server update check logic"; }
  "update" { "Run Unix-side update flow or implement Windows-specific installer"; }
  "self_check_update" { "Use Unix helper for interactive update"; }
  "self_update" { "Use Unix helper for interactive update"; }
}
