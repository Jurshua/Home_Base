# Installs the Home Base helper on Windows so the hub can sleep or shut this PC down.
# Run in PowerShell opened as Administrator (needed for the firewall rule):
#   powershell -ExecutionPolicy Bypass -File install-agent-windows.ps1
# Needs Python 3.9+ (winget install Python.Python.3.12). Prints the token to put in the hub's hub.toml.
$ErrorActionPreference = "Stop"

$py = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
if (-not $py) { throw "Python isn't installed. Run: winget install Python.Python.3.12, then run this again." }
$data = Join-Path $env:APPDATA "HomeBase"
New-Item -ItemType Directory -Force -Path $data | Out-Null
Copy-Item (Join-Path $PSScriptRoot "homebase_agent.py") (Join-Path $data "homebase_agent.py") -Force
$script = Join-Path $data "homebase_agent.py"

# Start at logon and keep running; replace any older copy of the task.
$action = New-ScheduledTaskAction -Execute $py -Argument "`"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit 0
Unregister-ScheduledTask -TaskName "Home Base helper" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "Home Base helper" -Action $action -Trigger $trigger -Settings $settings | Out-Null
Start-ScheduledTask -TaskName "Home Base helper"

# Let the hub reach port 4901 on the home network only.
if (-not (Get-NetFirewallRule -DisplayName "Home Base helper" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "Home Base helper" -Direction Inbound -Protocol TCP -LocalPort 4901 -Profile Private -Action Allow | Out-Null
}

Write-Host "Helper running on port 4901. Token for hub.toml:"
& ($py -replace "pythonw.exe$", "python.exe") $script --token
