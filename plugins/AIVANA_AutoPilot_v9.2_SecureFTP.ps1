# ===================================================================
# 🌐 AIVANA AutoPilot v9.2 - SecureFTP + Telegram AlertMode
# 🔒 Secure AES Encrypted Credentials (Telegram + FTP)
# 🧠 Author: Barkat AIVANA | Date: 2025
# 📁 Save As: C:\Users\LAPPYHUB\AIVANA_AutoPilot_v9.2_SecureFTP.ps1
# ===================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

# === 🔧 CONFIGURATION ===
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$ftpHost   = "ftp://ftp.todolist.barkataiautomation.in"
$ftpUser   = "u786522790.todolist.barkataiautomation.in"
$uploadRootGuess = "public_html"
$siteURL   = "https://todolist.barkataiautomation.in"

# === 🔐 SECURITY FILES ===
$keyFile   = "$env:USERPROFILE\AIVANA_AES.key"
$authFile  = "$env:USERPROFILE\AIVANA_TelegramAuth.enc"
$ftpCredFile = "$env:USERPROFILE\AIVANA_FTPAuth.enc"

# === 🧩 AES ENCRYPTION / DECRYPTION FUNCTIONS ===
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
    $aes.Key = $key
    $aes.GenerateIV()
    $enc = $aes.CreateEncryptor().TransformFinalBlock([System.Text.Encoding]::UTF8.GetBytes($plain),0,$plain.Length)
    return [Convert]::ToBase64String($aes.IV + $enc)
}
function Decrypt-Text([string]$encText, [byte[]]$key) {
    $data = [Convert]::FromBase64String($encText)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.IV = $data[0..15]
    $dec = $aes.CreateDecryptor().TransformFinalBlock($data,16,$data.Length-16)
    return [System.Text.Encoding]::UTF8.GetString($dec)
}

# === 🖥 SIMPLE TRAY NOTIFICATION ===
function Show-Notification {
    param([string]$title, [string]$text)
    try {
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.BalloonTipTitle = $title
        $notify.BalloonTipText  = $text
        $notify.Visible = $true
        $notify.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 1500
        $notify.Dispose()
    } catch { }
}

# === 📲 TELEGRAM MESSAGE FUNCTION ===
function Send-Telegram {
    param([string]$token,[string]$chatId,[string]$message)
    try {
        $url = "https://api.telegram.org/bot$token/sendMessage"
        $body = @{ chat_id = $chatId; text = $message }
        Invoke-RestMethod -Uri $url -Method Post -Body $body -TimeoutSec 15 | Out-Null
        return $true
    } catch { return $false }
}

# === 🔑 LOAD OR ASK FOR TELEGRAM CREDS ===
$key = New-AesKeyIfMissing -path $keyFile
if (Test-Path $authFile) {
    try {
        $enc = Get-Content $authFile -Raw
        $json = Decrypt-Text $enc $key | ConvertFrom-Json
        $botToken = $json.token
        $chatId   = $json.chatid
    } catch {
        Remove-Item $authFile -Force -ErrorAction SilentlyContinue
        Write-Host "Telegram credentials corrupted - कृपया दोबारा दर्ज करें।"
    }
}
if (-not $botToken -or -not $chatId) {
    Write-Host "Enter Telegram Bot Token:"
    $botToken = Read-Host "Bot Token"
    Write-Host "Enter your Chat ID:"
    $chatId = Read-Host "Chat ID"
    $obj = @{ token = $botToken; chatid = $chatId } | ConvertTo-Json -Compress
    $enc = Encrypt-Text $obj $key
    Set-Content -Path $authFile -Value $enc -Force
    Write-Host "Telegram credentials सुरक्षित रूप से सेव हो गए।"
}

# === 🔑 LOAD OR ASK FOR FTP CREDS (SECURE MODE) ===
if (Test-Path $ftpCredFile) {
    try {
        $enc = Get-Content $ftpCredFile -Raw
        $json = Decrypt-Text $enc $key | ConvertFrom-Json
        $ftpPass = $json.pass
    } catch {
        Remove-Item $ftpCredFile -Force -ErrorAction SilentlyContinue
        Write-Host "FTP credentials corrupted - कृपया दोबारा दर्ज करें।"
    }
}
if (-not $ftpPass) {
    Write-Host "Enter your FTP password:"
    $plainPass = Read-Host "FTP Password"
    $obj = @{ pass = $plainPass } | ConvertTo-Json -Compress
    $enc = Encrypt-Text $obj $key
    Set-Content -Path $ftpCredFile -Value $enc -Force
    Write-Host "FTP password सुरक्षित रूप से सेव हो गया।"
}

