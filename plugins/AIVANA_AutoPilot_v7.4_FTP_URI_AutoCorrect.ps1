# === AIVANA AutoPilot v7.4 — FTP URI AutoCorrect ===
Add-Type -AssemblyName PresentationFramework
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$uploadDir = "public_html"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpHost = "ftp.todolist.barkataiautomation.in"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpPass = [Microsoft.VisualBasic.Interaction]::InputBox("Enter FTP Password:", "FTP Login", "")
$siteURL = "https://todolist.barkataiautomation.in"

Write-Host "`n=== Starting AIVANA Auto Deploy ===" -ForegroundColor Cyan
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
Write-Host "📦 ZIP created." -ForegroundColor Green

$files = Get-ChildItem $sourceDir -Recurse -File
foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceDir.Length + 1).Replace("\", "/")
    # ✅ Ensure valid FTP URL
    $baseHost = if ($ftpHost -match '^ftp://') { $ftpHost.TrimEnd('/') } else { "ftp://$ftpHost" }
    $uri = "$baseHost/$uploadDir/$relative"
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
        $req.UseBinary = $true; $req.UsePassive = $true; $req.EnableSsl = $false
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        Write-Host "✅ Uploaded: $relative"
    } catch {
        Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n🌐 Verifying website..."
try {
    $resp = (Invoke-WebRequest $siteURL -UseBasicParsing -TimeoutSec 10).StatusCode
    if ($resp -eq 200) { Write-Host "🎯 Site LIVE!" -ForegroundColor Green } else { Write-Host "⚠️ HTTP $resp" }
} catch { Write-Host "❌ Verify failed." -ForegroundColor Red }

if (Test-Path $zipFile) { Remove-Item $zipFile -Force; Write-Host "🧹 Cleaned temp files" -ForegroundColor Gray }
Write-Host "✅ AIVANA Auto Deploy Complete!" -ForegroundColor Cyan
