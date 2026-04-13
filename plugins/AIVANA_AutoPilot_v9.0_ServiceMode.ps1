# === AIVANA AutoPilot v9.0 — Background Service + Tray Control ===
Add-Type -AssemblyName PresentationFramework, System.Windows.Forms
Add-Type -AssemblyName System.Security

$sourceDir = "C:\Users\LAPPYHUB\TODOLISTAIAUTOMATION"
$zipFile = "C:\Users\LAPPYHUB\deploy_package.zip"
$ftpHost = "ftp://ftp.todolist.barkataiautomation.in"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$siteURL = "https://todolist.barkataiautomation.in"
$authFile = "C:\Users\LAPPYHUB\AIVANA_AuthCache.enc"
$keyFile = "C:\Users\LAPPYHUB\AIVANA_AES.key"
$logFile = "C:\Users\LAPPYHUB\AIVANA_DeployLogs\ServiceLog.txt"
if (!(Test-Path (Split-Path $logFile))) { New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null }

# === AES Encryption Utilities ===
function Encrypt-Text($plain, $key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.GenerateIV()
    $enc = $aes.CreateEncryptor().TransformFinalBlock([System.Text.Encoding]::UTF8.GetBytes($plain),0,$plain.Length)
    [Convert]::ToBase64String($aes.IV + $enc)
}
function Decrypt-Text($encText, $key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $data = [Convert]::FromBase64String($encText)
    $aes.Key = $key; $aes.IV = $data[0..15]
    [System.Text.Encoding]::UTF8.GetString($aes.CreateDecryptor().TransformFinalBlock($data,16,$data.Length-16))
}

# === Load AES Key ===
if (!(Test-Path $keyFile)) {
    $key = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($key)
    [IO.File]::WriteAllBytes($keyFile, $key)
} else { $key = [IO.File]::ReadAllBytes($keyFile) }

# === Load Password ===
if (Test-Path $authFile) {
    $ftpPass = Decrypt-Text (Get-Content $authFile -Raw) $key
} else {
    $passWin = New-Object System.Windows.Window
    $passWin.Title = "FTP Password"; $passWin.Height = 150; $passWin.Width = 300
    $box = New-Object System.Windows.Controls.PasswordBox; $box.Margin = "20"
    $btn = New-Object System.Windows.Controls.Button; $btn.Content = "OK"; $btn.Margin = "20,70,20,0"
    $btn.Add_Click({ $passWin.Tag = $box.Password; $passWin.Close() })
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Children.Add($box); $grid.Children.Add($btn); $passWin.Content = $grid
    $passWin.ShowDialog() | Out-Null
    $ftpPass = $passWin.Tag
    if (-not $ftpPass) { exit }
    Set-Content $authFile (Encrypt-Text $ftpPass $key)
}

# === Logging Helper ===
function Log($msg) {
    $time = (Get-Date).ToString("HH:mm:ss")
    "$time | $msg" | Tee-Object -Append -FilePath $logFile
    Write-Host $msg
}

# === Toast Notification ===
function Notify($title, $msg) {
    [reflection.assembly]::loadwithpartialname('System.Windows.Forms') | Out-Null
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.BalloonTipTitle = $title
    $n.BalloonTipText = $msg
    $n.Visible = $true
    $n.ShowBalloonTip(3000)
}

# === Folder Create ===
function New-FTPFolder($uri,$user,$pass){
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method=[System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $req.Credentials=New-Object System.Net.NetworkCredential($user,$pass)
        $req.UseBinary=$true;$req.UsePassive=$true;$req.EnableSsl=$false
        $req.GetResponse()|Out-Null
        Log "📁 Created: $uri"
    }catch{}
}

# === Upload Function ===
function Upload-All {
    Log "=== AutoDeploy Started ==="
    if(Test-Path $zipFile){Remove-Item $zipFile -Force}
    Compress-Archive -Path "$sourceDir\*" -DestinationPath $zipFile -Force
    Log "📦 ZIP created."
    $files=Get-ChildItem $sourceDir -Recurse -File
    foreach($file in $files){
        $relative=$file.FullName.Substring($sourceDir.Length+1).Replace("\","/")
        if($relative -match "/"){ 
            $folderUri="$ftpHost/"+($relative.Substring(0,$relative.LastIndexOf("/")))
            New-FTPFolder $folderUri $ftpUser $ftpPass 
        }
        try{
            $req=[System.Net.FtpWebRequest]::Create("$ftpHost/$relative")
            $req.Method=[System.Net.WebRequestMethods+Ftp]::UploadFile
            $req.Credentials=New-Object System.Net.NetworkCredential($ftpUser,$ftpPass)
            $req.UseBinary=$true;$req.UsePassive=$true;$req.EnableSsl=$false
            $bytes=[System.IO.File]::ReadAllBytes($file.FullName)
            $stream=$req.GetRequestStream();$stream.Write($bytes,0,$bytes.Length);$stream.Close()
            Log "✅ Uploaded: $relative"
        }catch{Log "❌ Failed: $($_.Exception.Message)"}
    }

    # === Verify Key Links ===
    $urls=@(
        "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_English.pdf",
        "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_Hindi.pdf",
        "$siteURL/AIVANA_AI_Global_Identity_2025.zip"
    )
    foreach($u in $urls){
        try{
            $resp=(Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 10).StatusCode
            if($resp -eq 200){Log "✅ $u OK"} else {Log "⚠️ HTTP $resp → $u"}
        }catch{Log "❌ Missing/Blocked: $u"}
    }
    if(Test-Path $zipFile){Remove-Item $zipFile -Force;Log "🧹 Cleaned temp files"}
    Log "✅ Deploy complete!"
    Notify "AIVANA AutoDeploy" "Deployment finished successfully!"
}

# === Tray Icon Setup ===
$icon=[System.Windows.Forms.NotifyIcon]::new()
$icon.Icon=[System.Drawing.SystemIcons]::Information
$icon.Visible=$true
$menu=[System.Windows.Forms.ContextMenuStrip]::new()
$pause=$menu.Items.Add("⏸ Pause Sync")
$resume=$menu.Items.Add("▶ Resume Sync")
$exit=$menu.Items.Add("❌ Exit Service")
$icon.ContextMenuStrip=$menu

$paused=$false
$pause.add_Click({$global:paused=$true;Notify "AIVANA" "Sync paused."})
$resume.add_Click({$global:paused=$false;Notify "AIVANA" "Sync resumed."})
$exit.add_Click({$icon.Visible=$false;Notify "AIVANA" "Service stopped.";exit})

# === Initial Upload + Watcher ===
Upload-All
$watcher=New-Object IO.FileSystemWatcher $sourceDir -Property @{
    IncludeSubdirectories=$true
    NotifyFilter=[IO.NotifyFilters]'FileName, LastWrite, DirectoryName'
}
$action={
    if(-not $global:paused){
        Log "⚡ Change detected, syncing..."
        Start-Sleep -Seconds 3
        Upload-All
    }else{
        Log "⏸ Change detected but sync paused."
    }
}
Register-ObjectEvent $watcher Changed -Action $action|Out-Null
Register-ObjectEvent $watcher Created -Action $action|Out-Null
Register-ObjectEvent $watcher Deleted -Action $action|Out-Null

Log "🛰️ AIVANA AutoPilot v9.0 Service Active — watching $sourceDir"
while($true){Start-Sleep -Seconds 3}
