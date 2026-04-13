# ============================================
# AIVANA AutoStart Script (Full Automation Edition)
# ============================================

Write-Host "🔍 Searching for AuroraFusion package..." -ForegroundColor Cyan

# ZIP filename and paths
$zipName = "AuroraFusion_v5.3_FullEngine_AutoGUI_AutoStart_Fixed.zip"
$srcPath = "$env:USERPROFILE\Downloads\$zipName"
$extractRoot = "C:\AIVANA"
$destPath = Join-Path $extractRoot "AuroraFusion_v5.3_FullEngine_AutoGUI"

# 1️⃣ Find ZIP in Downloads
if (Test-Path $srcPath) {
    Write-Host "✅ Found ZIP in Downloads: $srcPath" -ForegroundColor Green

    # 2️⃣ Create C:\AIVANA if not exist
    if (!(Test-Path $extractRoot)) {
        Write-Host "📁 Creating folder: $extractRoot"
        New-Item -Path "C:\" -Name "AIVANA" -ItemType Directory | Out-Null
    }

    # 3️⃣ Extract ZIP to C:\AIVANA
    Write-Host "📦 Extracting package..."
    try {
        Expand-Archive -Path $srcPath -DestinationPath $extractRoot -Force
        Write-Host "✅ Extracted to: $destPath" -ForegroundColor Cyan
    } catch {
        Write-Host "⚠️ Extraction failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    # 4️⃣ Launch run.ps1 if found
    $runScript = Join-Path $destPath "run.ps1"
    if (Test-Path $runScript) {
        Write-Host "🚀 Launching AuroraFusion System..."
        Set-Location $destPath
        Set-ExecutionPolicy Bypass -Scope Process -Force
        & $runScript
    } else {
        Write-Host "⚠️ run.ps1 not found inside extracted folder." -ForegroundColor Yellow
    }
}
else {
    Write-Host "❌ ZIP not found in Downloads. Please ensure it's there." -ForegroundColor Yellow
    Write-Host "📦 Expected file: $srcPath"
}

Write-Host "`n✨ AutoStart sequence complete."