# === 🌐 FTP HELPER FUNCTIONS ===
function Test-FTP-Root {
    param($ftpHost, $user, $pass)
    try {
        $req = [System.Net.FtpWebRequest]::Create($ftpHost.TrimEnd('/') + '/')
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
        $req.UsePassive = $true; $req.UseBinary = $true; $req.EnableSsl = $false
        $req.GetResponse().Close()
        return $true
    } catch { return $false }
}
function New-FtpFolder {
    param($folderUri, $user, $pass)
    try {
        $req = [System.Net.FtpWebRequest]::Create($folderUri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
        $req.UsePassive = $true; $req.UseBinary = $true; $req.EnableSsl = $false
        $req.GetResponse() | Out-Null
        return $true
    } catch { return $false }
}
function Upload-FileToFtp {
    param($uri, $localPath, $user, $pass)
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
        $req.UseBinary = $true; $req.UsePassive = $true; $req.EnableSsl = $false
        $bytes = [System.IO.File]::ReadAllBytes($localPath)
        $stream = $req.GetRequestStream()
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Close()
        return $true
    } catch {
        return $_.Exception.Message
    }
}

# === 🚀 MAIN DEPLOYMENT ===
try {
    Write-Host "`n=== 🚀 AIVANA AutoDeploy (Telegram + SecureFTP) ===" -ForegroundColor Cyan
    Show-Notification "AIVANA" "AutoDeploy शुरू हुआ"
    Send-Telegram $botToken $chatId "🚀 Deploy शुरू हुआ - $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"

    # ZIP बनाएँ
    $zipPath = "$env:USERPROFILE\deploy_package.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path $sourceDir) {
        Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipPath -Force
        Write-Host "ZIP तैयार -> $zipPath"
    } else {
        throw "❌ Source directory नहीं मिला: $sourceDir"
    }

    # FTP टेस्ट करें
    $rootOk = Test-FTP-Root -ftpHost $ftpHost -user $ftpUser -pass $ftpPass
    if ($rootOk) { Write-Host "FTP Root OK ✅" } else { Write-Host "FTP Root नहीं मिला; /public_html कोशिश करेंगे ⚠️" }

    # फाइल अपलोड लूप
    $files = Get-ChildItem $sourceDir -Recurse -File
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($sourceDir.Length+1).Replace('\','/')
        $uriBase = if ($rootOk) { $ftpHost.TrimEnd('/') } else { "$ftpHost/$uploadRootGuess" }
        $fullUri = "$uriBase/$rel"

        # फ़ोल्डर बनाएँ (यदि जरूरी हो)
        if ($rel -match "/") {
            $folderPath = $rel.Substring(0, $rel.LastIndexOf('/'))
            $folderUri = "$uriBase/$folderPath"
            New-FtpFolder -folderUri $folderUri -user $ftpUser -pass $ftpPass | Out-Null
        }

        $res = Upload-FileToFtp -uri $fullUri -localPath $f.FullName -user $ftpUser -pass $ftpPass
        if ($res -eq $true) {
            Write-Host "✅ Uploaded: $rel"
        } else {
            Write-Host "❌ Failed: $rel -> $res" -ForegroundColor Red
            Send-Telegram $botToken $chatId "❌ Upload failed: $rel -> $res"
        }
    }

    # साइट चेक करें
    try {
        $r = Invoke-WebRequest -Uri $siteURL -UseBasicParsing -TimeoutSec 15
        if ($r.StatusCode -eq 200) {
            Write-Host "🌐 साइट उपलब्ध (HTTP 200)" -ForegroundColor Green
            Send-Telegram $botToken $chatId "✅ Deploy सफल - साइट पहुंच योग्य है।"
            Show-Notification "AIVANA" "Deploy सफल!"
        } else {
            Write-Host "⚠️ साइट ने HTTP $($r.StatusCode) रिटर्न किया" -ForegroundColor Yellow
            Send-Telegram $botToken $chatId "⚠️ Deploy हुआ लेकिन साइट ने HTTP $($r.StatusCode) दिया।"
        }
    } catch {
        Write-Host "❌ साइट वेरिफाई नहीं हो पाई: $($_.Exception.Message)"
        Send-Telegram $botToken $chatId "❌ साइट नहीं पहुंच पाई: $($_.Exception.Message)"
    }

} catch {
    Send-Telegram $botToken $chatId "💥 AIVANA Deploy Fatal Error: $($_.Exception.Message)"
    Show-Notification "AIVANA" "Deploy Error"
} finally {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
    Write-Host "✅ Done."
    Send-Telegram $botToken $chatId "✅ AIVANA AutoDeploy पूरा हुआ।"
}
