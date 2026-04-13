# AIVANA System Auto-Repair Script (v1.2 Clean ASCII)
# Fixes Node.js, npm, PATH, PowerShell ExecutionPolicy, and VSCode Terminal
# Author: AIVANA Federation / Aurora System

Write-Host "`nStarting AIVANA Auto Repair..." -ForegroundColor Cyan

# Step 1 — Allow PowerShell scripts temporarily
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Step 2 — Stop any old Node or npm processes
Write-Host "Cleaning old Node/npm processes..."
Stop-Process -Name "node" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "npm" -Force -ErrorAction SilentlyContinue

# Step 3 — Clear old Node.js and npm cache
Write-Host "Removing old Node.js and npm cache..." -ForegroundColor Yellow
Remove-Item -Recurse -Force "$env:AppData\npm" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:AppData\npm-cache" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "C:\Program Files\nodejs" -ErrorAction SilentlyContinue

# Step 4 — Clear Chocolatey cache (optional cleanup)
Remove-Item -Recurse -Force "C:\ProgramData\chocolatey\lib\nodejs*" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "C:\ProgramData\chocolatey\lib-bad" -ErrorAction SilentlyContinue

# Step 5 — Reinstall Node.js (LTS)
Write-Host "Installing Node.js (LTS) via Chocolatey..."
choco install nodejs-lts -y --force | Out-Null

# Step 6 — Verify installation
Write-Host "`nVerifying Node.js installation..."
node -v
npm -v
npx -v

# Step 7 — Fix PATH variable
Write-Host "Fixing PATH..."
$nodePath = "C:\Program Files\nodejs"
if (-Not ($env:Path -like "*$nodePath*")) {
    [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$nodePath", [EnvironmentVariableTarget]::Machine)
    Write-Host "PATH updated for Node.js"
}

# Step 8 — Fix VS Code terminal default to PowerShell
$settingsPath = "$env:APPDATA\Code\User\settings.json"
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw
    if ($settings -notmatch '"terminal.integrated.defaultProfile.windows"') {
        Add-Content $settingsPath ', "terminal.integrated.defaultProfile.windows": "PowerShell"'
        Write-Host "VS Code terminal default set to PowerShell"
    }
}

# Step 9 — Final message
Write-Host "`nRepair complete! Please close and reopen PowerShell or VS Code." -ForegroundColor Green
Write-Host "Then run:  cd C:\Users\LAPPYHUB\aurora-dashboard" -ForegroundColor Cyan
Write-Host "And start your app with: npm start" -ForegroundColor Cyan

Write-Host "`nAIVANA Auto-Heal Engine ready - Aurora Dashboard will now run cleanly." -ForegroundColor Magenta
