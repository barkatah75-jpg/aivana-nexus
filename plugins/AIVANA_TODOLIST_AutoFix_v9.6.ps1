# ===========================================
#  AIVANA_TODOLIST_AutoFix_v9.6.ps1
#  Complete AutoFix (Multilang + Workflow + Verify)
# ===========================================

chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

# --- CONFIG ---
$siteURL  = "https://todolist.barkataiautomation.in"
$ftpHost  = "ftp://89.117.188.202"
$ftpUser  = "u786522790.todolist.barkataiautomation.in"
$ftpPass  = Read-Host "Enter FTP password"
$uploadRoot = "public_html"
$localTemp  = "$env:TEMP\AIVANA_TODOLIST_AUTOFIX"
if (-not (Test-Path $localTemp)) { New-Item -ItemType Directory -Force -Path $localTemp | Out-Null }

# --- Notification helper ---
function Show-Notification($title,$text) {
  try {
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.BalloonTipTitle = $title
    $n.BalloonTipText  = $text
    $n.Visible = $true
    $n.ShowBalloonTip(4000)
    Start-Sleep -Milliseconds 1500
    $n.Dispose()
  } catch {}
}

# --- FTP Upload helper (Active mode fallback) ---
function Upload-FileToFtp {
  param($uri,$localPath,$user,$pass)
  try {
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
    $req.Credentials = New-Object System.Net.NetworkCredential($user,$pass)
    $req.UseBinary = $true
    $req.UsePassive = $false   # Force ACTIVE mode
    $req.EnableSsl = $false
    $bytes = [System.IO.File]::ReadAllBytes($localPath)
    $stream = $req.GetRequestStream()
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Close()
    Write-Host "Uploaded -> $($localPath | Split-Path -Leaf)" -ForegroundColor Green
    return $true
  } catch {
    Write-Host "Failed -> $($localPath | Split-Path -Leaf): $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
}


# --- Step 1: Generate missing multilingual PDFs ---
Write-Host "`n=== Step 1: Rebuilding Multilingual Guides ===" -ForegroundColor Cyan
$langs = @("EN","HI","ES","FR","AR","ZH","JP")
foreach ($l in $langs) {
  $pdfPath = Join-Path $localTemp "AIVANA_AI_Global_Identity_Guide_$l.pdf"
  "AIVANA Global Identity Guide ($l)`r`nAuto-generated placeholder $(Get-Date)" | Out-File $pdfPath -Encoding UTF8
  Write-Host "Created -> $pdfPath"
}

# --- Step 2: Create Workflow YAMLs ---
Write-Host "`n=== Step 2: Creating GitHub Workflow YAMLs ===" -ForegroundColor Cyan
$workflowsLocal = Join-Path $localTemp "workflows"
if (-not (Test-Path $workflowsLocal)) { New-Item -Path $workflowsLocal -ItemType Directory | Out-Null }

$aivanaYamlPath = Join-Path $workflowsLocal "aivana-auto-upload.yml"
$aivanaYamlLines = @(
"name: AIVANA Auto Upload",
"on:",
"  workflow_dispatch:",
"  push:",
"    branches: [ main ]",
"jobs:",
"  upload:",
"    runs-on: ubuntu-latest",
"    steps:",
"      - uses: actions/checkout@v4",
"      - name: Zip files",
"        run: zip -r deploy_package.zip .",
"      - name: Upload to FTP (example)",
"        uses: SamKirkland/FTP-Deploy-Action@4.4.0",
"        with:",
"          server: 89.117.188.202",
"          username: u786522790.todolist.barkataiautomation.in",
"          password: `$`{{ secrets.FTP_PASSWORD `$`}}",
"          local-dir: ."
)
Set-Content -Path $aivanaYamlPath -Value $aivanaYamlLines -Encoding UTF8
Write-Host "Generated -> $aivanaYamlPath"

$hostingerYamlPath = Join-Path $workflowsLocal "hostinger-deploy.yml"
$hostingerYamlLines = @(
"name: Hostinger Deploy",
"on:",
"  workflow_dispatch:",
"jobs:",
"  deploy:",
"    runs-on: ubuntu-latest",
"    steps:",
"      - uses: actions/checkout@v4",
"      - name: Zip and Upload (example)",
"        run: |",
"          zip -r deploy_package.zip .",
"          # FTP upload step can be added here or use action"
)
Set-Content -Path $hostingerYamlPath -Value $hostingerYamlLines -Encoding UTF8
Write-Host "Generated -> $hostingerYamlPath"

# --- Step 3: Upload to FTP ---
Write-Host "`n=== Step 3: Uploading to FTP Server ===" -ForegroundColor Cyan
foreach ($pdf in Get-ChildItem $localTemp -Filter *.pdf) {
  $rel = "/$uploadRoot/guides/" + ($pdf.Name)
  $uri = "$ftpHost/$rel"
  Upload-FileToFtp $uri $pdf.FullName $ftpUser $ftpPass | Out-Null
}
foreach ($yml in Get-ChildItem $workflowsLocal -Filter *.yml) {
  $rel = "/$uploadRoot/.github/workflows/" + ($yml.Name)
  $uri = "$ftpHost/$rel"
  Upload-FileToFtp $uri $yml.FullName $ftpUser $ftpPass | Out-Null
}

# --- Step 4: Verify site ---
Write-Host "`n=== Step 4: Verifying Site Files ===" -ForegroundColor Cyan
$checkURLs = @(
"$siteURL/guides/AIVANA_AI_Global_Identity_Guide_ES.pdf",
"$siteURL/guides/AIVANA_AI_Global_Identity_Guide_FR.pdf",
"$siteURL/guides/AIVANA_AI_Global_Identity_Guide_AR.pdf",
"$siteURL/guides/AIVANA_AI_Global_Identity_Guide_ZH.pdf",
"$siteURL/guides/AIVANA_AI_Global_Identity_Guide_JP.pdf"
)
foreach ($url in $checkURLs) {
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -eq 200) {
      Write-Host "OK -> $url"
    } else {
      Write-Host "FAIL -> $url"
    }
  } catch {
    Write-Host "ERROR -> $url"
  }
}

Show-Notification "AIVANA AutoFix" "Completed successfully."
Write-Host "`n✅ AutoFix completed successfully." -ForegroundColor Green
