# ============================================================
# AIVANA_TODOLIST_AutoFix.ps1  (v9.5.1)
# Purpose: create missing multilingual guide PDFs (by copying English),
#          restore basic GitHub workflow YAMLs, upload via FTP,
#          verify, notify via Telegram, save log.
# ============================================================

chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

# -------- CONFIG (adjust only if needed) ---------------------
$sourceDir = "C:\Users\LAPPYHUB\AIVANA_TODOLISTAIAUTOMATION_AUTO_DEPLOY_v1"
# if above path differs, the script will still try to use the local guides found under $sourceDir\guides
$ftpHost   = "ftp://ftp.todolist.barkataiautomation.in"
$ftpUser   = "u786522790.todolist.barkataiautomation.in"
$uploadRoot = "public_html"
$siteURL   = "https://todolist.barkataiautomation.in"
$logDir    = "$env:USERPROFILE\AIVANA_Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }
$logFile = "$logDir\autofix_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# security files (uses same AES helpers as other scripts)
$keyFile  = "$env:USERPROFILE\AIVANA_AES.key"
$authFile = "$env:USERPROFILE\AIVANA_TelegramAuth.enc"
$ftpCred  = "$env:USERPROFILE\AIVANA_FTPAuth.enc"

# -------- AES helpers ---------------------------------------
function New-AesKeyIfMissing($path) {
    if (-not (Test-Path $path)) {
        $b = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
        [IO.File]::WriteAllBytes($path, $b)
    }
    return [IO.File]::ReadAllBytes($path)
}
function Encrypt-Text($plain, [byte[]]$key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.GenerateIV()
    $enc = $aes.CreateEncryptor().TransformFinalBlock([Text.Encoding]::UTF8.GetBytes($plain),0,$plain.Length)
    return [Convert]::ToBase64String($aes.IV + $enc)
}
function Decrypt-Text($encText, [byte[]]$key) {
    $data = [Convert]::FromBase64String($encText)
    $aes  = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.IV = $data[0..15]
    $dec = $aes.CreateDecryptor().TransformFinalBlock($data,16,$data.Length-16)
    return [Text.Encoding]::UTF8.GetString($dec)
}

# -------- UI / Telegram helpers -----------------------------
function Show-Notification($title, $msg) {
    try {
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.BalloonTipTitle = $title; $n.BalloonTipText = $msg
        $n.Visible = $true; $n.ShowBalloonTip(3500)
        Start-Sleep -Milliseconds 1200; $n.Dispose()
    } catch {}
}
function Send-Telegram($token, $chatId, $msg) {
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" -Method Post -Body @{ chat_id = $chatId; text = $msg } -TimeoutSec 15 | Out-Null
        return $true
    } catch { return $false }
}

# -------- load Telegram creds (if present) -------------------
$key = New-AesKeyIfMissing $keyFile
if (Test-Path $authFile) {
    try {
        $json = Decrypt-Text (Get-Content $authFile -Raw) $key | ConvertFrom-Json
        $botToken = $json.token; $chatId = $json.chatid
    } catch {}
}

# -------- load or ask FTP password ---------------------------
function Get-FtpPassword {
    if (Test-Path $ftpCred) {
        try { return (Decrypt-Text (Get-Content $ftpCred -Raw) $key | ConvertFrom-Json).pass } catch {}
    }
    $p = Read-Host "Enter FTP password"
    $enc = Encrypt-Text (@{ pass = $p } | ConvertTo-Json -Compress) $key
    Set-Content -Path $ftpCred -Value $enc -Force
    return $p
}
$ftpPass = Get-FtpPassword

# -------- FTP helpers ---------------------------------------
function Test-FTP-Login($host, $user, $pass, $ssl) {
    try {
        $req = [System.Net.FtpWebRequest]::Create($host.TrimEnd('/') + '/')
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
        $req.UsePassive = $true; $req.UseBinary = $true; $req.EnableSsl = $ssl
        $res = $req.GetResponse(); $res.Close(); return $true
    } catch { return $false }
}
function Upload-FileToFtp($uri, $localPath, $user, $pass, $ssl) {
    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
        $req.UseBinary = $true; $req.UsePassive = $true; $req.EnableSsl = $ssl
        $bytes = [System.IO.File]::ReadAllBytes($localPath)
        $stream = $req.GetRequestStream(); $stream.Write($bytes,0,$bytes.Length); $stream.Close()
        return $true
    } catch { return $_.Exception.Message }
}

