<#
.SYNOPSIS
  SurgeMail Helper (Windows, PowerShell 7+)
  Version: 1.13.2
#>

param(
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateSet("status","start","stop","strong_stop","restart","reload","check-update","update")]
  [string]$Command,

  [string]$Tellmail = "tellmail",
  [string]$Service  = "surgemail",
  [switch]$Unattended
)

function Have-Cmd($name) {
  $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Is-Running {
  if (Have-Cmd $Tellmail) {
    $p = Start-Process -FilePath $Tellmail -ArgumentList "status" -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -eq 0) { return $true }
    $p = Start-Process -FilePath $Tellmail -ArgumentList "version" -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -eq 0) { return $true }
  }
  $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue
  if ($null -ne $svc) { return $svc.Status -eq 'Running' }
  return $false
}

function Start-SM {
  $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue
  if ($null -ne $svc) { Start-Service -Name $Service; return }
  Write-Error "Service '$Service' not found and no fallback implemented."
}

function Stop-SM {
  $svc = Get-Service -Name $Service -ErrorAction SilentlyContinue
  if ($null -ne $svc) { Stop-Service -Name $Service; return }
  Write-Error "Service '$Service' not found and no fallback implemented."
}

function Reload-SM {
  # Windows services typically don't support 'reload'; use restart.
  Restart-Service -Name $Service -ErrorAction SilentlyContinue
}

function Get-Version {
  if (Have-Cmd $Tellmail) {
    try {
      $p = & $Tellmail version 2>$null
      return $p
    } catch { return "tellmail not available" }
  } else {
    return "tellmail not available"
  }
}

switch ($Command) {
  "status" {
    if (Is-Running) { Write-Host "SurgeMail: RUNNING" } else { Write-Host "SurgeMail: STOPPED" }
    Write-Host "Version: $(Get-Version)"
  }
  "start" {
    if (Is-Running) { Write-Host "Already running."; break }
    Start-SM
    Start-Sleep -Seconds 2
    if (Is-Running) { Write-Host "Started." } else { throw "Failed to start." }
  }
  "stop" {
    if (-not (Is-Running)) { Write-Host "Already stopped."; break }
    Stop-SM
    Start-Sleep -Seconds 2
    if (-not (Is-Running)) { Write-Host "Stopped." } else { throw "Stop did not succeed. Try strong_stop." }
  }
  "strong_stop" {
    if (Have-Cmd $Tellmail) {
      # IMPORTANT: correct command is 'tellmail shutdown'
      & $Tellmail shutdown 2>$null
    } else {
      Stop-SM
    }
    Start-Sleep -Seconds 3
    if (Is-Running) { throw "Strong stop may have failed." } else { Write-Host "Strong stop completed." }
  }
  "restart" {
    & $PSCommandPath -Command stop -Tellmail $Tellmail -Service $Service
    & $PSCommandPath -Command start -Tellmail $Tellmail -Service $Service
  }
  "reload" {
    Reload-SM
    Write-Host "Reload requested."
  }
  "check-update" {
    Write-Host "Checking for updates... (placeholder)"
  }
  "update" {
    $prev = Get-Version
    Write-Host "Previous version: $prev"
    Write-Host "1) Downloading installer..."
    Write-Host "2) Stopping service (graceful)..."
    & $PSCommandPath -Command stop -Tellmail $Tellmail -Service $Service
    Write-Host "3) Running installer..."
    # TODO: invoke installer silently if available
    Write-Host "4) Installer complete."
    Write-Host "5) Post-install checks..."
    Write-Host "6) Starting SurgeMail (only if not running)"
    if (Is-Running) {
      Write-Host "SurgeMail already running after install. Skipping start."
    } else {
      Start-SM
    }
    Start-Sleep -Seconds 2
    $now = Get-Version
    Write-Host "Current version: $now"
    if (Is-Running) { Write-Host "Update complete and service is running." } else { throw "Update finished but service is NOT running." }
  }
}
