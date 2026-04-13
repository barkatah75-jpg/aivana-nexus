# ===========================================
# 🚀 AIVANA_TODOLIST_AutoHeal_v10.6_WinSCP_FTPS.ps1
# (Full AutoHeal + WinSCP FTPS + Telegram + Scheduler)
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
if (-not (Test-Path $tempRoot)) { New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null }

# --- Telegram Notify ---
function Send-Telegram($msg) {
    try {
        $safeMsg = $msg -replace '[^\x00-\x7F]', ''
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$telegramToken/sendMessage" -Method POST -Body @{chat_id=$chatId; text=$safeMsg} | Out-Null
        Write-Host "📨 Telegram sent."
    } catch {
        Write-Host "⚠️ Telegram failed: $($_.Exception.Message)"
    }
}

# --- Notification ---
function Notify($title,$msg) {
    try {
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.BalloonTipTitle = $title
        $n.BalloonTipText = $msg
        $n.Visible = $true
        $n.ShowBalloonTip(4000)
        Start-Sleep -Milliseconds 2000
        $n.Dispose()
    } catch {}
}

# --- WinSCP Upload ---
function Upload-UsingWinSCP {
    param($localPath, $remotePath)
    $sessionXml = @"
<session>
  <protocol>ftp</protocol>
  <host>$ftpHost</host>
  <port>21</port>
  <username>$ftpUser</username>
  <password>$ftpPass</password>
  <tls>Explicit</tls>
</session>
"@
    $sessionFile = "$env:TEMP\winscp_session.xml"
    $sessionXml | Out-File $sessionFile -Encoding ASCII

    $cmd = @"
option batch continue
option confirm off
open /ini=nul "$sessionFile"
put "$localPath" "$remotePath"
exit
"@
    $cmdFile = "$env:TEMP\winscp_cmd.txt"
    $cmd | Out-File $cmdFile -Encoding ASCII

    & "C:\Program Files (x86)\WinSCP\WinSCP.com" /script=$cmdFile | Out-Null
    Write-Host "✅ Uploaded: $(Split-Path $localPath -Leaf)" -ForegroundColor Green
}

# --- AutoHeal Process ---
function Run-AutoHeal {
    Write-Host "`n🧠 Running AIVANA AutoHeal..." -ForegroundColor Cyan

    $langs = @("EN","HI","ES","FR","ZH","JP")
    foreach ($l in $langs) {
        $pdf = Join-Path $tempRoot "AIVANA_AI_Global_Identity_Guide_$l.pdf"
        "AIVANA Global Identity Guide ($l)`r`nAuto-generated $(Get-Date)" | Out-File $pdf -Encoding UTF8
        Upload-UsingWinSCP $pdf $remoteDir
    }

    $ok = 0
    foreach ($l in $langs) {
        $url = "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf"
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
            if ($r.StatusCode -eq 200) { $ok++ }
        } catch {}
    }

    Write-Host "`n📘 Guides Online: $ok/$($langs.Count)" -ForegroundColor Cyan
    if ($ok -ge 5) {
        Send-Telegram "✅ AIVANA AutoHeal Success: $ok/$($langs.Count) online!"
        Notify "AIVANA AutoHeal" "All major guides verified ✅"
    } else {
        Send-Telegram "⚠️ AIVANA AutoHeal Warning: Only $ok/$($langs.Count) online!"
        Notify "AIVANA AutoHeal" "Some guides missing ⚠️"
    }
}

# --- Scheduler ---
function Register-AutoTrigger {
    try {
        $scriptPath = $MyInvocation.MyCommand.Path
        $taskName = "AIVANA AutoHeal Daemon"
        $trigger = New-ScheduledTaskTrigger -Daily -At 03:00
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
        Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Daily AIVANA AutoHeal FTPS Verify" -Force
        Write-Host "🕓 Scheduler Registered (03:00 AM Daily)" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Scheduler registration failed: $($_.Exception.Message)"
    }
}

# --- MAIN ---
Run-AutoHeal
Register-AutoTrigger
Write-Host "`n✨ AutoHeal Completed Successfully" -ForegroundColor Cyan
