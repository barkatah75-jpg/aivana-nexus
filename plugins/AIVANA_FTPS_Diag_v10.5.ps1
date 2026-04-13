chcp 65001 | Out-Null
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$ftpHost = "89.117.188.202"
$ftpUser = "u786522790.todolist.barkataiautomation.in"
$ftpPass = "M1$wc$0cX>G~QfYt"
$targetUri = "ftp://$ftpHost/public_html/"

Write-Host "`n=== FTPS Diagnostic v10.5 ===" -ForegroundColor Cyan
Write-Host "Testing connection to $targetUri with TLS 1.2..." -ForegroundColor Yellow

try {
    $req = [System.Net.FtpWebRequest]::Create($targetUri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
    $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser,$ftpPass)
    $req.EnableSsl = $true
    $req.UsePassive = $true
    $req.Timeout = 10000

    $res = $req.GetResponse()
    Write-Host "`n✅ FTPS CONNECTED SUCCESSFULLY!" -ForegroundColor Green
    $res.Close()
} catch {
    Write-Host "`n❌ Connection Failed!" -ForegroundColor Red
    Write-Host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Gray
    Write-Host "Message: $($_.Exception.Message)" -ForegroundColor DarkYellow
    if ($_.Exception.InnerException) {
        Write-Host "Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor DarkGray
    }
}
