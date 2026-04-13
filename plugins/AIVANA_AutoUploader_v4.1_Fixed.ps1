Add-Type -AssemblyName PresentationFramework

# === CONFIG ===
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpHosts = @("ftp://ftp.todolist.barkataiautomation.in/")

$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpPath = "public_html/"
$verifyURL = "https://todolist.barkataiautomation.in"

# === GUI ===
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="AIVANA AutoUploader v4.1 (Fixed Build)" Height="370" Width="560" Background="#0a0a1f" WindowStartupLocation="CenterScreen">
  <Grid Margin="15">
    <TextBlock Text="AIVANA AutoUploader v4.1" FontSize="20" Foreground="Cyan" HorizontalAlignment="Center" Margin="0,10,0,0"/>
    <TextBlock Text="Auto FTP Host Detection + Upload System" FontSize="12" Foreground="LightGray" HorizontalAlignment="Center" Margin="0,35,0,0"/>
    <PasswordBox Name="PasswordBox" Width="300" Height="30" Margin="0,65,0,0" HorizontalAlignment="Center" VerticalAlignment="Top" FontSize="14" Foreground="White" Background="#111133" />
    <Button Name="StartBtn" Content="Start Auto Upload" Width="200" Height="40" Margin="0,110,0,0" HorizontalAlignment="Center" VerticalAlignment="Top" Background="#0099ff" Foreground="White"/>
    <ProgressBar Name="ProgressBar" Height="20" Margin="0,170,0,0" HorizontalAlignment="Stretch" VerticalAlignment="Top" Foreground="Lime"/>
    <TextBox Name="LogBox" Margin="0,200,0,0" Background="#0d0d2b" Foreground="LightGreen" FontFamily="Consolas" FontSize="13" IsReadOnly="True" VerticalScrollBarVisibility="Auto"/>
  </Grid>
</Window>
"@
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)
$PasswordBox = $Window.FindName("PasswordBox")
$StartBtn = $Window.FindName("StartBtn")
$ProgressBar = $Window.FindName("ProgressBar")
$LogBox = $Window.FindName("LogBox")

function Log($msg) {
    $LogBox.AppendText("$msg`n")
    $LogBox.ScrollToEnd()
}

function Test-FTPHost($host, $pass) {
    try {
        $req = [Net.FtpWebRequest]::Create("$host")
        $req.Method = [Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = New-Object Net.NetworkCredential($ftpUser, $pass)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $req.EnableSsl = $false
        $res = $req.GetResponse()
        $res.Close()
        return $true
    } catch {
        return $false
    }
}

function Upload-File {
    param([string]$file, [string]$host, [string]$pass)
    $name = [IO.Path]::GetFileName($file)
    $target = "$host$ftpPath$name"
    try {
        $req = [Net.FtpWebRequest]::Create($target)
        $req.Method = [Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object Net.NetworkCredential($ftpUser, $pass)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $req.EnableSsl = $false
        $bytes = [IO.File]::ReadAllBytes($file)
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        Log "Uploaded: $name"
        return $true
    } catch {
       Log ("Upload failed for {0}: {1}" -f $name, $_.Exception.Message)

        return $false
    }
}

$StartBtn.Add_Click({
    $ProgressBar.Value = 0
    $pass = $PasswordBox.Password
    if (-not $pass) { Log "Enter FTP password first!"; return }

    Log "=== AIVANA AutoUploader v4.1 (Fixed) Started ==="
    Log "Creating ZIP..."
    if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
    Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
    Log "ZIP created: $zipFile"
    $ProgressBar.Value = 20

    $phpFile = "C:\Users\LAPPYHUB\auto-extract.php"
$phpCode = @'
<?php
$zip = new ZipArchive;
if ($zip->open('deploy_package.zip') === TRUE) {
    $zip->extractTo('.');
    $zip->close();
    echo 'AIVANA Deployment Extracted Successfully!';
    unlink('deploy_package.zip');
    unlink('auto-extract.php');
} else {
    echo 'Failed to Extract ZIP.';
}
?>
'@
Set-Content -Path $phpFile -Value $phpCode -Encoding UTF8

    Log "Testing FTP hosts..."
    $connectedHost = $null
    foreach ($h in $ftpHosts) {
        Log "Trying $h ..."
        if (Test-FTPHost $h $pass) {
            Log "Connected to: $h"
            $connectedHost = $h
            break
        } else {
            Log "Failed: $h"
        }
    }

    if (-not $connectedHost) {
        Log "No valid FTP host found. Check credentials."
        return
    }

    $ProgressBar.Value = 40
    Log "Uploading files to $connectedHost ..."
    if (Upload-File $zipFile $connectedHost $pass -and Upload-File $phpFile $connectedHost $pass) {
        $ProgressBar.Value = 70
        Log "Running extractor..."
        try {
            [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            $r = Invoke-WebRequest -Uri "$verifyURL/auto-extract.php" -UseBasicParsing -TimeoutSec 20
            Log "Server Response: $($r.Content)"
        } catch {
            Log "Extractor Error: $($_.Exception.Message)"
        }
        $ProgressBar.Value = 90
        try {
            $res = Invoke-WebRequest -Uri $verifyURL -UseBasicParsing -TimeoutSec 20
            if ($res.StatusCode -eq 200) {
                Log "Site Verified: $verifyURL"
            } else {
                Log "HTTP Status: $($res.StatusCode)"
            }
        } catch {
            Log "Site Verification Failed: $($_.Exception.Message)"
        }
        $ProgressBar.Value = 100
        Log "Deployment Complete!"
    } else {
        Log "Upload failed!"
    }
})

$Window.ShowDialog() | Out-Null
