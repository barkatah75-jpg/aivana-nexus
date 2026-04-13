# ======================================================
# 🧠 AIVANA TODOLIST Feature Auto-Check (v1.0)
# Checks: Brand Pack, Multilingual, Automation Readiness
# ======================================================

$siteURL = "https://todolist.barkataiautomation.in"
$assets = @(
    "/assets/app_icon_128.webp",
    "/assets/logo_48.webp",
    "/favicons/favicon-32.webp",
    "/guides/AIVANA_AI_Global_Identity_Guide_English.pdf",
    "/guides/AIVANA_AI_Global_Identity_Guide_Hindi.pdf"
)

Write-Host "`n=== 🔍 Checking TODOLIST Feature Integrity ===" -ForegroundColor Cyan

# --- Test 1: Luxury Brand Pack ---
$brandPass = $true
foreach ($a in $assets) {
    try {
        $r = Invoke-WebRequest -Uri ($siteURL + $a) -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) {
            Write-Host "✅ Found: $a"
        } else {
            Write-Host "⚠️ Missing or error: $a"
            $brandPass = $false
        }
    } catch {
        Write-Host "❌ Not accessible: $a"
        $brandPass = $false
    }
}

if ($brandPass) { Write-Host "🏆 Luxury Brand Pack ✅ OK" -ForegroundColor Green }
else { Write-Host "💥 Luxury Brand Pack ❌ FAIL" -ForegroundColor Red }

# --- Test 2: Multilingual Guides ---
$langs = @("EN","HI","ES","FR","AR","ZH","JP")
$mlPass = $true
foreach ($l in $langs) {
    try {
        $r = Invoke-WebRequest -Uri "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf" -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) {
            Write-Host "🌐 $l → Available"
        } else {
            Write-Host "⚠️ $l → Not found"
            $mlPass = $false
        }
    } catch {
        Write-Host "❌ $l → Not accessible"
        $mlPass = $false
    }
}
if ($mlPass) { Write-Host "🈺 Multilingual Guides ✅ OK" -ForegroundColor Green }
else { Write-Host "💥 Multilingual Guides ❌ FAIL" -ForegroundColor Red }

# --- Test 3: Automation Readiness ---
$autoPass = $false
try {
    $r = Invoke-WebRequest -Uri "$siteURL/.github/workflows/aivana-auto-upload.yml" -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -eq 200) {
        Write-Host "⚙️ Auto-upload script found."
        $autoPass = $true
    }
} catch {}
try {
    $r = Invoke-WebRequest -Uri "$siteURL/.github/workflows/hostinger-deploy.yml" -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -eq 200) {
        Write-Host "🧩 Hostinger deploy script found."
        $autoPass = $true
    }
} catch {}

if ($autoPass) { Write-Host "🤖 Automation Scripts ✅ Ready" -ForegroundColor Green }
else { Write-Host "💥 Automation Scripts ❌ Missing" -ForegroundColor Red }

# --- Summary ---
Write-Host "`n=== 📊 Summary ===" -ForegroundColor Yellow
if ($brandPass -and $mlPass -and $autoPass) {
    Write-Host "🎯 TODOLIST Platform Fully Functional ✅"
} else {
    Write-Host "⚠️ Some features missing or broken ❌"
}
