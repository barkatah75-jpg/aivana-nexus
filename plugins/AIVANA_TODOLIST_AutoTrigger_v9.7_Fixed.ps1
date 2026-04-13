# ===========================================
#  AIVANA_TODOLIST_AutoTrigger_v9.7_Fixed.ps1
#  (Self-start, daily feature-check + auto-fix + Telegram alert)
# ===========================================

chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- CONFIG ---
$ftpHost  = "ftp://89.117.188.202"
$ftpUser  = "u786522790.todolist.barkataiautomation.in"
$siteURL  = "https://todolist.barkataiautomation.in"
$uploadRoot = "public_html"
$ftpPass  = "M1$wc$0cX>G~QfYt"  # optional: replace with Read-Host for security
$telegramToken = "YOUR_TELEGRAM_BOT_TOKEN"
$chatId = "YOUR_CHAT_ID"
$tempRoot = "$env:TEMP\AIVANA_TODOLIST_AUTOFIX"
$logFile = "$env:USERPROFILE\AIVANA_Logs\AutoTrigger_$(Get-Date -Format yyyyMMdd_HHmmss).log"
if (-not (Test-Path (Split-Path $logFile))) { New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null }

# --- Telegram Notify ---
function Send-Telegram($msg) {
  try {
    $u = "https://api.telegram.org/bot$telegramToken/sendMessage"
    $body = @{ chat_id=$chatId; text=$msg }
    Invoke-RestMethod -Uri $u -Method POST -Body $body | Out-Null
  } catch {}
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

# --- FTP Upload (Hybrid Active/Passive Mode) ---
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
      $bytes = [System.IO.File]::ReadAllBytes($localPath)
      $stream = $req.GetRequestStream()
      $stream.Write($bytes,0,$bytes.Length)
      $stream.Close()
      Write-Host "Uploaded -> $($localPath | Split-Path -Leaf) (Passive=$mode)" -ForegroundColor Green
      return $true
    } catch {
      Write-Host "Failed (Passive=$mode): $($localPath | Split-Path -Leaf): $($_.Exception.Message)" -ForegroundColor Yellow
      Start-Sleep -Seconds 2
    }
  }
  return $false
}


# --- Feature Check + AutoFix ---
function Run-AutoFix {
  "=== AIVANA AutoTrigger Run @ $(Get-Date) ===" | Out-File $logFile
  if (-not (Test-Path $tempRoot)) { New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null }

  # --- Generate Guides ---
  $langs = @("EN","HI","ES","FR","AR","ZH","JP")
  foreach ($l in $langs) {
    $pdfPath = Join-Path $tempRoot "AIVANA_AI_Global_Identity_Guide_$l.pdf"
    "AIVANA Global Identity Guide ($l)`r`nAuto-generated $(Get-Date)" | Out-File $pdfPath -Encoding UTF8
  }

  # --- Upload All ---
  foreach ($pdf in Get-ChildItem $tempRoot -Filter *.pdf) {
    $rel = "/$uploadRoot/guides/" + $pdf.Name
    $uri = "$ftpHost/$rel"
    if (-not (Upload-FileToFtp $uri $pdf.FullName $ftpUser $ftpPass)) {
      # fallback upload to alternate path
      $altUri = "$ftpHost/$uploadRoot/aivana_ci/" + $pdf.Name
      Upload-FileToFtp $altUri $pdf.FullName $ftpUser $ftpPass | Out-Null
    }
  }

  # --- Verify site links ---
  $okCount = 0
  foreach ($l in $langs) {
    $url = "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf"
    try {
      $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
      if ($r.StatusCode -eq 200) { $okCount++ }
    } catch {}
  }

  if ($okCount -ge 6) {
    Write-Host "Verification success ($okCount/7 online)"
    Send-Telegram "AIVANA AutoTrigger: $okCount/7 guides online OK."
    Notify "AIVANA AutoTrigger" "Verification success ($okCount/7)"
  } else {
    Write-Host "Verification incomplete ($okCount/7)"
    Send-Telegram "AIVANA AutoTrigger: Only $okCount/7 guides online!"
    Notify "AIVANA AutoTrigger" "Some guides missing!"
  }
}

# --- Scheduler Registration ---
function Register-AutoTrigger {
  $scriptPath = $MyInvocation.MyCommand.Path
  $taskName = "AIVANA AutoTrigger Daemon"
  $taskCmd = "powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`""
  $trigger = New-ScheduledTaskTrigger -Daily -At 03:00
  $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
  Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Daily AIVANA AutoFix and Verify" -Force
  Write-Host "Scheduler Registered: $taskName (runs daily 03:00 AM)"
}

# --- MAIN ---
Run-AutoFix
Register-AutoTrigger
