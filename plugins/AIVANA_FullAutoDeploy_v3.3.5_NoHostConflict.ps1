Write-Host ""
Write-Host "=== Starting AIVANA Full AutoDeploy (v3.3.5 NoHostConflict) ==="

# CONFIG
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpHosts = @(
    "ftp://todolist.barkataiautomation.in/",
    "ftp://89.117.188.202/"
)
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpPath = "public_html/"
$verifyURL = "https://todolist.barkataiautomation.in"
$ftpPass = Read-Host "Enter FTP Password"

# ZIP PACKAGE
if (!(Test-Path $sourceDir)) {
    Write-Host "Source folder not found: $sourceDir" -ForegroundColor Red
    exit
}
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
Write-Host "Creating ZIP package..." -ForegroundColor Yellow
Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
Write-Host "ZIP created: $zipFile" -ForegroundColor Green

# PHP Extractor
$phpFile = "C:\Users\LAPPYHUB\auto-extract.php"
@"
<?php
\$zip = new ZipArchive;
if (\$zip->open('deploy_package.zip') === TRUE) {
    \$zip->extractTo('.');
    \$zip->close();
    echo 'AIVANA Deployment Extracted Successfully!';
    unlink('deploy_package.zip');
    unlink('auto-extract.php');
} else {
    echo 'Failed to Extract ZIP.';
}
?>
"@ | Set-Content $phpFile -Encoding UTF8

# Upload Function
function Upload-File {
    param([string]$ftpHost, [string]$file)
    $name = [IO.Path]::GetFileName($file)
    $target = "$ftpHost$ftpPath$name"
    Write-Host "Uploading $name to $ftpHost"

    try {
        $req = [Net.FtpWebRequest]::Create($target)
        $req.Method = [Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object Net.NetworkCredential($ftpUser, $ftpPass)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $req.EnableSsl = $true

        try {
            $bytes = [IO.File]::ReadAllBytes($file)
            $stream = $req.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
            Write-Host "Uploaded (SSL): $name"
            return $true
        } catch {
            Write-Host "SSL failed, retrying without SSL..."
            $req = [Net.FtpWebRequest]::Create($target)
            $req.Method = [Net.WebRequestMethods+Ftp]::UploadFile
            $req.Credentials = New-Object Net.NetworkCredential($ftpUser, $ftpPass)
            $req.UseBinary = $true
            $req.UsePassive = $true
            $req.EnableSsl = $false
            $bytes = [IO.File]::ReadAllBytes($file)
            $stream = $req.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
            Write-Host "Uploaded (Non-SSL): $name"
            return $true
        }
    } catch {
        Write-Host ("Upload failed for {0}: {1}" -f $name, $_.Exception.Message)
        return $false
    }
}

# Try Hosts
$uploaded = $false
foreach ($ftpHostItem in $ftpHosts) {
    Write-Host ""
    Write-Host "Trying FTP host: $ftpHostItem"
    foreach ($file in @($zipFile, $phpFile)) {
        if (!(Upload-File -ftpHost $ftpHostItem -file $file)) {
            Write-Host "Retrying next host..."
            $uploaded = $false
            break
        } else {
            $uploaded = $true
        }
    }
    if ($uploaded) { break }
}

if (-not $uploaded) {
    Write-Host "Upload failed on all hosts. Check credentials."
    exit
}

# Trigger Extractor
Write-Host "Triggering extraction script..."
try {
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    $url = "$verifyURL/auto-extract.php"
    $res = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
    Write-Host "Server Response: $($res.Content)"
} catch {
    Write-Host ("Extractor Error: {0}" -f $_.Exception.Message)
}

# Verify Site
Write-Host "Verifying site status..."
try {
    $r = Invoke-WebRequest -Uri $verifyURL -UseBasicParsing -TimeoutSec 20
    if ($r.StatusCode -eq 200) {
        Write-Host "SITE LIVE: $verifyURL"
    } else {
        Write-Host ("Status: {0}" -f $r.StatusCode)
    }
} catch {
    Write-Host ("Verification failed: {0}" -f $_.Exception.Message)
}

Write-Host ""
Write-Host "=== AIVANA Full AutoDeploy v3.3.5 Completed Successfully! ==="
