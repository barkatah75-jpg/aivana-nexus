# ================================================
# 🧠 AIVANA FTP Diagnostic v1.1 (syntax-safe)
# ================================================

Add-Type -AssemblyName System.Security

$ftpHost = "ftp://ftp.todolist.barkataiautomation.in"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpPort = 21
$keyFile = "$env:USERPROFILE\AIVANA_AES.key"
$ftpCred = "$env:USERPROFILE\AIVANA_FTPAuth.enc"

function New-AesKeyIfMissing($path){
    if(-not(Test-Path $path)){
        $b = New-Object byte[] 32
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

$key = New-AesKeyIfMissing $keyFile

function Get-FtpPassword{
    if(Test-Path $ftpCred){
        try{
            return (Decrypt-Text (Get-Content $ftpCred -Raw) $key | ConvertFrom-Json).pass
        }catch{}
    }
    $pw = Read-Host "Enter FTP password"
    $enc = Encrypt-Text (@{pass=$pw}|ConvertTo-Json -Compress) $key
    Set-Content $ftpCred $enc
    return $pw
}
$ftpPass = Get-FtpPassword

Write-Host "`n=== 🔍 AIVANA FTP Diagnostic ===" -ForegroundColor Cyan
Write-Host "Host: $ftpHost"
Write-Host "User: $ftpUser"
Write-Host "Port: $ftpPort"
Write-Host "--------------------------------------------"

function Test-Ftp($ssl){
    try{
        $req=[Net.FtpWebRequest]::Create($ftpHost)
        $req.Method=[Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials=New-Object Net.NetworkCredential($ftpUser,$ftpPass)
        $req.UsePassive=$true
        $req.UseBinary=$true
        $req.EnableSsl=$ssl
        $res=$req.GetResponse()
        $res.Close()
        Write-Host ("✅ FTP login successful (SSL={0})" -f $ssl) -ForegroundColor Green
        return $true
    }catch{
        Write-Host ("❌ FTP login failed (SSL={0}): {1}" -f $ssl,$_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

$plain = Test-Ftp $false
$ssl   = Test-Ftp $true

Write-Host ""
Write-Host "=============================================" -ForegroundColor Yellow
if($plain -or $ssl){
    Write-Host "🎯 FTP connection successful!" -ForegroundColor Green
}else{
    Write-Host "🚫 FTP connection still failing (check password or host)." -ForegroundColor Yellow
}
Write-Host "=============================================" -ForegroundColor Yellow
