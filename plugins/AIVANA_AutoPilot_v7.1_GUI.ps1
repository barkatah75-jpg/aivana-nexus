Add-Type -AssemblyName PresentationFramework, PresentationCore

# === AIVANA AutoPilot v7.1 GUI ===
$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$uploadDir = "/public_html"
$logDir = "C:\Users\LAPPYHUB\AIVANA_DeployLogs"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpHost = "ftp://ftp.todolist.barkataiautomation.in"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpCache = "C:\Users\LAPPYHUB\AIVANA_AuthCache.json"
$siteURL = "https://todolist.barkataiautomation.in"

if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

# Function for logging
function Log($msg) {
    $time = (Get-Date).ToString("HH:mm:ss")
    $msgLine = "$time  $msg`n"
    $TextBox.AppendText($msgLine)
    $TextBox.ScrollToEnd()
}

# Load or request password
if (Test-Path $ftpCache) {
    $auth = Get-Content $ftpCache | ConvertFrom-Json
    $ftpPass = $auth.pass
} else {
    $ftpPass = [Microsoft.VisualBasic.Interaction]::InputBox("Enter FTP Password:", "FTP Login", "")
    @{host=$ftpHost;user=$ftpUser;pass=$ftpPass} | ConvertTo-Json | Out-File $ftpCache -Encoding UTF8
}

# === GUI Window ===
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="AIVANA AutoPilot v7.1" Width="560" Height="400"
        Background="#0b0b15" WindowStartupLocation="CenterScreen">
  <Grid Margin="15">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Text="AIVANA AutoPilot v7.1 — Auto Deploy System" Foreground="#00ffff" FontSize="18" FontWeight="Bold" Margin="0,0,0,10"/>

    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Background="#111">
      <TextBox x:Name="TextBox" FontFamily="Consolas" FontSize="12" Background="#111" Foreground="White" TextWrapping="Wrap" IsReadOnly="True"/>
    </ScrollViewer>

    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0">
      <Button x:Name="StartButton" Content="🚀 Deploy Now" Width="120" Height="32" Margin="5"/>
      <Button x:Name="ClearButton" Content="🧹 Clear Logs" Width="100" Height="32" Margin="5"/>
      <Button x:Name="ExitButton" Content="❌ Exit" Width="80" Height="32" Margin="5"/>
    </StackPanel>
  </Grid>
</Window>
"@

# Parse XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)
$TextBox = $Window.FindName("TextBox")
$StartButton = $Window.FindName("StartButton")
$ClearButton = $Window.FindName("ClearButton")
$ExitButton = $Window.FindName("ExitButton")

# === Deploy Function ===
$StartButton.Add_Click({
    $StartButton.IsEnabled = $false
    Log "=== Starting AIVANA Deploy ==="
    try {
        if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
        Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
        Log "📦 ZIP created."

        $files = Get-ChildItem $sourceDir -Recurse -File
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($sourceDir.Length + 1).Replace("\", "/")
            $uri = "$ftpHost$uploadDir/$relative"
            try {
                $req = [System.Net.FtpWebRequest]::Create($uri)
                $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
                $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
                $req.UseBinary = $true; $req.UsePassive = $true; $req.EnableSsl = $false
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                $stream = $req.GetRequestStream(); $stream.Write($bytes, 0, $bytes.Length); $stream.Close()
                Log "✅ Uploaded: $relative"
            } catch {
                Log "❌ Failed: $($_.Exception.Message)"
            }
        }

        Log "🌐 Verifying website..."
        try {
            $resp = (Invoke-WebRequest $siteURL -UseBasicParsing -TimeoutSec 10).StatusCode
            if ($resp -eq 200) { Log "🎯 Site LIVE!" } else { Log "⚠️ Unexpected HTTP $resp" }
        } catch { Log "❌ Verify failed." }

        if (Test-Path $zipFile) { Remove-Item $zipFile -Force; Log "🧹 Cleaned temp files" }

    } catch { Log "❌ Fatal Error: $($_.Exception.Message)" }
    Log "✅ AIVANA Deploy Complete!"
    $StartButton.IsEnabled = $true
})

# Clear logs
$ClearButton.Add_Click({ $TextBox.Clear() })
# Exit button
$ExitButton.Add_Click({ $Window.Close() })

$Window.ShowDialog() | Out-Null
