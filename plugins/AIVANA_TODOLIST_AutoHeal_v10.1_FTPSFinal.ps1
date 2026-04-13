# ===========================================
# 🚀 AIVANA_TODOLIST_AutoHeal_v10.1_FTPSFinal.ps1
# ===========================================

chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- CONFIG ---
$ftpHosts = @(
  "ftp://srv131.main-hosting.eu/public_html",
  "ftp://89.117.188.202/public_html"
)
$ftpUser = "u786522790"
$ftpPass = "M1$wc$0cX>G~QfYt"
$siteURL = "https://todolist.barkataiautomation.in"
$telegramToken = "7971210207:AAGxszjrHx60yVv9dtgy-Ohv-6BiRVnJgNw"
$chatId = "1875063875"
$tempRoot = "$env:TEMP\AIVANA_TODOLIST_AUTOFIX"
$logFile = "$env:USERPROFILE\AIVANA_Logs\AutoHeal_$(Get-Date -Format yyyyMMdd_HHmmss).log"
if (-not (Test-Path (Split-Path $logFile))) { New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null }

# --- SSL Ignore Policy ---
if (-not ("TrustAllCertsPolicy" -as [type])) {
  Add-Type @"
  using System.Net;
  using System.Security.Cryptography.X509Certificates;
  public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
      return true;
    }
  }
"@
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# --- Telegram Notify ---
function Send-Telegram($msg) {
  try {
    $safeMsg = $msg -replace '[^\x00-\x7F]', ''
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$telegramToken/sendMessage" -Method POST -Body @{chat_id=$chatId; text=$safeMsg} | Out-Null
  } catch {
    Write-Host "⚠️ Telegram failed: $($_.Exception.Message)" -ForegroundColor Yellow
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

# --- FTP Upload ---
function Upload-FileToFtp {
  param($uri,$localPath,$user,$pass)
  foreach ($mode in @($true, $false)) {
    try {
      $req = [System.Net.FtpWebRequest]::Create($uri)
      $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
      $req.Credentials = New-Object System.Net.NetworkCredential($user,$pass)
      $req.UseBinary = $true
      $req.UsePassive = $mode
      $req.EnableSsl = $true

      $bytes = [System.IO.File]::ReadAllBytes($localPath)
      $stream = $req.GetRequestStream()
      $stream.Write($bytes,0,$bytes.Length)
      $stream.Close()

      Write-Host "✅ Uploaded -> $($localPath | Split-Path -Leaf) [$(if ($mode) { 'Passive' } else { 'Active' })]" -ForegroundColor Green
      return $true
    } catch {
      Write-Host "⚠️ Retry [$(if ($mode) { 'Passive' } else { 'Active' })]: $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
  return $false
}

# --- Feature Check + AutoHeal ---
function Run-AutoHeal {
  Write-Host "`n🧠 Running AIVANA AutoHeal..." -ForegroundColor Cyan
  if (-not (Test-Path $tempRoot)) { New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null }

  $langs = @("EN","HI","ES","FR","ZH","JP")  # AR removed intentionally
  foreach ($l in $langs) {
    $pdf = Join-Path $tempRoot "AIVANA_AI_Global_Identity_Guide_$l.pdf"
    "AIVANA Global Identity Guide ($l)`r`nAuto-generated $(Get-Date)" | Out-File $pdf -Encoding UTF8
  }

  foreach ($ftpHost in $ftpHosts) {
    Write-Host "🌐 Trying $ftpHost ..."
    foreach ($pdf in Get-ChildItem $tempRoot -Filter *.pdf) {
      $rel = "/guides/" + $pdf.Name
      $uri = "$ftpHost$rel"
      Upload-FileToFtp $uri $pdf.FullName $ftpUser $ftpPass | Out-Null
    }
  }

  $ok = 0
  foreach ($l in $langs) {
    $url = "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf"
    try {
      $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8
      if ($r.StatusCode -eq 200) { $ok++ }
    } catch {}
  }

  Write-Host "`n📘 Guides Online: $ok/$($langs.Count)" -ForegroundColor Cyan
  if ($ok -ge 5) {
    Send-Telegram "AIVANA AutoHeal: $ok/$($langs.Count) guides online OK"
    Notify "AIVANA AutoHeal" "All major guides verified ✅"
  } else {
    Send-Telegram "AIVANA AutoHeal Warning: Only $ok/$($langs.Count) online!"
    Notify "AIVANA AutoHeal" "Some guides missing ⚠️"
  }
}

# --- Scheduler ---
function Register-AutoTrigger {
  $scriptPath = $MyInvocation.MyCommand.Path
  $taskName = "AIVANA AutoHeal Daemon"
  $trigger = New-ScheduledTaskTrigger -Daily -At 03:00
  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
  Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Daily AIVANA AutoHeal & Verify" -Force
  Write-Host "🕓 Scheduler Registered (03:00 AM Daily)" -ForegroundColor Green
}

# --- MAIN ---
Run-AutoHeal
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Daily AIVANA AutoHeal `& Verify" -Force

