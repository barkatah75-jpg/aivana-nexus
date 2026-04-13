# ==========================================================
# AIVANA_TODOLIST_AutoTrigger_v9.8_SilentDaemon.ps1
# Full AutoFix + Daily Trigger + Hybrid FTP + Telegram Alerts
# Background Silent Daemon Mode (UTF-8 Safe)
# ==========================================================

chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- CONFIG ---
$ftpHost  = "ftp://89.117.188.202/public_html"
$ftpUser  = "u786522790.todolist.barkataiautomation.in"
$ftpPass  = "M1$wc$0cX>G~QfYt"
$siteURL  = "https://todolist.barkataiautomation.in"
$telegramToken = "YOUR_TELEGRAM_BOT_TOKEN"
$chatId = "YOUR_CHAT_ID"
$tempRoot = "$env:TEMP\AIVANA_TODOLIST_AUTOFIX"
$logRoot = "$env:USERPROFILE\AIVANA_Logs"
if (-not (Test-Path $logRoot)) { New-Item -ItemType Directory -Force -Path $logRoot | Out-Null }
$logFile = "$logRoot\AutoTrigger_$(Get-Date -Format yyyyMMdd_HHmmss).log"

# --- Telegram Notify ---
function Send-Telegram($msg) {
  try {
    $uri = "https://api.telegram.org/bot$telegramToken/sendMessage"
    $body = @{ chat_id=$chatId; text=$msg }
    Invoke-RestMethod -Uri $uri -Method POST -Body $body | Out-Null
  } catch {}
}

# --- Local Notification ---
function Notify($title,$msg) {
  try {
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.BalloonTipTitle = $title
    $n.BalloonTipText = $msg
    $n.Visible = $true
    $n.ShowBalloonTip(4000)
    Start-Sleep -Milliseconds 2500
    $n.Dispose()
  } catch {}
}

# --- FTP Upload (Hybrid Mode + Path Fix) ---
function Upload-FileToFtp {
  param($uri,$localPath,$user,$pass)
  foreach ($mode in @($true, $false)) {
    try {
      $req = [System.Net.FtpWebRequest]::Create($uri)
      $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
      $req.Credentials = New-Object System.Net.NetworkCredential($user,$pass)
      $req.UseBinary = $true
      $req.UsePassive = $mode
      $req.EnableSsl = $false
      $req.KeepAlive = $false
      $bytes = [System.IO.File]::ReadAllBytes($localPath)
      $stream = $req.GetRequestStream()
      $stream.Write($bytes,0,$bytes.Length)
      $stream.Close()
      Write-Host "Uploaded -> $($localPath | Split-Path -Leaf) (Passive=$mode)" -ForegroundColor Green
      return $true
    } catch {
      $msg = $_.Exception.Message
      if ($msg -like "*530*") {
        Write-Host "Login failed for $user (530 Not logged in)" -ForegroundColor Yellow
      } else {
        Write-Host "Failed (Passive=$mode): $msg" -ForegroundColor DarkYellow
      }
      Start-Sleep -Seconds 1
    }
  }
  return $false
}

# --- Feature Check + AutoFix ---
function Run-AutoFix {
  "=== AIVANA AutoTrigger Run @ $(Get-Date) ===" | Out-File $logFile
  if (-not (Test-Path $tempRoot)) { New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null }

  $langs = @("EN","HI","ES","FR","AR","ZH","JP")
  foreach ($l in $langs) {
    $pdfPath = Join-Path $tempRoot "AIVANA_AI_Global_Identity_Guide_$l.pdf"
    "AIVANA Global Identity Guide ($l)`r`nAuto-generated $(Get-Date)" | Out-File $pdfPath -Encoding UTF8
  }

  foreach ($pdf in Get-ChildItem $tempRoot -Filter *.pdf) {
    $remotePath = "$ftpHost/guides/" + $pdf.Name
    if (-not (Upload-FileToFtp $remotePath $pdf.FullName $ftpUser $ftpPass)) {
      Write-Host "Failed upload -> $($pdf.Name)" -ForegroundColor Red
    }
  }

  $okCount = 0
  foreach ($l in $langs) {
    $url = "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf"
    try {
      $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
      if ($r.StatusCode -eq 200) { $okCount++ }
    } catch {}
  }

  if ($okCount -ge 6) {
    Write-Host "Verification success ($okCount/7 online)" -ForegroundColor Green
    Send-Telegram "AIVANA AutoTrigger: Verification success ($okCount/7)."
    Notify "AIVANA AutoTrigger" "Verification success ($okCount/7)"
  } else {
    Write-Host "Verification incomplete ($okCount/7)" -ForegroundColor Yellow
    Send-Telegram "AIVANA AutoTrigger: Only $okCount/7 guides online."
    Notify "AIVANA AutoTrigger" "Some guides missing."
  }
}

# --- Scheduler Registration (Silent Mode) ---
function Register-AutoTrigger {
  $scriptPath = $MyInvocation.MyCommand.Path
  $taskName = "AIVANA AutoTrigger Daemon"
  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
  $trigger = New-ScheduledTaskTrigger -Daily -At 03:00
  Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Daily AIVANA AutoFix and Verify" -Force
  Write-Host "Scheduler Registered: $taskName (runs daily 03:00 AM)" -ForegroundColor Cyan
}

# --- MAIN ---
Run-AutoFix
Register-AutoTrigger
