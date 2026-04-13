# ===================================================================
# 🌐 AIVANA AutoPilot v9.3 - Secure SFTP + Telegram AlertMode (AutoRepair)
# 🔒 AES Encryption for Telegram & SFTP Credentials
# 🧠 Author: Barkat AIVANA | Date: 2025
# ===================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

# === CONFIG ===
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$sftpHost  = "todolist.barkataiautomation.in"    # hostname only, no sftp://
$sftpPort  = 22
$sftpUser  = "u786522790.todolist.barkataiautomation.in"
$siteURL   = "https://todolist.barkataiautomation.in"

# === SECURITY FILES ===
$keyFile   = "$env:USERPROFILE\AIVANA_AES.key"
$authFile  = "$env:USERPROFILE\AIVANA_TelegramAuth.enc"
$sftpCred  = "$env:USERPROFILE\AIVANA_SFTPAuth.enc"

# === AES FUNCTIONS ===
function New-AesKeyIfMissing {
    param($path)
    if (-not (Test-Path $path)) {
        $b = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
        [IO.File]::WriteAllBytes($path, $b)
    }
    return [IO.File]::ReadAllBytes($path)
}
function Encrypt-Text([string]$plain, [byte[]]$key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.GenerateIV()
    $enc = $aes.CreateEncryptor().TransformFinalBlock(
        [System.Text.Encoding]::UTF8.GetBytes($plain),0,$plain.Length)
    return [Convert]::ToBase64String($aes.IV + $enc)
}
function Decrypt-Text([string]$encText, [byte[]]$key) {
    $data = [Convert]::FromBase64String($encText)
    $aes  = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.IV = $data[0..15]
    $dec = $aes.CreateDecryptor().TransformFinalBlock($data,16,$data.Length-16)
    return [System.Text.Encoding]::UTF8.GetString($dec)
}

# === NOTIFICATION ===
function Show-Notification {
    param([string]$title,[string]$text)
    try {
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.BalloonTipTitle = $title; $n.BalloonTipText = $text
        $n.Visible = $true; $n.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 1500; $n.Dispose()
    } catch {}
}

# === TELEGRAM ===
function Send-Telegram {
    param($token,$chatId,$msg)
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" `
            -Method Post -Body @{chat_id=$chatId;text=$msg} -TimeoutSec 15 | Out-Null
        return $true
    } catch { return $false }
}

# === LOAD TELEGRAM CREDS ===
$key = New-AesKeyIfMissing -path $keyFile
if (Test-Path $authFile) {
    try {
        $json = Decrypt-Text (Get-Content $authFile -Raw) $key | ConvertFrom-Json
        $botToken=$json.token; $chatId=$json.chatid
    } catch {}
}
if (-not $botToken -or -not $chatId) {
    $botToken = Read-Host "Enter Telegram Bot Token"
    $chatId   = Read-Host "Enter Chat ID"
    $enc = Encrypt-Text (@{token=$botToken;chatid=$chatId}|ConvertTo-Json -Compress) $key
    Set-Content $authFile $enc
}

# === LOAD SFTP CREDS (AUTOREPAIR) ===
function Get-SftpPassword {
    if (Test-Path $sftpCred) {
        try { return (Decrypt-Text (Get-Content $sftpCred -Raw) $key | ConvertFrom-Json).pass }
        catch {}
    }
    $pw = Read-Host "Enter your SFTP password"
    $enc = Encrypt-Text (@{pass=$pw}|ConvertTo-Json -Compress) $key
    Set-Content $sftpCred $enc
    return $pw
}
$sftpPass = Get-SftpPassword

# === LOAD SSH.NET LIBRARY ===
Add-Type -Path "$PSScriptRoot\Renci.SshNet.dll" -ErrorAction SilentlyContinue
if (-not ("Renci.SshNet.SftpClient" -as [type])) {
    Write-Host "Downloading SSH.NET library..."
    $zipUrl="https://github.com/sshnet/SSH.NET/releases/download/v2020.0.1/SSH.NET-2020.0.1.zip"
    $tmp="$env:TEMP\sshnet.zip"
    Invoke-WebRequest -Uri $zipUrl -OutFile $tmp -UseBasicParsing
    Expand-Archive $tmp "$env:TEMP\sshnet" -Force
    $dllPath = (Get-ChildItem "$env:TEMP\sshnet" -Recurse -Filter "Renci.SshNet.dll" | Select-Object -First 1).FullName
    Add-Type -Path $dllPath
}

# === MAIN DEPLOY ===
try {
    Write-Host "`n=== 🚀 AIVANA AutoDeploy (Secure SFTP) ===" -ForegroundColor Cyan
    Show-Notification "AIVANA" "AutoDeploy शुरू हुआ"
    Send-Telegram $botToken $chatId "🚀 Deploy शुरू हुआ $(Get-Date)"

    $zip="$env:USERPROFILE\deploy_package.zip"
    if(Test-Path $zip){Remove-Item $zip -Force}
    Compress-Archive -Path "$sourceDir\*" -DestinationPath $zip -Force
    Write-Host "ZIP तैयार -> $zip"

    $client = New-Object Renci.SshNet.SftpClient($sftpHost,$sftpPort,$sftpUser,$sftpPass)
    try { $client.Connect() }
    catch {
        Write-Host "❌ Login failed – AutoRepair triggered"
        Remove-Item $sftpCred -Force -ErrorAction SilentlyContinue
        $sftpPass = Get-SftpPassword
        $client = New-Object Renci.SshNet.SftpClient($sftpHost,$sftpPort,$sftpUser,$sftpPass)
        $client.Connect()
    }

    Write-Host "SFTP Login OK ✅"
    Send-Telegram $botToken $chatId "SFTP login सफल ✅"

    $files = Get-ChildItem $sourceDir -Recurse -File
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($sourceDir.Length+1).Replace('\','/')
        $remote = "/public_html/$rel"
        $dir = Split-Path $remote
        if (-not $client.Exists($dir)) { $client.CreateDirectory($dir) }
        $fs = [System.IO.File]::OpenRead($f.FullName)
        $client.UploadFile($fs,$remote,$true)
        $fs.Close()
        Write-Host "✅ Uploaded: $rel"
    }

    $client.Disconnect()
    Send-Telegram $botToken $chatId "✅ Deploy सफल – साइट देखें $siteURL"
    Show-Notification "AIVANA" "Deploy सफल!"
}
catch {
    Send-Telegram $botToken $chatId "💥 Error: $($_.Exception.Message)"
    Show-Notification "AIVANA" "Deploy Error"
}
