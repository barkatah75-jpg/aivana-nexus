# AIVANA_TODOLIST_AutoHeal_v9.9.1.ps1
# AutoHeal + Secure Telegram Notification + AES Encrypted Credentials
chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------- CONFIG ----------------
$siteURL = "https://todolist.barkataiautomation.in"
$ftpCandidates = @(
    "ftp://89.117.188.202",
    "ftp://ftp.todolist.barkataiautomation.in",
    "ftp://89.117.188.202/public_html",
    "ftp://89.117.188.202/domains/todolist.barkataiautomation.in/public_html"
)
$langs = @("EN","HI","ES","FR","AR","ZH","JP")
$dirs = @{
    Temp = "$env:TEMP\AIVANA_TODOLIST_AUTOHEAL"
    Keys = "$env:USERPROFILE\.aivana"
    Logs = "$env:USERPROFILE\AIVANA_Logs"
}
foreach ($d in $dirs.Values) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }

$aesKeyFile = Join-Path $dirs.Keys "AIVANA_AES.key"
$ftpCredFile = Join-Path $dirs.Keys "AIVANA_FTPAuth.enc"
$tgCredFile  = Join-Path $dirs.Keys "AIVANA_Telegram.enc"
$logFile = Join-Path $dirs.Logs ("autoheal_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# ---------------- AES Utils ----------------
function New-AesKeyIfMissing($p){if(-not(Test-Path $p)){ $b=New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [IO.File]::WriteAllBytes($p,$b)}; [IO.File]::ReadAllBytes($p)}
$key = New-AesKeyIfMissing $aesKeyFile
function Encrypt-Text($t,[byte[]]$k){$a=[Security.Cryptography.Aes]::Create();$a.Key=$k;$a.GenerateIV();$b=[Text.Encoding]::UTF8.GetBytes($t);$c=$a.CreateEncryptor().TransformFinalBlock($b,0,$b.Length);[Convert]::ToBase64String($a.IV+$c)}
function Decrypt-Text($t,[byte[]]$k){$d=[Convert]::FromBase64String($t);$a=[Security.Cryptography.Aes]::Create();$a.Key=$k;$a.IV=$d[0..15];$b=$a.CreateDecryptor().TransformFinalBlock($d,16,$d.Length-16);[Text.Encoding]::UTF8.GetString($b)}

# ---------------- Load/Save Creds ----------------
function Save-Enc($p,$data){$enc=Encrypt-Text ($data|ConvertTo-Json -Compress) $key;Set-Content $p $enc -Force}
function Load-Enc($p){if(Test-Path $p){try{(Decrypt-Text (Get-Content $p -Raw) $key)|ConvertFrom-Json}catch{}}}

# ---------------- Log Helper ----------------
function Log($m){$t="{0} {1}" -f (Get-Date -Format "s"),$m;$t|Tee-Object -FilePath $logFile -Append}

# ---------------- FTP Test ----------------
function Test-Ftp($base,$u,$p){try{$r=[Net.FtpWebRequest]::Create($base);$r.Method=[Net.WebRequestMethods+Ftp]::ListDirectory;$r.Credentials=New-Object Net.NetworkCredential($u,$p);$r.GetResponse().Close();$true}catch{$false}}

# ---------------- FTP Upload ----------------
function Upload-FTP($uri,$path,$u,$p){
  try{
    $r=[Net.FtpWebRequest]::Create($uri)
    $r.Method=[Net.WebRequestMethods+Ftp]::UploadFile
    $r.Credentials=New-Object Net.NetworkCredential($u,$p)
    $r.UseBinary=$true;$r.UsePassive=$true;$r.EnableSsl=$false
    $b=[IO.File]::ReadAllBytes($path)
    $s=$r.GetRequestStream();$s.Write($b,0,$b.Length);$s.Close()
    Log "Uploaded: $(Split-Path $path -Leaf)"
    $true
  }catch{Log "Fail: $(Split-Path $path -Leaf) → $($_.Exception.Message)";$false}
}

# ---------------- Telegram ----------------
function Send-TG($t,$c,$m){
  try{Invoke-RestMethod -Uri "https://api.telegram.org/bot$t/sendMessage" -Method Post -Body @{chat_id=$c;text=$m}|Out-Null}catch{Log "TG send failed"}
}

# ---------------- File Generation ----------------
function Generate-Files($r){
  if(-not(Test-Path $r)){New-Item -ItemType Directory $r|Out-Null}
  $g=Join-Path $r "guides";if(-not(Test-Path $g)){New-Item $g -ItemType Directory|Out-Null}
  foreach($l in $langs){"AIVANA Guide ($l)`r`nAuto-generated $(Get-Date)"|Out-File (Join-Path $g "AIVANA_AI_Global_Identity_Guide_$l.pdf")}
  $a=Join-Path $r "assets";$f=Join-Path $r "favicons"
  New-Item $a -ItemType Directory -Force|Out-Null;New-Item $f -ItemType Directory -Force|Out-Null
  "<svg xmlns='http://www.w3.org/2000/svg'><rect width='100%' height='100%' fill='green'/></svg>"|Out-File (Join-Path $a "app_icon_128.svg")
  "<svg xmlns='http://www.w3.org/2000/svg'><circle cx='16' cy='16' r='16' fill='green'/></svg>"|Out-File (Join-Path $f "favicon-32.svg")
  Log "Generated sample guides and assets."
}

# ---------------- Main ----------------
Log "==== AIVANA AutoHeal v9.9.1 ===="

$ftpCred=Load-Enc $ftpCredFile
if(-not$ftpCred){
  $u=Read-Host "FTP username"
  $p=Read-Host "FTP password"
  Save-Enc $ftpCredFile @{user=$u;pass=$p}
  $ftpCred=@{user=$u;pass=$p}
}
$tgCred=Load-Enc $tgCredFile
if(-not$tgCred){
  $t=Read-Host "Telegram Bot Token"
  $c=Read-Host "Telegram Chat ID"
  Save-Enc $tgCredFile @{token=$t;chat=$c}
  $tgCred=@{token=$t;chat=$c}
}

$ftpBase=$null
foreach($b in $ftpCandidates){if(Test-Ftp $b $ftpCred.user $ftpCred.pass){$ftpBase=$b;break}}
if(-not$ftpBase){Log "No FTP base valid";exit}

Generate-Files $dirs.Temp

foreach($f in Get-ChildItem "$($dirs.Temp)\guides" -File){Upload-FTP "$ftpBase/public_html/guides/$($f.Name)" $f.FullName $ftpCred.user $ftpCred.pass|Out-Null}
foreach($f in Get-ChildItem "$($dirs.Temp)\assets" -File){Upload-FTP "$ftpBase/public_html/assets/$($f.Name)" $f.FullName $ftpCred.user $ftpCred.pass|Out-Null}
foreach($f in Get-ChildItem "$($dirs.Temp)\favicons" -File){Upload-FTP "$ftpBase/public_html/favicons/$($f.Name)" $f.FullName $ftpCred.user $ftpCred.pass|Out-Null}

$ok=0
foreach($l in $langs){
  try{$r=Invoke-WebRequest "$siteURL/guides/AIVANA_AI_Global_Identity_Guide_$l.pdf" -UseBasicParsing
    if($r.StatusCode -eq 200){$ok++}}catch{}
}
$msg="✅ AutoHeal done. Guides online: $ok/7"
Log $msg
try {

    $uri = "https://api.telegram.org/bot$($tgCred.token)/sendMessage"
    $body = @{
        chat_id = $tgCred.chat
        text = "✅ AIVANA AutoHeal complete. Guides online: $ok/7.`n$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
    Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    Log "Telegram notification sent successfully."
} catch {
    Log "Telegram send failed: $($_.Exception.Message)"
}
