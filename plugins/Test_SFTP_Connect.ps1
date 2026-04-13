# Simple SFTP Test & Upload using SSH.NET
# ------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$sftpHost = "todolist.barkataiautomation.in"
$sftpPort = 22
$sftpUser = "u786522790.todolist.barkataiautomation.in"
$sftpPass = Read-Host "Enter SFTP password"
$localFile = "C:\Users\LAPPYHUB\test.txt"
$remotePath = "/public_html/test.txt"

# ----  SSH.NET DLL  ---------------------------------------------------------
$zipUrl = "https://github.com/sshnet/SSH.NET/releases/download/v2020.0.1/SSH.NET-2020.0.1.zip"
$temp = "$env:TEMP\sshnet"
if (-not (Test-Path "$temp")) { New-Item -ItemType Directory -Force -Path "$temp" | Out-Null }
$zipFile = "$temp\sshnet.zip"

if (-not (Test-Path "$temp\Renci.SshNet.dll")) {
    Write-Host "Downloading SSH.NET library..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
    Expand-Archive $zipFile -DestinationPath $temp -Force
}

Add-Type -Path (Get-ChildItem "$temp" -Recurse -Filter "Renci.SshNet.dll" | Select-Object -First 1).FullName

# ----  CONNECT & UPLOAD  ----------------------------------------------------
try {
    $client = New-Object Renci.SshNet.SftpClient($sftpHost, $sftpPort, $sftpUser, $sftpPass)
    $client.Connect()
    if ($client.IsConnected) {
        Write-Host "✅  Connected to $sftpHost via SFTP"
        if (-not (Test-Path $localFile)) {
            "SFTP test file - $(Get-Date)" | Out-File $localFile
        }
        $fs = [System.IO.File]::OpenRead($localFile)
        $client.UploadFile($fs, $remotePath, $true)
        $fs.Close()
        Write-Host "✅  Uploaded test file to $remotePath"
        $client.Disconnect()
    } else {
        Write-Host "❌  Could not connect."
    }
}
catch {
    Write-Host "💥  Error: $($_.Exception.Message)"
}
