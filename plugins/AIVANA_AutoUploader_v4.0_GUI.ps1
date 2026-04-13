Add-Type -AssemblyName PresentationFramework

# === CONFIG ===
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpServer = "ftp://89.117.188.202/"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpPath = "public_html/"
$verifyURL = "https://todolist.barkataiautomation.in"

# === GUI ===
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="AIVANA AutoUploader v4.0" Height="340" Width="540" Background="#0a0a1f" WindowStartupLocation="CenterScreen">
  <Grid Margin="15">
    <TextBlock Text="🌐 AIVANA AutoUploader v4.0" FontSize="20" Foreground="Cyan" HorizontalAlignment="Center" Margin="0,10,0,0"/>
    <TextBox Name="PasswordBox" Width="300" Height="30" Margin="0,60,0,0" HorizontalAlignment="Center" VerticalAlignment="Top" 
             FontSize="14" Foreground="White" Background="#111133" CaretBrush="White" />
    <Button Name="StartBtn" Content="🚀 Start Upload" Width="200" Height="40" Margin="0,110,0,0" HorizontalAlignment="Center" VerticalAlignment="Top" Background="#0099ff" Foreground="White"/>
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

function Upload-File {
    param([string]$file)
    $name = [IO.Path]::GetFileName($file)
    $target = "$ftpServer$ftpPath$name"
    try {
        $req = [Net.FtpWebRequest]::Create($target)
        $req.Method = [Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object Net.NetworkCredential($ftpUser, $PasswordBox.Text)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $req.EnableSsl = $false
        $bytes = [IO.File]::ReadAllBytes($file)
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        Log "✅ Uploaded: $name"
        return $true
    } catch {
        Log "❌ Upload failed for $name: $($_.Exception.Message)"
        return $false
    }
}

$StartBtn.Add_Click({
    $ProgressBar.Value = 0
    Log "=== Starting AIVANA AutoUploader ==="
    Log "📦 Creating ZIP package..."
    if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
    Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
    Log "✅ ZIP created: $zipFile"

    $phpFile = "C:\Users\LAPPYHUB\auto-extract.php"
@"
<?php
\$zip = new ZipArchive;
if (\$zip->open('deploy_package.zip') === TRUE) {
    \$zip->extractTo('.');
    \$zip->close();
    echo '✅ AIVANA Deployment Extracted Successfully!';
    unlink('deploy_package.zip');
    unlink('auto-extract.php');
} else {
    echo '❌ Failed to Extract ZIP.';
}
?>
"@ | Set-Content $phpFile -Encoding UTF8

    $ProgressBar.Value = 30
    Log "⬆️ Uploading files to FTP..."
    if (Upload-File $zipFile -and Upload-File $phpFile) {
        $ProgressBar.Value = 60
        Log "🛰️ Triggering extraction script..."
        try {
            [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            $res = Invoke-WebRequest -Uri "$verifyURL/auto-extract.php" -UseBasicParsing -TimeoutSec 20
            Log "Server Response: $($res.Content)"
        } catch {
            Log "❌ Error triggering extractor: $($_.Exception.Message)"
        }
        $ProgressBar.Value = 90
        try {
            $r = Invoke-WebRequest -Uri $verifyURL -UseBasicParsing -TimeoutSec 20
            if ($r.StatusCode -eq 200) {
                Log "🌍 SITE LIVE: $verifyURL"
            } else {
                Log "⚠️ Status: $($r.StatusCode)"
            }
        } catch {
            Log "❌ Site verification failed: $($_.Exception.Message)"
        }
        $ProgressBar.Value = 100
        Log "🎯 Deployment Complete!"
    } else {
        Log "❌ Upload failed — check credentials or path."
    }
})

$Window.ShowDialog() | Out-Null
