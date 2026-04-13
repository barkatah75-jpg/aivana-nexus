# ===================================================================
# 🌐 AIVANA AutoPilot v9.4 - Secure FTP + Telegram AlertMode (AutoRepair)
# 🔒 AES Encrypted Telegram & FTP Credentials
# ⚙️ Auto ZIP + Upload + Telegram Alerts + AutoRepair
# ===================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

# --- CONFIG ---
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$ftpHost   = "ftp://89.117.188.202"
$ftpUser   = "u786522790.todolist.barkataiautomation.in"
$uploadRoot = "public_html"
$siteURL   = "https://todolist.barkataiautomation.in"

# --- SECURITY FILES ---
$keyFile  = "$env:USERPROFILE\AIVANA_AES.key"
$authFile = "$env:USERPROFILE\AIVANA_TelegramAuth.enc"
$ftpCred  = "$env:USERPROFILE\AIVANA_FTPAuth.enc"

# --- AES ---
function New-AesKeyIfMissing {
    param($path)
    if (-not (Test-Path $path)) {
        $b = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
        [IO.File]::WriteAllBytes($path,$b)
    }
    return [IO.File]::ReadAllBytes($path)
}
function Encrypt-Text([string]$plain,[byte[]]$key){
    $aes=[System.Security.Cryptography.Aes]::Create()
    $aes.Key=$key; $aes.GenerateIV()
    $enc=$aes.CreateEncryptor().TransformFinalBlock([Text.Encoding]::UTF8.GetBytes($plain),0,$plain.Length)
    [Convert]::ToBase64String($aes.IV+$enc)
}
function Decrypt-Text([string]$encText,[byte[]]$key){
    $data=[Convert]::FromBase64String($encText)
    $aes=[System.Security.Cryptography.Aes]::Create()
    $aes.Key=$key; $aes.IV=$data[0..15]
    $dec=$aes.CreateDecryptor().TransformFinalBlock($data,16,$data.Length-16)
    [Text.Encoding]::UTF8.GetString($dec)
}

# --- UI notify ---
function Show-Notification {
    param([string]$title,[string]$text)
    try{
        $n=New-Object System.Windows.Forms.NotifyIcon
        $n.Icon=[System.Drawing.SystemIcons]::Information
        $n.BalloonTipTitle=$title; $n.BalloonTipText=$text
        $n.Visible=$true; $n.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 1500; $n.Dispose()
    }catch{}
}

# --- Telegram ---
function Send-Telegram {
    param($token,$chatId,$msg)
    try{
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" `
            -Method Post -Body @{chat_id=$chatId;text=$msg} -TimeoutSec 10 | Out-Null
        $true
    }catch{$false}
}

# --- Load Telegram creds ---
$key=New-AesKeyIfMissing -path $keyFile
if(Test-Path $authFile){
    try{
        $json=Decrypt-Text (Get-Content $authFile -Raw) $key | ConvertFrom-Json
        $botToken=$json.token; $chatId=$json.chatid
    }catch{}
}
if(-not $botToken -or -not $chatId){
    $botToken=Read-Host "Enter Telegram Bot Token"
    $chatId=Read-Host "Enter Chat ID"
    $enc=Encrypt-Text (@{token=$botToken;chatid=$chatId}|ConvertTo-Json -Compress) $key
    Set-Content $authFile $enc
}

# --- FTP password (autorepair) ---
function Get-FtpPassword{
    if(Test-Path $ftpCred){
        try{return (Decrypt-Text (Get-Content $ftpCred -Raw) $key|ConvertFrom-Json).pass}catch{}
    }
    $pw=Read-Host "Enter your FTP password"
    $enc=Encrypt-Text (@{pass=$pw}|ConvertTo-Json -Compress) $key
    Set-Content $ftpCred $enc; return $pw
}
$ftpPass=Get-FtpPassword

# --- FTP helpers ---
function Test-FTP-Login($host,$user,$pass){
    try{
        $r=[Net.FtpWebRequest]::Create($host)
        $r.Method=[Net.WebRequestMethods+Ftp]::ListDirectory
        $r.Credentials=New-Object Net.NetworkCredential($user,$pass)
        $r.UsePassive=$true; $r.UseBinary=$true; $r.EnableSsl=$false
        $res=$r.GetResponse();$res.Close();$true
    }catch{$false}
}
function Upload-FileToFtp($uri,$local,$user,$pass){
    try{
        $r=[Net.FtpWebRequest]::Create($uri)
        $r.Method=[Net.WebRequestMethods+Ftp]::UploadFile
        $r.Credentials=New-Object Net.NetworkCredential($user,$pass)
        $r.UsePassive=$true; $r.UseBinary=$true; $r.EnableSsl=$false
        $b=[IO.File]::ReadAllBytes($local)
        $s=$r.GetRequestStream();$s.Write($b,0,$b.Length);$s.Close();$true
    }catch{$_.Exception.Message}
}

# --- MAIN DEPLOY ---
try{
    Write-Host "`n=== 🚀 AIVANA AutoDeploy (Secure FTP) ===" -ForegroundColor Cyan
    Show-Notification "AIVANA" "AutoDeploy शुरू हुआ"
    Send-Telegram $botToken $chatId "🚀 Deploy शुरू हुआ $(Get-Date)"

    $zip="$env:USERPROFILE\deploy_package.zip"
    if(Test-Path $zip){Remove-Item $zip -Force}
    Compress-Archive -Path "$sourceDir\*" -DestinationPath $zip -Force
    Write-Host "ZIP तैयार -> $zip"

    # --- login test ---
    if(-not (Test-FTP-Login $ftpHost $ftpUser $ftpPass)){
        Write-Host "❌ FTP login failed – AutoRepair"
        Remove-Item $ftpCred -Force -ErrorAction SilentlyContinue
        $ftpPass=Get-FtpPassword
        if(-not (Test-FTP-Login $ftpHost $ftpUser $ftpPass)){
            throw "FTP login failed again."
        }
    }
    Write-Host "✅ FTP login OK"

    # --- upload ---
    $files=Get-ChildItem $sourceDir -Recurse -File
    foreach($f in $files){
        $rel=$f.FullName.Substring($sourceDir.Length+1).Replace('\','/')
        $remote="$ftpHost/$uploadRoot/$rel"
        $res=Upload-FileToFtp $remote $f.FullName $ftpUser $ftpPass
        if($res -eq $true){Write-Host "✅ Uploaded: $rel"}
        else{Write-Host "❌ Failed: $rel -> $res"; Send-Telegram $botToken $chatId "❌ Upload failed: $rel -> $res"}
    }

    # --- verify site ---
    try{
        $r=Invoke-WebRequest -Uri $siteURL -UseBasicParsing -TimeoutSec 15
        if($r.StatusCode -eq 200){
            Write-Host "🌐 साइट उपलब्ध (HTTP 200)"
            Send-Telegram $botToken $chatId "✅ Deploy सफल - साइट पहुंच योग्य है।"
            Show-Notification "AIVANA" "Deploy सफल!"
        }else{
            Write-Host "⚠️ HTTP $($r.StatusCode)"
            Send-Telegram $botToken $chatId "⚠️ Deploy हुआ लेकिन साइट ने HTTP $($r.StatusCode) दिया।"
        }
    }catch{
        Write-Host "❌ Verify error: $($_.Exception.Message)"
        Send-Telegram $botToken $chatId "❌ साइट नहीं पहुंच पाई: $($_.Exception.Message)"
    }
}catch{
    Send-Telegram $botToken $chatId "💥 Error: $($_.Exception.Message)"
    Show-Notification "AIVANA" "Deploy Error"
}
