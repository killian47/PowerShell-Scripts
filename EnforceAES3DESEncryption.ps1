Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12


Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

FUNCTION Get-ScriptDirectory
	{
	$Invocation = (Get-Variable MyInvocation -Scope 1).Value
	Split-Path $Invocation.MyCommand.Path
	}

$ScriptDir = Get-ScriptDirectory
Set-Location $ScriptDir

#Establish credentials
#$USER = "admin_user" 
Clear-Host
$USER = Read-Host "Please enter iLO username"
$CREDENTIALS = Get-Credential -UserName $USER -Message "Enter password"
$PASS = $CREDENTIALS.GetNetworkCredential().Password
$base64AuthInfo = [System.Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("${USER}:${PASS}")))
$basicAuth = "Basic" + " " + $base64AuthInfo
Clear-Host

#ChooseFile Function
Function ChooseFile
	{
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
	Out-Null
	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.initialDirectory = $ScriptDir
	$OpenFileDialog.filter = "All files (*.csv)| *.csv"              #the CSV file should have a column heading 'Name' and entries should be the ilo fqdn
	$OpenFileDialog.title = "Please choose a text input file..."
 	$OpenFileDialog.ShowDialog() | Out-Null
 	$OpenFileDialog.filename
	}
#End ChooseFile Function

IF((Test-Path variable:Filename) -ieq $true)
	{
	Clear-Variable -Name Filename
	}

$Filename = ChooseFile

#ChooseFileResult Function
Function ChooseFileResult
	{
	IF(($Filename -ieq "") -or ($Filename -eq $null))
		{
		[System.Windows.Forms.MessageBox]::Show(`
		"Either no answer filename was specified or you have chosen to cancel script execution."`
		,"Cancelling...",0) | Out-Null
		Exit
		}
	IF($Filename -imatch ".csv")
		{
		$Script:InputList = Import-Csv $Filename
		}
	}


#Run ChooseFileResulf Function
ChooseFileResult

#Contruct headers and body for the http request
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("OData-Version", "4.0")
$headers.Add("Content-Type", "application/json")
$headers.Add("Authorization", $basicAuth)
$body = @"
{
    `"Oem`": {
        `"Hp`": {
            `"EnforceAES3DESEncryption`": true
        }
    }
}
"@


#MAIN
$report = @()
ForEach ($servers in $InputList)
    {
        $EnforceAES3DESEncryption = $null
        $jsonresponse = $null
        $response = $null
        $err = $null
        $result = $null
        $server = $servers.Name
        #Test network connectivity of ILO
        $is_server_valid = Test-NetConnection $server -ErrorAction SilentlyContinue
        IF($is_server_valid.PingSucceeded -ieq 'True')
            {
                 $url = "https://$server"
                 try
                    {
                         $response = Invoke-RestMethod "$url/redfish/v1/Managers/1/NetworkService/"  -Method Get  -Headers $headers -DisableKeepAlive -TimeoutSec 10 -ErrorAction Continue
                         $EnforceAES3DESEncryption = $response.Oem.Hp.EnforceAES3DESEncryption
                         IF($EnforceAES3DESEncryption -imatch 'false')
                            {
                                try {
                                        $result = Invoke-RestMethod "$url/redfish/v1/Managers/1/NetworkService/" -Method 'PATCH' -Headers $headers -Body $body -DisableKeepAlive -TimeoutSec 10 -ErrorAction SilentlyContinue
                                        $jsonresponse = $result | ConvertTo-Json
                                        IF($jsonresponse -imatch 'ResetInProgress')
                                            {
                                                Write-Host $server "- SUCCESS... iLO4 reset inprogress" -ForegroundColor Green
                                                $list = "" | Select ServerName, Status
                                                $list.ServerName = $server
                                                $list.Status = "Success"
                                                $report += $list
                       
                                            }
                                    }
                                catch
                                    {
                                        $err = $error | Select-Object -First 1
                                        Write-Host $server $err.Exception.Message -ForegroundColor Red
                                        $list = "" | Select ServerName, Status
                                        $list.ServerName = $server
                                        $list.Status = $err.Exception.Message
                                        $report += $list
                                    }
                            }
                         Else {
                                Write-Host $server "AES 3DES Encryption is already enabled" -ForegroundColor Green
                                $list = "" | Select ServerName, Status
                                $list.ServerName = $server
                                $list.Status = "AES 3DES Encryption is already enabled"
                                $report += $list
                              }
                    }
                catch {
                        $err = $error | Select-Object -First 1
                        Write-Host $server $err.Exception.Message -ForegroundColor Red
                        $list = "" | Select ServerName, Status
                        $list.ServerName = $server
                        $list.Status = $err.Exception.Message
                        $report += $list
                      }
            }
        Else
            {
                Write-Host $server "unreacheable" -ForegroundColor Red
                $list = "" | Select ServerName, Status
                $list.ServerName = $server
                $list.Status = "unreacheable"
                $report += $list
            }
    }

$date = Get-Date -Format 'yyyyMMdd_HHmmss'
$file = "AES3DES_Report_" + $date
$path =  "D:\Scripts\HPE Automation\AES3DESEncyption_Remediation\$file.csv"
$report | Export-csv $path -notypeinformation  
$filename = $path # this is the location where you saved the report
$smtpServer = "Mailo2.uhc.com"
$recipients = "rosano_gapud@optum.com" # enter the email address of the recipients here, seprate by comma for multiple addresses
$msg = new-object Net.Mail.MailMessage
$att = new-object Net.Mail.Attachment($filename)
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$msg.From = “rosano_gapud@optum.com”
$msg.To.Add($recipients)
$msg.Subject = “AES3DESEncryption Mod Report”
$msg.Body = “see attached csv”
$msg.Attachments.Add($att)

$smtp.Send($msg)      
#end of MAIN
                
