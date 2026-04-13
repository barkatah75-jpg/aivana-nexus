# ===============================================
#  AIVANA_TODOLIST_AutoHeal_v9.9.2_SilentDaemon.ps1
#  (Self-heal, multilingual verification + Telegram alert)
# ===============================================

chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- CONFIG ---
$ftpHost   = "ftp://89.117.188.202"
$ftpUser   = "u786522790.todolist.barkataiautomation.in"
$ftpPass   = "M1$wc$0cX>G~QfYt"
$siteURL   = "https://todolist.barkataiautomation.in"
$uploadDir = "public_html/guides"

$tgCred = @{
    token = "7971210207:AAGxszjrHx60yVv9dtgy-Ohv-6BiRVnJgNw"
    chat  = "1875063875"
}

$logDir = "$env:USERPROFILE\AIVANA_Logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = "$logDir\AutoHeal_$(Get-Date -Format yyyyMMdd_HHmmss).log"

function Log($msg) {
    $t = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    $line = "$t  $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# --- FTP Upload ---
function Upload-FileToFtp {
    param($localPath, $remotePath)
    try {
        foreach ($mode in @($true, $false)) {
            $req = [System.Net.FtpWebRequest]::Create("$ftpHost/$remotePath")
            $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
            $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
            $req.UseBinary = $true
            $req.UsePassive = $mode
            $req.EnableSsl = $false
            $bytes = [System.IO.File]::ReadAllBytes($localPath)
            $stream = $req.GetRequestStream()
            $stream.Write($bytes,0,$bytes.Length)
            $stream.Close()
            Log "Uploaded (Passive=$mode): $(Split-Path $localPath -Leaf)"
            return $true
        }
    }
    catch {
        Log "Upload failed for $(Split-Path $localPath -Leaf): $($_.Exception.Message)"
        return $false
    }
}

# --- Generate Multilingual Guides ---
function Generate-Guides {
    $langs = @("EN","HI","ES","FR","AR","ZH","JP")
    $temp = "$env:TEMP\AIVANA_TODOLIST_AUTOHEAL"
    if (!(Test-Path $temp)) { New-Item -ItemType Directory -Force -Path $temp | Out-Null }

    foreach ($l in $langs) {
        $path = "$temp\AIVANA_AI_Global_Identity_Guide_$l.pdf"
        "AIVANA Global Identity Guide ($l)`r`nAuto-generated: $(Get-Date)" | Out-File $path -Encoding UTF8
    }
    return $temp
}

# --- Verify Site Links ---
function Verify-Site {
    param($langs)
    $ok = 0
    foreach ($l in $langs) {
        $url = "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf"
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
            if ($r.StatusCode -eq 200) {
                Log "OK → $l"
                $ok++
            } else {
                Log "ERR → $l (code $($r.StatusCode))"
            }
        } catch {
            Log "ERR → $l (missing)"
        }
    }
    return $ok
}

# --- Telegram Notify (Fixed v9.9.2) ---
function Send-Telegram {
    param($text)
    try {
        $uri = "https://api.telegram.org/bot$($tgCred.token)/sendMessage"
        $body = @{
            chat_id = $tgCred.chat
            text    = $text
        }
        $resp = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        if ($resp.ok -eq $true) {
            Log "✅ Telegram sent successfully."
        } else {
            Log "⚠️ Telegram responded but not OK."
        }
    } catch {
        Log "❌ Telegram send failed: $($_.Exception.Message)"
    }
}

# --- MAIN EXECUTION ---
Log "==== AIVANA AutoHeal v9.9.2 ===="
$langs = @("EN","HI","ES","FR","AR","ZH","JP")
$tempDir = Generate-Guides
Log "Generated multilingual guides."

foreach ($pdf in Get-ChildItem $tempDir -Filter *.pdf) {
    $remote = "$uploadDir/$($pdf.Name)"
    Upload-FileToFtp $pdf.FullName $remote | Out-Null
}

$ok = Verify-Site $langs
Log "Verification done. Online: $ok/7"

Send-Telegram "✅ AIVANA AutoHeal complete.`nGuides online: $ok/7`n$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Log "==== AutoHeal completed ===="
exit
