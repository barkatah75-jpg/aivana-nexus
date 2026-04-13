# === AIVANA AutoPilot v8.0 — AutoSync + AutoFolder Create ===
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Security

$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpHost = "ftp://ftp.todolist.barkataiautomation.in"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$siteURL = "https://todolist.barkataiautomation.in"
$authFile = "C:\Users\LAPPYHUB\AIVANA_AuthCache.enc"
$keyFile = "C:\Users\LAPPYHUB\AIVANA_AES.key"

# === Encryption Helpers ===
function Encrypt-Text($plain, $key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.GenerateIV()
    $enc = $aes.CreateEncryptor().TransformFinalBlock([System.Text.Encoding]::UTF8.GetBytes($plain),0,$plain.Length)
    [Convert]::ToBase64String($aes.IV + $enc)
}
function Decrypt-Text($encText, $key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $data = [Convert]::FromBase64String($encText)
    $aes.Key = $key; $aes.IV = $data[0..15]
    [System.Text.Encoding]::UTF8.GetString($aes.CreateDecryptor().TransformFinalBlock($data,16,$data.Length-16))
}

# === Load AES Key ===
if (!(Test-Path $keyFile)) {
    $key = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($key)
    [IO.File]::WriteAllBytes($keyFile, $key)
} else { $key = [IO.File]::ReadAllBytes($keyFile) }

# === Load or ask FTP password ===
if (Test-Path $authFile) {
    $ftpPass = Decrypt-Text (Get-Content $authFile -Raw) $key
} else {
    $win = New-Object System.Windows.Window
    $win.Title = "FTP Login"; $win.Width = 360; $win.Height = 160
    $grid = New-Object System.Windows.Controls.Grid
    $lbl = New-Object System.Windows.Controls.Label; $lbl.Content = "Enter FTP Password:"
    $pwd = New-Object System.Windows.Controls.PasswordBox; $pwd.Margin = "0,30,0,0"
    $btn = New-Object System.Windows.Controls.Button; $btn.Content = "OK"; $btn.Margin = "0,70,0,0"
    $btn.Add_Click({ $win.Tag = $pwd.Password; $win.Close() })
    $grid.Children.Add($lbl); $grid.Children.Add($pwd); $grid.Children.Add($btn)
    $win.Content = $grid; $win.ShowDialog() | Out-Null
    $ftpPass = $win.Tag
    if (-not $ftpPass) { Write-Host "❌ No password entered. Exiting." -ForegroundColor Red; exit }
    Set-Content -Path $authFile -Value (Encrypt-Text $ftpPass $key)
    Write-Host "🔐 Password saved securely."
}

# === Folder Create Function ===
function New-FTPFolder($uri, $user, $pass) {
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
        $req.UseBinary = $true; $req.UsePassive = $true; $req.EnableSsl = $false
        $req.GetResponse() | Out-Null
        Write-Host "📂 Created folder: $uri"
    } catch { }
}

# === Upload Function (with folder auto-create) ===
function Upload-All {
    Write-Host "`n=== Starting AutoDeploy ===" -ForegroundColor Cyan
    if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
    Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
    Write-Host "📦 ZIP created." -ForegroundColor Green

    $files = Get-ChildItem $sourceDir -Recurse -File
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceDir.Length + 1).Replace("\", "/")
        $uri = "$ftpHost/$relative"
        $folderUri = "$ftpHost/" + ($relative.Substring(0, $relative.LastIndexOf("/")))
        if ($relative -match "/") { New-FTPFolder $folderUri $ftpUser $ftpPass }
        try {
            $req = [System.Net.FtpWebRequest]::Create($uri)
            $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
            $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
            $req.UseBinary = $true; $req.UsePassive = $true; $req.EnableSsl = $false
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $stream = $req.GetRequestStream(); $stream.Write($bytes,0,$bytes.Length); $stream.Close()
            Write-Host "✅ Uploaded: $relative"
        } catch {
            Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    try {
        $resp = (Invoke-WebRequest $siteURL -UseBasicParsing -TimeoutSec 10).StatusCode
        if ($resp -eq 200) { Write-Host "🎯 Site LIVE!" -ForegroundColor Green }
    } catch { Write-Host "⚠️ Verify failed." -ForegroundColor Yellow }

    if (Test-Path $zipFile) { Remove-Item $zipFile -Force; Write-Host "🧹 Cleaned temp files" -ForegroundColor Gray }
    Write-Host "✅ AutoDeploy Complete!" -ForegroundColor Cyan
}

# === Initial Deploy + Watcher ===
Upload-All

$watcher = New-Object IO.FileSystemWatcher $sourceDir -Property @{
    IncludeSubdirectories = $true
    NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, DirectoryName'
}
$action = {
    Write-Host "`n⚡ Change detected, auto-syncing..." -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    Upload-All
}
Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null
Register-ObjectEvent $watcher Deleted -Action $action | Out-Null
Write-Host "`n🛰️  AIVANA AutoSync is LIVE — watching folder: $sourceDir" -ForegroundColor Magenta
while ($true) { Start-Sleep -Seconds 2 }
