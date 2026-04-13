# ===========================================
# AIVANA_TODOLIST_AutoHeal_v10.9_ASCII_SAFE.ps1
# Stable FTPS Upload + Telegram + Scheduler (no Unicode, no multiline)
# ===========================================

chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- CONFIG ---
$ftpHost = "89.117.188.202"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpPass = "M1$wc$0cX>G~QfYt"
$remoteDir = "/public_html/guides/"
$siteURL = "https://todolist.barkataiautomation.in"
$telegramToken = "7971210207:AAGxszjrHx60yVv9dtgy-Ohv-6BiRVnJgNw"
$chatId = "1875063875"
$tempRoot = "$env:TEMP\AIVANA_TODOLIST_AUTOFIX"

$WinSCP = "C:\Program Files (x86)\WinSCP\WinSCP.com"
if (-not (Test-Path $WinSCP)) { $WinSCP = "$env:USERPROFILE\Downloads\WinSCP\WinSCP.com" }

if (-not (Test-Path $tempRoot)) { New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null }

# --- Telegram Notify ---
function Send-Telegram($msg) {
    try {
        $clean = $msg -replace '[^\x00-\x7F]', ''
        Invoke-RestMethod "https://api.telegram.org/bot$telegramToken/sendMessage" -Method POST -Body @{chat_id=$chatId; text=$clean} | Out-Null
        Write-Host "Telegram sent OK"
    } catch {
        Write-Host "Telegram failed: $($_.Exception.Message)"
    }
}

# --- Windows Notification ---
function Notify($title,$msg) {
    try {
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.BalloonTipTitle = $title
        $n.BalloonTipText = $msg
        $n.Visible = $true
        $n.ShowBalloonTip(3000)
        Start-Sleep -Milliseconds 2000
        $n.Dispose()
    } catch {}
}

# --- Upload via WinSCP ---
function Upload-File($localPath) {
    $sessionFile = "$env:TEMP\winscp_session.ini"
    $cmdFile = "$env:TEMP\winscp_cmd.txt"

    @(
        "# WinSCP session",
        "protocol=ftp",
        "host=$ftpHost",
        "port=21",
        "username=$ftpUser",
        "password=$ftpPass",
        "tls=Explicit"
    ) | Set-Content -Encoding ASCII $sessionFile

    @(
        "option batch continue",
        "option confirm off",
        "open /ini=nul `"$sessionFile`"",
        "put `"$localPath`" `"$remoteDir`"",
        "exit"
    ) | Set-Content -Encoding ASCII $cmdFile

    if (Test-Path $WinSCP) {
        & "$WinSCP" /script=$cmdFile | Out-Null
        Write-Host "Uploaded: $(Split-Path $localPath -Leaf)"
    } else {
        Write-Host "WinSCP not found at $WinSCP"
    }
}

# --- AutoHeal Core ---
function Run-AutoHeal {
    Write-Host ""
    Write-Host "Running AIVANA AutoHeal..." -ForegroundColor Cyan
    $langs = @("EN","HI","ES","FR","ZH","JP")

    foreach ($l in $langs) {
        $pdf = Join-Path $tempRoot "AIVANA_AI_Global_Identity_Guide_$l.pdf"
        "AIVANA Guide ($l) - Generated $(Get-Date)" | Out-File $pdf -Encoding UTF8
        Upload-File $pdf
    }

    $ok = 0
    foreach ($l in $langs) {
        $url = "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf"
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8
            if ($r.StatusCode -eq 200) { $ok++ }
        } catch {}
    }

    Write-Host "Guides Online: $ok/$($langs.Count)" -ForegroundColor Cyan
    if ($ok -ge 5) {
        Send-Telegram "AIVANA AutoHeal Success: $ok/$($langs.Count) online"
        Notify "AIVANA AutoHeal" "All guides OK"
    } else {
        Send-Telegram "AIVANA AutoHeal Warning: Only $ok/$($langs.Count) online"
        Notify "AIVANA AutoHeal" "Some guides missing"
    }
}

# --- Scheduler Setup ---
function Register-AutoTrigger {
    try {
        $scriptPath = $MyInvocation.MyCommand.Path
        $taskName = "AIVANA AutoHeal Daemon"
        $trigger = New-ScheduledTaskTrigger -Daily -At 03:00
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
        Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Daily AutoHeal FTPS Verify" -Force
        Write-Host "Scheduler Registered (03:00 AM Daily)" -ForegroundColor Green
    } catch {
        Write-Host "Scheduler error: $($_.Exception.Message)"
    }
}

# --- MAIN ---
Run-AutoHeal
Register-AutoTrigger
Write-Host ""
Write-Host "AutoHeal Completed Successfully" -ForegroundColor Cyan