# -------- AutoFix main --------------------------------------
Start-Transcript -Path $logFile -Force
try {
    Write-Host "`n=== AIVANA TODOLIST AutoFix (v9.5.1) ===" -ForegroundColor Cyan
    Show-Notification "AIVANA AutoFix" "Starting fix..."
    if ($botToken -and $chatId) { Send-Telegram $botToken $chatId "🔧 AutoFix started for TODOLIST on $env:COMPUTERNAME" }

    # locate english guide in local source
    $localGuidesDir = Join-Path $sourceDir "guides"
    $englishPdf = Join-Path $localGuidesDir "AIVANA_AI_Global_Identity_Guide_English.pdf"
    if (-not (Test-Path $englishPdf)) {
        Write-Host "ERROR: local English guide not found at $englishPdf" -ForegroundColor Red
        throw "Local English guide not found. Place English PDF under $localGuidesDir and re-run."
    } else {
        Write-Host "Found local English guide -> $englishPdf"
    }

    # languages to create (codes)
    $langs = @("ES","FR","AR","ZH","JP")
    $created = @()
    foreach ($lang in $langs) {
        $tmp = Join-Path $env:TEMP ("AIVANA_Guide_" + $lang + ".pdf")
        Copy-Item -Path $englishPdf -Destination $tmp -Force
        # optional: we could embed a short metadata file; for now we copy English as placeholder
        Write-Host "Created placeholder for $lang -> $tmp"
        $created += $tmp
    }

    # create workflow YAMLs locally (PowerShell-safe, base64 encoded)
$workflowsLocal = Join-Path $env:TEMP "aivana_workflows"
if (-not (Test-Path $workflowsLocal)) { New-Item -Path $workflowsLocal -ItemType Directory | Out-Null }

# --- aivana-auto-upload.yml ---
$aivanaYamlBase64 = @"
bmFtZTogQUlWQU5BIEF1dG8gVXBsb2FkCm9uOgogIHdvcmtmbG93X2Rpc3BhdGNoOgogIHB1c2g6CiAgICBicmFuY2hlczogWyBtYWluIF0Kam9iczoKICB1cGxvYWQ6CiAgICBydW5zLW9uOiB1YnVudHUtbGF0ZXN0CiAgICBzdGVwczoKICAgICAgLSB1c2VzOiBhY3Rpb25zL2NoZWNrb3V0QHY0CiAgICAgIC0gbmFtZTogWmlwIGZpbGVzCiAgICAgICAgcnVuOiB6aXAgLXIgZGVwbG95X3BhY2thZ2UuemlwIC4KICAgICAgLSBuYW1lOiBVcGxvYWQgdG8gRlRQIChleGFtcGxlKQogICAgICAgIHVzZXM6IFNhbUtpcmtsYW5kL0ZUUC1EZXBsb3ktQWN0aW9uQDQuNC4wCiAgICAgICAgd2l0aDoKICAgICAgICAgIHNlcnZlcjogODkuMTE3LjE4OC4yMDIKICAgICAgICAgIHVzZXJuYW1lOiB1Nzg2NTIyNzkwLnRvZG9saXN0LmJhcmthdGFpYXV0b21hdGlvbi5pbgogICAgICAgICAgcGFzc3dvcmQ6ICR7eyBzZWNyZXRzLkZUUF9QQVNTV09SRCB9fQogICAgICAgICAgbG9jYWwtZGlyOiAu
"@
[IO.File]::WriteAllBytes( (Join-Path $workflowsLocal "aivana-auto-upload.yml"), [Convert]::FromBase64String($aivanaYamlBase64))
Write-Host "Generated workflow -> $(Join-Path $workflowsLocal 'aivana-auto-upload.yml')"

# --- hostinger-deploy.yml ---
$hostingerYamlBase64 = @"
bmFtZTogSG9zdGluZ2VyIERlcGxveQpvbjoKICB3b3JrZmxvd19kaXNwYXRjaDoKam9iczoKICBkZXBsb3k6CiAgICBydW5zLW9uOiB1YnVudHUtbGF0ZXN0CiAgICBzdGVwczoKICAgICAgLSB1c2VzOiBhY3Rpb25zL2NoZWNrb3V0QHY0CiAgICAgIC0gbmFtZTogWmlwIGFuZCBVcGxvYWQgKGV4YW1wbGUpCiAgICAgICAgcnVuOiB8CiAgICAgICAgICB6aXAgLXIgZGVwbG95X3BhY2thZ2UuemlwIC4KICAgICAgICAgICMgRlRQIHVwbG9hZCBzdGVwIGNhbiBiZSBhZGRlZCBoZXJlIG9yIHVzZSBhY3Rpb24=
"@
[IO.File]::WriteAllBytes( (Join-Path $workflowsLocal "hostinger-deploy.yml"), [Convert]::FromBase64String($hostingerYamlBase64))
Write-Host "Generated workflow -> $(Join-Path $workflowsLocal 'hostinger-deploy.yml')"

name: Hostinger Deploy
on:
  workflow_dispatch:
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Zip and Upload (example)
        run: |
          zip -r deploy_package.zip .
          # FTP upload step can be added here or use action
'@
Set-Content -Path $hostingerYamlPath -Value $hostingerYaml -Encoding UTF8
Write-Host "Generated workflow -> $hostingerYamlPath"


    $hostingerYamlPath = Join-Path $workflowsLocal "hostinger-deploy.yml"
    $hostingerYaml = @"
name: Hostinger Deploy
on:
  workflow_dispatch:
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Zip and Upload (example)
        run: |
          zip -r deploy_package.zip .
          # FTP upload step can be added here or use action
"@
    Set-Content -Path $hostingerYamlPath -Value $hostingerYaml -Encoding UTF8
    Write-Host "Generated workflow -> $hostingerYamlPath"

    # Determine which FTP SSL mode works
    $sslMode = $false
    if (Test-FTP-Login $ftpHost $ftpUser $ftpPass $false) { $sslMode = $false } elseif (Test-FTP-Login $ftpHost $ftpUser $ftpPass $true) { $sslMode = $true } else { throw "FTP login failed for both SSL modes." }
    Write-Host "Using FTP SSL mode: $sslMode"

    # upload guides
    foreach ($file in $created) {
        $fname = Split-Path $file -Leaf
        $remoteUri = "$ftpHost/$uploadRoot/guides/$fname"
        $u = Upload-FileToFtp $remoteUri $file $ftpUser $ftpPass $sslMode
        if ($u -eq $true) { Write-Host "Uploaded -> $remoteUri" } else { Write-Host "Upload failed -> $remoteUri : $u" }
    }
    # upload existing English and Hindi (if present locally)
    $localEnglish = $englishPdf
    if (Test-Path $localEnglish) {
        $remote = "$ftpHost/$uploadRoot/guides/$(Split-Path $localEnglish -Leaf)"
        $res = Upload-FileToFtp $remote $localEnglish $ftpUser $ftpPass $sslMode
        Write-Host "Uploaded English -> $remote : $res"
    }
    $localHindi = Join-Path $localGuidesDir "AIVANA_AI_Global_Identity_Guide_Hindi.pdf"
    if (Test-Path $localHindi) {
        $remote = "$ftpHost/$uploadRoot/guides/$(Split-Path $localHindi -Leaf)"
        $res = Upload-FileToFtp $remote $localHindi $ftpUser $ftpPass $sslMode
        Write-Host "Uploaded Hindi -> $remote : $res"
    }

    # upload workflow files
    $remoteWorkflowBase = "$ftpHost/$uploadRoot/.github/workflows"
    foreach ($wf in Get-ChildItem -Path $workflowsLocal -File) {
        $remote = "$remoteWorkflowBase/$($wf.Name)"
        $r = Upload-FileToFtp $remote $wf.FullName $ftpUser $ftpPass $sslMode
        if ($r -eq $true) { Write-Host "Uploaded workflow -> $remote" } else { Write-Host "Upload failed -> $remote : $r" }
    }

    # verify via HTTP
    Start-Sleep -Seconds 3
    $verifyFailures = @()
    # check guides
    $checkList = @()
    $checkList += ("/guides/AIVANA_AI_Global_Identity_Guide_English.pdf")
    $checkList += ("/guides/AIVANA_AI_Global_Identity_Guide_Hindi.pdf")
    foreach ($lang in $langs) { $checkList += ("/guides/AIVANA_AI_Global_Identity_Guide_$lang.pdf") }
    foreach ($p in $checkList) {
        try {
            $u = "$siteURL$p"
            $resp = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 12
            if ($resp.StatusCode -eq 200) { Write-Host "Verified: $p" } else { Write-Host "Verify fail: $p"; $verifyFailures += $p }
        } catch { Write-Host "Verify error: $p => $($_.Exception.Message)"; $verifyFailures += $p }
    }
    # check workflows
    $wfPaths = @("/.github/workflows/aivana-auto-upload.yml","/.github/workflows/hostinger-deploy.yml")
    foreach ($w in $wfPaths) {
        try { $u = "$siteURL$w"; $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 12; if ($r.StatusCode -eq 200) { Write-Host "Verified: $w" } else { Write-Host "Verify fail: $w"; $verifyFailures += $w } } catch { Write-Host "Verify error: $w => $($_.Exception.Message)"; $verifyFailures += $w }
    }

    # final notification
    if ($verifyFailures.Count -eq 0) {
        Write-Host "`nAutoFix completed successfully." -ForegroundColor Green
        Show-Notification "AIVANA AutoFix" "All fixes applied and verified."
        if ($botToken -and $chatId) { Send-Telegram $botToken $chatId "✅ AutoFix completed successfully for TODOLIST. All guides and workflows restored." }
    } else {
        Write-Host "`nAutoFix completed with verification failures:" -ForegroundColor Yellow
        $verifyFailures | ForEach-Object { Write-Host $_ }
        Show-Notification "AIVANA AutoFix" "Completed with verification issues. Check log."
        if ($botToken -and $chatId) { Send-Telegram $botToken $chatId "⚠️ AutoFix completed but some files failed verification: $($verifyFailures -join ', ')" }
    }

} catch {
    Write-Host "Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    Show-Notification "AIVANA AutoFix" "Fatal error: $($_.Exception.Message)"
    if ($botToken -and $chatId) { Send-Telegram $botToken $chatId "❌ AutoFix fatal error: $($_.Exception.Message)" }
} finally {
    Stop-Transcript
    Write-Host "`nLog saved -> $logFile"
    Show-Notification "AIVANA AutoFix" "Finished (see log)"
}
