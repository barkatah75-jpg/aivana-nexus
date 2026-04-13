Write-Host "`n🌐 Starting AIVANA Full AutoDeploy to Hostinger..." -ForegroundColor Cyan
# Ignore SSL certificate validation errors for FTPS
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

Start-Sleep -Seconds 2

# === CONFIG ===
$ftpServer = "ftp://89.117.188.202/domains/todolist.barkataiautomation.in/public_html/"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpPass = Read-Host "🔐 Enter FTP Password"
$verifyURL = "https://todolist.barkataiautomation.in"

# === PREPARE FILES ===
Write-Host "📂 Preparing web files..." -ForegroundColor Yellow

$html = @"
<!doctype html>
<html lang='en'>
<head>
  <meta charset='utf-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1'>
  <title>AIVANA ToDo Automation</title>
  <style>
    body {
      margin:0;
      background: radial-gradient(circle at top,#0f0c29,#302b63,#24243e);
      font-family: Arial, sans-serif;
      height: 100vh;
      display:flex;
      align-items:center;
      justify-content:center;
      color:#00ffff;
      text-shadow:0 0 15px #00ffff;
      font-size:28px;
      letter-spacing:1px;
    }
  </style>
</head>
<body>🚀 AIVANA ToDo Automation System Online 🌌</body>
</html>
"@
Set-Content -Path ".\index.html" -Value $html -Encoding UTF8

$htaccess = @"
Options -Indexes
DirectoryIndex index.html
ErrorDocument 403 /index.html
ErrorDocument 404 /index.html
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule ^(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]
"@
Set-Content -Path ".\.htaccess" -Value $htaccess -Encoding UTF8

Write-Host "✅ index.html & .htaccess ready." -ForegroundColor Green

# === UPLOAD FUNCTION ===
function Upload-FTPFile($local, $remote) {
    try {
        Write-Host "⬆️ Uploading $local ..." -ForegroundColor Yellow
        $req = [System.Net.FtpWebRequest]::Create($remote)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
        $req.EnableSsl = $true
        $req.UsePassive = $true
        $req.UseBinary = $true
        $bytes = [System.IO.File]::ReadAllBytes($local)
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        Write-Host "✅ Uploaded: $local" -ForegroundColor Green
    } catch {
        Write-Host "❌ Upload failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# === EXECUTE UPLOAD ===
Upload-FTPFile ".\index.html" "$ftpServer/index.html"
Upload-FTPFile ".\.htaccess" "$ftpServer/.htaccess"

# === VERIFY SITE ===
Write-Host "🛰️ Verifying website..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri $verifyURL -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Website Online: $verifyURL" -ForegroundColor Green
        Start-Process $verifyURL
    } else {
        Write-Host "⚠️ Unexpected Response: $($response.StatusCode)" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "❌ Website not reachable. Check SSL or domain link." -ForegroundColor Red
}

Write-Host "`n🎯 AIVANA Full AutoDeploy Finished!" -ForegroundColor Cyan
