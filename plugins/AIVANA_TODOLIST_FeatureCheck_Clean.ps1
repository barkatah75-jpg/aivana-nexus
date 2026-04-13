# AIVANA TODOLIST Feature Check (clean ASCII mode)
$siteURL = "https://todolist.barkataiautomation.in"

$assets = @(
    "/assets/app_icon_128.webp",
    "/assets/logo_48.webp",
    "/favicons/favicon-32.webp",
    "/guides/AIVANA_AI_Global_Identity_Guide_English.pdf",
    "/guides/AIVANA_AI_Global_Identity_Guide_Hindi.pdf"
)

Write-Host ""
Write-Host "=== Checking TODOLIST Feature Integrity ===" -ForegroundColor Cyan

# Test 1: Luxury Brand Pack
$brandOK = $true
foreach ($a in $assets) {
    try {
        $r = Invoke-WebRequest -Uri ($siteURL + $a) -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) {
            Write-Host "OK  - $a"
        } else {
            Write-Host "FAIL - $a"
            $brandOK = $false
        }
    } catch {
        Write-Host "ERROR - $a"
        $brandOK = $false
    }
}
if ($brandOK) { Write-Host "[PASS] Luxury Brand Pack OK" -ForegroundColor Green }
else { Write-Host "[FAIL] Luxury Brand Pack incomplete" -ForegroundColor Red }

# Test 2: Multilingual Guides
$langs = @("EN","HI","ES","FR","AR","ZH","JP")
$multiOK = $true
foreach ($l in $langs) {
    $url = "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf"
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) {
            Write-Host "OK  - Guide $l"
        } else {
            Write-Host "FAIL - Guide $l"
            $multiOK = $false
        }
    } catch {
        Write-Host "ERROR - Guide $l"
        $multiOK = $false
    }
}
if ($multiOK) { Write-Host "[PASS] Multilingual Guides OK" -ForegroundColor Green }
else { Write-Host "[FAIL] Some multilingual guides missing" -ForegroundColor Red }

# Test 3: Automation Readiness
$autoOK = $false
try {
    $r = Invoke-WebRequest -Uri "$siteURL/.github/workflows/hostinger-deploy.yml" -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -eq 200) {
        Write-Host "OK  - hostinger-deploy.yml found"
        $autoOK = $true
    }
} catch {}
try {
    $r = Invoke-WebRequest -Uri "$siteURL/.github/workflows/aivana-auto-upload.yml" -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -eq 200) {
        Write-Host "OK  - aivana-auto-upload.yml found"
        $autoOK = $true
    }
} catch {}

if ($autoOK) { Write-Host "[PASS] Automation scripts present" -ForegroundColor Green }
else { Write-Host "[FAIL] Automation scripts missing" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Yellow
if ($brandOK -and $multiOK -and $autoOK) {
    Write-Host "All TODOLIST features working properly" -ForegroundColor Green
} else {
    Write-Host "Some features missing or broken" -ForegroundColor Red
}
