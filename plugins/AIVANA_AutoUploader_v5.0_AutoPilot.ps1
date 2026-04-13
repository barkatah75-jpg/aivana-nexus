# === AIVANA AutoUploader v5.0 AutoPilot ===
Add-Type -AssemblyName PresentationFramework
$ftpHostList = @("ftp://ftp.todolist.barkataiautomation.in", "ftp://89.117.188.202")
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$uploadDir = "/public_html"
$logDir = "C:\Users\LAPPYHUB\AIVANA_DeployLogs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = "$logDir\deploy_log.txt"
function Log($msg) {
    $time = (Get-Date).ToString("HH:mm:ss")
    "$time  $msg" | Tee-Object -Append -FilePath $logFile
    Write-Host $msg
}
Log "`n=== 🚀 Starting AIVANA AutoUploader v5.0 AutoPilot ==="
$ftpPass = Read-Host "🔐 Enter FTP Password"
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
Log "📦 ZIP created: $zipFile"

$connected = $false
foreach ($host in $ftpHostList) {
    try {
        Log "🔗 Testing $host ..."
        $req = [System.Net.FtpWebRequest]::Create("$host/")
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
        $req.UsePassive = $true; $req.UseBinary = $true; $req.EnableSsl = $true
        $res = $req.GetResponse()
        Log "✅ Connected successfully via FTPS: $host"
        $connected = $true; $ftpServer = $host; break
    } catch {
        Log "⚠️ SSL failed for $host, retrying without SSL..."
        try {
            $req.EnableSsl = $false
            $res = $req.GetResponse()
            Log "✅ Connected successfully via FTP: $host"
            $connected = $true; $ftpServer = $host; break
        } catch {
            Log "❌ Connection failed for $host"
        }
    }
}
if (-not $connected) {
    Log "❌ No valid FTP host found. Exiting."; exit
}

$files = @($zipFile, "C:\Users\LAPPYHUB\auto-extract.php")
if (-not (Test-Path $files[1])) {
@"
<?php
$zip = new ZipArchive;
if ($zip->open('deploy_package.zip') === TRUE) {
  $zip->extractTo('.');
  $zip->close();
  echo '✅ AIVANA AutoDeploy Successful!';
  unlink(__FILE__);
  unlink('deploy_package.zip');
} else { echo '❌ Extraction Failed'; }
?>
"@ | Out-File $files[1] -Encoding UTF8
}
foreach ($file in $files) {
    $name = Split-Path $file -Leaf
    try {
        Log "⬆️ Uploading $name ..."
        $uri = "$ftpServer/$uploadDir/$name"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
        $req.UsePassive = $true; $req.UseBinary = $true; $req.EnableSsl = $false
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $stream = $req.GetRequestStream(); $stream.Write($bytes, 0, $bytes.Length); $stream.Close()
        Log "✅ Uploaded: $name"
    } catch {
        Log "❌ Upload failed for $name: $($_.Exception.Message)"
    }
}

Log "🛰️ Verifying website..."
try {
    $result = (Invoke-WebRequest "https://todolist.barkataiautomation.in" -UseBasicParsing -TimeoutSec 15).Content
    if ($result -match "AIVANA") { Log "🎯 Deployment verified successfully!" }
    else { Log "⚠️ Site reachable but verification failed." }
} catch { Log "❌ Site unreachable: $($_.Exception.Message)" }

Log "🧹 Cleaning local temp files..."
Remove-Item $zipFile -Force
Log "`n🎉 AIVANA AutoUploader v5.0 AutoPilot Finished!"
