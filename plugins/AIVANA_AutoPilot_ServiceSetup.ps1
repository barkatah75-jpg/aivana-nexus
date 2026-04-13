# === AIVANA AutoPilot Service Setup (v9.0) ===
$serviceName = "AIVANA_AutoPilot_Service"
$serviceDisplay = "AIVANA AutoPilot Background Service"
$serviceScript = "C:\Users\LAPPYHUB\AIVANA_AutoPilot_v9.0_ServiceMode.ps1"
$logFile = "C:\Users\LAPPYHUB\AIVANA_DeployLogs\ServiceSetup.txt"

if (!(Test-Path $serviceScript)) {
    Write-Host "❌ Service core script not found at $serviceScript" -ForegroundColor Red
    exit
}

Write-Host "`n=== Installing AIVANA AutoPilot as Windows Service ===" -ForegroundColor Cyan

# Remove old service if exists
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Write-Host "⚙️ Removing old service..."
    sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 3
}

# Create wrapper script that launches in background
$launcher = "C:\Users\LAPPYHUB\AIVANA_ServiceLauncher.bat"
@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$serviceScript"
"@ | Out-File $launcher -Encoding ASCII

# Register service via NSSM (if available) or fallback using schtasks
$nssm = "C:\Windows\System32\nssm.exe"
if (Test-Path $nssm) {
    Write-Host "🧠 Installing using NSSM..."
    & $nssm install $serviceName "cmd.exe" "/c $launcher"
    & $nssm set $serviceName DisplayName "$serviceDisplay"
    & $nssm set $serviceName Start SERVICE_AUTO_START
    & $nssm start $serviceName
} else {
    Write-Host "⚡ NSSM not found — using Task Scheduler fallback."
    $taskName = "AIVANA AutoPilot Background"
    schtasks /Delete /TN "$taskName" /F > $null 2>&1
    schtasks /Create /SC ONLOGON /TN "$taskName" /TR "cmd /c start $launcher" /RL HIGHEST /F
    Write-Host "✅ Task Scheduler service created successfully."
}

Write-Host "✅ AIVANA AutoPilot Service setup complete."
"$(Get-Date -Format 'HH:mm:ss') - Service installed" | Out-File $logFile -Append
Write-Host "🛰️ Background service will auto-start on next Windows boot." -ForegroundColor Green
