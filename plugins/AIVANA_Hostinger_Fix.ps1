Write-Host "`n🚀 Starting AIVANA Full AutoDeploy to Hostinger..." -ForegroundColor Cyan

# === CONFIGURATION ===
$repoUrl = "https://github.com/barkatah75-jpg/TODOLISTAIAUTOMATION-.git"
$localRepo = "$env:TEMP\AIVANA_TODO_DEPLOY"
$ftpServer = "ftp://ftp.todolist.barkataiautomation.in/public_html/"
$ftpUser = "u786522790.todolistaiautomation"
$ftpPass = Read-Host "Enter FTP Password" -AsSecureString
$ftpPassUnsecure = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ftpPass)
)

# === PREPARE TEMP FOLDER ===
if (Test-Path $localRepo) {
    Remove-Item -Recurse -Force $localRepo
}
git clone $repoUrl $localRepo
Set-Location $localRepo
Write-Host "✅ Repository cloned successfully." -ForegroundColor Green

# === CREATE .htaccess (Force HTTPS + Index fix) ===
$htaccess = @"
Options -Indexes
DirectoryIndex index.html
ErrorDocument 403 /index.html
ErrorDocument 404 /index.html
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule ^(.*)$ https://%{HTTP_HOST}/$1 [R=301,L]
"@
Set-Content -Path "$localRepo\.htaccess" -Value $htaccess -Encoding ASCII

# === UPLOAD FUNCTION ===
function Upload-FTPFile($filePath, $remoteFile) {
    $uri = $ftpServer + $remoteFile
    $ftp = [System.Net.FtpWebRequest]::Create($uri)
    $ftp.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPassUnsecure)
    $ftp.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
    $ftp.UseBinary = $true
    $ftp.UsePassive = $true
    $ftp.EnableSsl = $false

    $fileContent = [System.IO.File]::ReadAllBytes($filePath)
    $ftpStream = $ftp.GetRequestStream()
    $ftpStream.Write($fileContent, 0, $fileContent.Length)
    $ftpStream.Close()
    Write-Host "⬆️ Uploaded: $remoteFile" -ForegroundColor Green
}

# === UPLOAD FILES RECURSIVELY ===
function Upload-Folder($folderPath, $remotePath) {
    $files = Get-ChildItem -Path $folderPath -Recurse -File
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($folderPath.Length + 1).Replace("\", "/")
        try {
            Upload-FTPFile $file.FullName $relativePath
        } catch {
            Write-Host "⚠️ Failed: $relativePath" -ForegroundColor Yellow
        }
    }
}

Write-Host "📂 Uploading files to Hostinger..." -ForegroundColor Cyan
Upload-Folder $localRepo "/"
Upload-FTPFile "$localRepo\.htaccess" ".htaccess"

Write-Host "`n✅ Upload complete! Verifying online..." -ForegroundColor Green

# === VERIFY SITE ===
try {
    $url = "https://todolist.barkataiautomation.in"
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "🌐 Site Verified Online! ✅" -ForegroundColor Green
        Write-Host "👉 $url"
    } else {
        Write-Host "⚠️ Site responded but not OK: $($response.StatusCode)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "❌ Could not verify site. Check Hostinger manually." -ForegroundColor Red
}

Write-Host "`n🎯 AIVANA Full AutoDeploy Finished!" -ForegroundColor Cyan
