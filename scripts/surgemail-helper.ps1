<#
.SYNOPSIS
  SurgeMail Helper (Windows, PowerShell)
  Version: 1.14.8
#>

param(
  [Parameter(Position=0)]
  [string]$Command = "help",
  [string]$Tellmail = "tellmail",
  [string]$Service  = "surgemail",
  [switch]$Unattended
)

$HelperVersion = "1.14.8"

function Have-Cmd($name) { $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

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

function Show-Help {
@"
Usage: surgemail <command> [options]

Short flags:
  -s status, -r reload, -u update, -d diagnostics, -v version, -w where, -h help

Commands:
  status           Show SurgeMail status (tellmail status)
  start            Start service
  stop             Stop service
  strong_stop      Stop (strong)
  restart          Stop then start
  reload           Reload configuration (tellmail reload)
  update           Update server (call Unix helper for full flow)
  check-update     Check if newer server exists (Unix helper has full flow)
  version          Show version (tellmail version + helper)
  where            Show helper script path and surgemail command
  diagnostics      Show diagnostics
  self_check_update  Check helper script update (GitHub)
  self_update        Update helper script (GitHub)
  help             Show this help
"@
}

function Cmd-Status { if (Have-Cmd $Tellmail) { & $Tellmail status } else { "tellmail not found" } }
function Cmd-Reload { if (Have-Cmd $Tellmail) { & $Tellmail reload; "SurgMail server configurations reloaded." } else { "SurgMail server configurations reload failed. SurgeMail server not running." } }
function Cmd-Version { if (Have-Cmd $Tellmail) { & $Tellmail version }; "Helper: v$HelperVersion" }
function Cmd-Where {
  $scriptPath = $MyInvocation.MyCommand.Path
  $bin = (Get-Command surgemail -ErrorAction SilentlyContinue)
  if ($bin) { "surgemail command : " + $bin.Source + " (surgemail helper command)" } else { "surgemail command : (not found)" }
  "helper script    : $scriptPath"
}
function Cmd-Diagnostics { "Helper: v$HelperVersion"; if (Have-Cmd $Tellmail) { "tellmail: present" } else { "tellmail: missing" } }

switch ($Command) {
  "status" { Cmd-Status }
  "reload" { Cmd-Reload }
  "version" { Cmd-Version }
  "where"  { Cmd-Where }
  "diagnostics" { Cmd-Diagnostics }
  "help" { Show-Help }
  default { Show-Help }
}
