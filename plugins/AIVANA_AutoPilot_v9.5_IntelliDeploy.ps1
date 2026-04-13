# ==========================================================
# 🚀 AIVANA AutoPilot v9.5 – IntelliDeploy
# 💡 Auto FTP Detect + AES Encryption + Telegram Alerts + Log
# ==========================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

# === CONFIG ===
$sourceDir = "C:\Users\LAPPYHUB\AIVANA_TODOLISTAIAUTOMATION_AUTO_DEPLOY_v1"
$ftpHost   = "ftp://ftp.todolist.barkataiautomation.in"
$ftpUser   = "u786522790.todolist.barkataiautomation.in"
$uploadRoot = "public_html"
$siteURL   = "https://todolist.barkataiautomation.in"
$logDir    = "$env:USERPROFILE\AIVANA_Logs"
if(-not(Test-Path $logDir)){New-Item -ItemType Directory -Path $logDir|Out-Null}
$logFile   = "$logDir\deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# === SECURITY FILES ===
$keyFile  = "$env:USERPROFILE\AIVANA_AES.key"
$authFile = "$env:USERPROFILE\AIVANA_TelegramAuth.enc"
$ftpCred  = "$env:USERPROFILE\AIVANA_FTPAuth.enc"

# === AES HELPERS ===
function New-AesKeyIfMissing($path){
    if(-not(Test-Path $path)){
        $b=New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
        [IO.File]::WriteAllBytes($path,$b)
    }
    [IO.File]::ReadAllBytes($path)
}
function Encrypt-Text($plain,[byte[]]$key){
    $aes=[Security.Cryptography.Aes]::Create()
    $aes.Key=$key; $aes.GenerateIV()
    $enc=$aes.CreateEncryptor().TransformFinalBlock([Text.Encoding]::UTF8.GetBytes($plain),0,$plain.Length)
    [Convert]::ToBase64String($aes.IV+$enc)
}
function Decrypt-Text($encText,[byte[]]$key){
    $data=[Convert]::FromBase64String($encText)
    $aes=[Security.Cryptography.Aes]::Create()
    $aes.Key=$key; $aes.IV=$data[0..15]
    $dec=$aes.CreateDecryptor().TransformFinalBlock($data,16,$data.Length-16)
    [Text.Encoding]::UTF8.GetString($dec)
}

# === UI Notification ===
function Show-Notification($title,$msg){
    try{
        $n=New-Object Windows.Forms.NotifyIcon
        $n.Icon=[Drawing.SystemIcons]::Information
        $n.BalloonTipTitle=$title; $n.BalloonTipText=$msg
        $n.Visible=$true; $n.ShowBalloonTip(3000)
        Start-Sleep -Milliseconds 1500; $n.Dispose()
    }catch{}
}

# === Telegram ===
function Send-Telegram($token,$chatId,$msg){
    try{
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" -Method Post -Body @{chat_id=$chatId;text=$msg} -TimeoutSec 10|Out-Null
    }catch{}
}

# === Load Telegram ===
$key=New-AesKeyIfMissing $keyFile
if(Test-Path $authFile){
    try{$t=Decrypt-Text (Get-Content $authFile -Raw) $key|ConvertFrom-Json;$botToken=$t.token;$chatId=$t.chatid}catch{}
}

# === FTP Password ===
function Get-FtpPassword{
    if(Test-Path $ftpCred){
        try{return (Decrypt-Text (Get-Content $ftpCred -Raw) $key|ConvertFrom-Json).pass}catch{}
    }
    $pw=Read-Host "Enter FTP password"
    $enc=Encrypt-Text (@{pass=$pw}|ConvertTo-Json -Compress) $key
    Set-Content $ftpCred $enc;return $pw
}
$ftpPass=Get-FtpPassword

# === FTP Functions ===
function Test-FTP($ssl){
    try{
        $r=[Net.FtpWebRequest]::Create($ftpHost)
        $r.Method=[Net.WebRequestMethods+Ftp]::ListDirectory
        $r.Credentials=New-Object Net.NetworkCredential($ftpUser,$ftpPass)
        $r.UsePassive=$true;$r.UseBinary=$true;$r.EnableSsl=$ssl
        $res=$r.GetResponse();$res.Close();return $true
    }catch{return $false}
}
function Upload-File($uri,$local,$u,$p,$ssl){
    try{
        $r=[Net.FtpWebRequest]::Create($uri)
        $r.Method=[Net.WebRequestMethods+Ftp]::UploadFile
        $r.Credentials=New-Object Net.NetworkCredential($u,$p)
        $r.UseBinary=$true;$r.UsePassive=$true;$r.EnableSsl=$ssl
        $b=[IO.File]::ReadAllBytes($local)
        $s=$r.GetRequestStream();$s.Write($b,0,$b.Length);$s.Close();$true
    }catch{$_.Exception.Message}
}

# === MAIN EXECUTION ===
Start-Transcript -Path $logFile -Force
try{
    Write-Host "`n=== 🚀 AIVANA IntelliDeploy (v9.5) ===" -ForegroundColor Cyan
    Show-Notification "AIVANA" "Deploy started"
    Send-Telegram $botToken $chatId "🚀 IntelliDeploy started on $env:COMPUTERNAME"

    $zip="$env:USERPROFILE\deploy_package.zip"
    if(Test-Path $zip){Remove-Item $zip -Force}
    Compress-Archive -Path "$sourceDir\*" -DestinationPath $zip -Force
    Write-Host "📦 ZIP ready -> $zip"

    $sslMode=$false
    if(Test-FTP $false){$sslMode=$false}
    elseif(Test-FTP $true){$sslMode=$true}
    else{throw "FTP login failed in both SSL modes."}
    Write-Host "🔍 FTP mode detected: SSL=$sslMode"

    $files=Get-ChildItem $sourceDir -Recurse -File
    foreach($f in $files){
        $rel=$f.FullName.Substring($sourceDir.Length+1).Replace('\','/')
        $uri="$ftpHost/$uploadRoot/$rel"
        $r=Upload-File $uri $f.FullName $ftpUser $ftpPass $sslMode
        if($r -eq $true){Write-Host "✅ Uploaded: $rel"}else{Write-Host "❌ Failed: $rel -> $r";Send-Telegram $botToken $chatId "❌ Upload failed: $rel -> $r"}
    }

    $r=Invoke-WebRequest -Uri $siteURL -UseBasicParsing -TimeoutSec 15
    if($r.StatusCode -eq 200){
        Write-Host "🌐 Site reachable (HTTP 200)"
        Send-Telegram $botToken $chatId "✅ Deploy successful - site reachable."
        Show-Notification "AIVANA" "Deploy successful"
    }else{
        Write-Host "⚠️ Site returned HTTP $($r.StatusCode)"
        Send-Telegram $botToken $chatId "⚠️ Deploy finished - HTTP $($r.StatusCode)"
    }
}catch{
    Write-Host "💥 Error: $($_.Exception.Message)" -ForegroundColor Red
    Send-Telegram $botToken $chatId "💥 IntelliDeploy error: $($_.Exception.Message)"
    Show-Notification "AIVANA" "Deploy failed"
}finally{
    Stop-Transcript
    Write-Host "`n🗂️ Log saved -> $logFile"
}
