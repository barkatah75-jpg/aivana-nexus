# === AIVANA AutoPilot v7.6 — No-Prompt AutoDeploy (AES Encryption) ===
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Security

# === Paths and Config ===
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$uploadDir = "public_html"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpHost = "ftp://ftp.todolist.barkataiautomation.in"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$siteURL = "https://todolist.barkataiautomation.in"
$authFile = "C:\Users\LAPPYHUB\AIVANA_AuthCache.enc"

function Encrypt-Text($plain, $key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.GenerateIV()
    $encryptor = $aes.CreateEncryptor()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
    $enc = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    return [Convert]::ToBase64String($aes.IV + $enc)
}

function Decrypt-Text($encText, $key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $data = [Convert]::FromBase64String($encText)
    $aes.Key = $key
    $aes.IV = $data[0..15]
    $decryptor = $aes.CreateDecryptor()
    $dec = $decryptor.TransformFinalBlock($data, 16, $data.Length - 16)
    return [System.Text.Encoding]::UTF8.GetString($dec)
}

# AES Key (Auto-generated fixed key per PC)
$keyFile = "C:\Users\LAPPYHUB\AIVANA_AES.key"
if (!(Test-Path $keyFile)) {
    $key = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($key)
    [IO.File]::WriteAllBytes($keyFile, $key)
} else {
    $key = [IO.File]::ReadAllBytes($keyFile)
}

# Get FTP Password (either from encrypted cache or new input)
if (Test-Path $authFile) {
    $encPass = Get-Content $authFile -Raw
    $ftpPass = Decrypt-Text $encPass $key
} else {
    # Ask password GUI
    $Window = New-Object System.Windows.Window
    $Window.Title = "Enter FTP Password"
    $Window.Height = 160
    $Window.Width = 360
    $Window.WindowStartupLocation = "CenterScreen"
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
    $grid.Children.Add($lbl); $grid.Children.Add($pwd); $grid.Children.Add($btn)
    $Window.Content = $grid
    $Window.ShowDialog() | Out-Null
    $ftpPass = $Window.Tag
    if (-not $ftpPass) { Write-Host "❌ No password entered. Exiting." -ForegroundColor Red; exit }
    $encPass = Encrypt-Text $ftpPass $key
    Set-Content -Path $authFile -Value $encPass
    Write-Host "🔐 Password saved securely (AES-encrypted)."
}

Write-Host "`n=== Starting AIVANA Auto Deploy ===" -ForegroundColor Cyan
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
Write-Host "📦 ZIP created." -ForegroundColor Green

$files = Get-ChildItem $sourceDir -Recurse -File
foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourceDir.Length + 1).Replace("\", "/")
    $uri = "$ftpHost/$uploadDir/$relative"
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
        $req.UseBinary = $true; $req.UsePassive = $true; $req.EnableSsl = $false
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $stream = $req.GetRequestStream(); $stream.Write($bytes, 0, $bytes.Length); $stream.Close()
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
