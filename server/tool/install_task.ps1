<#
.SYNOPSIS
Builds the dashboard server and starts it every time you log on to Windows.

.DESCRIPTION
Compiles bin/server.dart to server/ai_dashboard_server.exe and registers the
"AiDashboardServer" Task Scheduler task, which runs it hidden at log on as the
current user (the agent CLIs need your profile and their logins). Output goes
to server/server.log. Rerun after pulling changes to rebuild and restart.

Remove it with:  Unregister-ScheduledTask -TaskName AiDashboardServer
#>
param(
    [string]$Dart = "$env:USERPROFILE\flutter\bin\cache\dart-sdk\bin\dart.exe"
)

$ErrorActionPreference = 'Stop'
$taskName = 'AiDashboardServer'
$server = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $server 'ai_dashboard_server.exe'
$log = Join-Path $server 'server.log'

if (-not (Test-Path (Join-Path $server 'config.json'))) {
    throw "Create $server\config.json first (copy config.example.json)."
}

# The running exe is locked, so stop it before rebuilding.
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Get-Process ai_dashboard_server -ErrorAction SilentlyContinue | Stop-Process -Force

& $Dart pub get --directory $server
if ($LASTEXITCODE) { throw 'dart pub get failed.' }
& $Dart compile exe (Join-Path $server 'bin\server.dart') -o $exe
if ($LASTEXITCODE) { throw 'dart compile failed.' }

$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"& '$exe' --log '$log'`"" `
    -WorkingDirectory $server
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Force `
    -Description 'Agent dashboard server: drives the agent CLIs for the phone app.' | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host "Started $taskName. Log: $log"
Write-Host "Expose it on your tailnet with:  tailscale serve --bg 8787"
