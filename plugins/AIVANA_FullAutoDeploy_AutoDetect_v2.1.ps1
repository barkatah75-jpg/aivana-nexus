# ============================================================
# 🚀 AIVANA Full AutoDeploy v2.1 (AutoDetect + FTPS Fallback)
# Author: AIVANA Systems | Barkat AI Automation
# ============================================================

Write-Host "`n🌐 Starting AIVANA Full AutoDeploy to Hostinger..." -ForegroundColor Cyan

# ---------- CONFIG ----------
$ftpHosts = @(
    "ftp://ftp.todolist.barkataiautomation.in/",
    "ftp://89.117.188.202/"
)

$ftpUsers = @(
    "u786522790.todolist.barkataiautomation.in",
    "u786522790.todolistaiautomation"
)

$ftpPath = "domains/todolist.barkataiautomation.in/public_html/"
$verifyURL = "https://todolist.barkataiautomation.in"
$ftpPass = Read-Host "🔐 Enter FTP Password"

# ---------- STEP 1: Auto-detect working FTP combo ----------
$connected = $false
foreach ($host in $ftpHosts) {
    foreach ($user in $ftpUsers) {
        Write-Host "`n🔍 Testing $user@$host" -ForegroundColor Yellow
        $req = [System.Net.FtpWebRequest]::Create($host)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($user, $ftpPass)
        $req.UsePassive = $true
        $req.UseBinary = $true
        $req.EnableSsl = $false
        try {
            $res = $req.GetResponse()
            Write-Host "✅ Connected successfully as $user" -ForegroundColor Green
            $res.Close()
            $ftpServer = "$host$ftpPath"
            $ftpUser = $user
            $connected = $true
            break
        } catch {
            Write-Host "❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if ($connected) { break }
}

if (-not $connected) {
    Write-Host "`n🚫 No valid FTP combination found. Please check credentials." -ForegroundColor Red
    exit
}

# ---------- STEP 2: Prepare web files ----------
Write-Host "`n📂 Preparing web files..." -ForegroundColor Cyan

$indexHTML = @"
<!doctype html>
<html lang='en'>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<title>AIVANA ToDo Aurora</title>
<style>
body{
margin:0;
font-family:sans-serif;
background:radial-gradient(circle at top,#0f0c29,#302b63,#24243e);
display:flex;align-items:center;justify-content:center;
height:100vh;color:#00ffff;
text-shadow:0 0 20px #00ffff;
font-size:26px;letter-spacing:1px;
}
</style>
</head>
<body>⚡ AIVANA ToDo Automation System Online ⚡</body>
</html>
"@
Set-Content -Path "index.html" -Value $indexHTML -Encoding UTF8

$htaccess = @"
Options -Indexes
DirectoryIndex index.html
ErrorDocument 403 /index.html
ErrorDocument 404 /index.html
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule ^(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]
"@
Set-Content -Path ".htaccess" -Value $htaccess -Encoding UTF8

Write-Host "✅ index.html & .htaccess ready." -ForegroundColor Green

# ---------- STEP 3: Upload via FTP ----------
$files = @("index.html", ".htaccess")
foreach ($file in $files) {
    $target = "$ftpServer$file"
    Write-Host "⬆️ Uploading $file ..."
    $req = [System.Net.FtpWebRequest]::Create($target)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
    $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
    $req.UseBinary = $true
    $req.UsePassive = $true
    $req.EnableSsl = $false
    try {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        Write-Host "✅ Uploaded $file successfully." -ForegroundColor Green
    } catch {
        Write-Host "❌ Upload failed for $file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---------- STEP 4: Verify Website ----------
Write-Host "`n🛰️ Verifying website..." -ForegroundColor Cyan
try {
    $res = Invoke-WebRequest -Uri $verifyURL -UseBasicParsing -TimeoutSec 15
    if ($res.StatusCode -eq 200) {
        Write-Host "✅ Website Online: $verifyURL" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Website responded with status: $($res.StatusCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Website not reachable: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n🎯 AIVANA AutoDeploy Completed Successfully!" -ForegroundColor Cyan
