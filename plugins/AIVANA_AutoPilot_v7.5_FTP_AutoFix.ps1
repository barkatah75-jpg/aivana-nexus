# === AIVANA AutoPilot v7.5 — Final FTP + Password Fix ===
Add-Type -AssemblyName PresentationFramework

# === Settings ===
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$uploadDir = "public_html"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpHost = "ftp.todolist.barkataiautomation.in"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$siteURL = "https://todolist.barkataiautomation.in"

# === Ask Password with WPF Dialog (no VisualBasic dependency) ===
Add-Type -AssemblyName PresentationFramework
$Window = New-Object System.Windows.Window
$Window.Title = "FTP Login"
$Window.Height = 160
$Window.Width = 360
$Window.WindowStartupLocation = "CenterScreen"
$Window.Content = {
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = '20'
    $lbl = New-Object System.Windows.Controls.Label
    $lbl.Content = "Enter FTP Password:"
    $pwd = New-Object System.Windows.Controls.PasswordBox
    $pwd.Margin = '0,30,0,0'
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = "OK"
    $btn.Margin = '0,70,0,0'
    $btn.Add_Click({ $Window.Tag = $pwd.Password; $Window.Close() })
    $grid.Children.Add($lbl)
    $grid.Children.Add($pwd)
    $grid.Children.Add($btn)
    $grid
}.Invoke()
$Window.ShowDialog() | Out-Null
$ftpPass = $Window.Tag

if (-not $ftpPass) { Write-Host "❌ No password entered. Exiting." -ForegroundColor Red; exit }

Write-Host "`n=== Starting AIVANA Auto Deploy ===" -ForegroundColor Cyan
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
Write-Host "📦 ZIP created." -ForegroundColor Green

$files = Get-ChildItem $sourceDir -Recurse -File
foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceDir.Length + 1).Replace("\", "/")
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
