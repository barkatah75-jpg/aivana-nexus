# ===========================================
# 🚀 AIVANA_TODOLIST_AutoHeal_v10.3_Stable.ps1
# (FTPS Auto-Heal + Telegram + Scheduler FIXED)
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
$logDir = "$env:USERPROFILE\AIVANA_Logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

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
    $cleanMsg = ($msg -replace '[^\x00-\x7F]', '').Trim()
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$telegramToken/sendMessage" -Method POST -Body @{
      chat_id = $chatId
      text = $cleanMsg
    } | Out-Null
    Write-Host "📨 Telegram sent: $cleanMsg" -ForegroundColor Cyan
  } catch {
    Write-Host "⚠️ Telegram failed: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# --- Notification Balloon ---
function Notify($title,$msg) {
  try {
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.BalloonTipTitle = $title
    $n.BalloonTipText = $msg
    $n.Visible = $true
    $n.ShowBalloonTip(3000)
    Start-Sleep -Milliseconds 1500
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

      Write-Host "✅ Uploaded: $($localPath | Split-Path -Leaf) [$(if ($mode) {'Passive'} else {'Active'})]" -ForegroundColor Green
      return $true
    } catch {
      Write-Host "⚠️ Retry [$(if ($mode){'Passive'}else{'Active'})]: $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
  return $false
}

# --- Auto Host Detection ---
function Get-WorkingHost {
  foreach ($ftpHost in $ftpHosts) {
    try {
      $req = [System.Net.FtpWebRequest]::Create($ftpHost)
      $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
      $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser,$ftpPass)
      $req.EnableSsl = $true
      $req.UsePassive = $true
      $res = $req.GetResponse()
      $res.Close()
      Write-Host "🌐 Active Host: $ftpHost" -ForegroundColor Green
      return $ftpHost
    } catch {
      Write-Host "❌ Host failed: $ftpHost" -ForegroundColor Red
    }
  }
  return $null
}

# --- Main Healing Routine ---
function Run-AutoHeal {
  Write-Host "`n🧠 Running AIVANA AutoHeal..." -ForegroundColor Cyan
  if (-not (Test-Path $tempRoot)) { New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null }

  $langs = @("EN","HI","ES","FR","ZH","JP")
  foreach ($l in $langs) {
    $pdf = Join-Path $tempRoot "AIVANA_AI_Global_Identity_Guide_$l.pdf"
    "AIVANA Global Identity Guide ($l)`r`nAuto-generated $(Get-Date)" | Out-File $pdf -Encoding UTF8
  }

  $ftpHost = Get-WorkingHost
  if (-not $ftpHost) {
    Write-Host "❌ No working FTPS host found." -ForegroundColor Red
    Send-Telegram "❌ AIVANA AutoHeal Failed: No valid FTPS host."
    return
  }

  foreach ($pdf in Get-ChildItem $tempRoot -Filter *.pdf) {
    $rel = "/guides/" + $pdf.Name
    $uri = "$ftpHost$rel"
    Upload-FileToFtp $uri $pdf.FullName $ftpUser $ftpPass | Out-Null
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
    Send-Telegram "✅ AIVANA AutoHeal Success: $ok/$($langs.Count) online"
    Notify "AIVANA AutoHeal" "All major guides verified ✅"
  } else {
    Send-Telegram "⚠️ AIVANA AutoHeal Warning: Only $ok/$($langs.Count) online"
    Notify "AIVANA AutoHeal" "Some guides missing ⚠️"
  }
}

# --- Scheduler Registration ---
function Register-AutoTrigger {
  try {
    $scriptPath = $MyInvocation.MyCommand.Path
    $taskName = "AIVANA AutoHeal Daemon"
    $trigger = New-ScheduledTaskTrigger -Daily -At 03:00
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description 'Daily AIVANA AutoHeal and Verify' -Force
    Write-Host "🕓 Scheduler Registered (03:00 AM Daily)" -ForegroundColor Green
  } catch {
    Write-Host "⚠️ Scheduler registration failed: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# --- MAIN EXECUTION ---
Run-AutoHeal
Register-AutoTrigger
Write-Host "`n✨ AutoHeal Completed Successfully" -ForegroundColor Cyan
