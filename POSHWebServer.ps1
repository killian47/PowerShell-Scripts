# http://myserver:8006/

#>
#This part will check if the script is run as "Administrator". IF NOT, it will open a new instance of PowerShell and run it with elevated priviledges.
#Get the ID and security principal of the current user account
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent();
$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID);
#Get the security principal for the administrator role
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator;
# Check to see if we are currently running as an administrator
if ($myWindowsPrincipal.IsInRole($adminRole))
{
    # We are running as an administrator, so change the title and background colour to indicate this
    $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + "(Elevated)";
    $Host.UI.RawUI.BackgroundColor = "DarkBlue";
    Clear-Host;
}
else {
    # We are not running as an administrator, so relaunch as administrator

    # Create a new process object that starts PowerShell
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";

    # Specify the current script path and name as a parameter with added scope and support for scripts with spaces in it's path
    $newProcess.Arguments = "& '" + $script:MyInvocation.MyCommand.Path + "'"

    # Indicate that the process should be elevated
    $newProcess.Verb = "runas";

    # Start the new process
    [System.Diagnostics.Process]::Start($newProcess);

    # Exit from the current, unelevated, process
    Exit;
}


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

FUNCTION Get-ScriptDirectory
	{
	$Invocation = (Get-Variable MyInvocation -Scope 1).Value
	Split-Path $Invocation.MyCommand.Path
	}

$ScriptDir = Get-ScriptDirectory
Set-Location $ScriptDir
Import-Module HPEiLOCmdlets
Import-Module ActiveDirectory
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

#$USER = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$DATE = Get-Date -Format "dddd, MMMM dd yyyy"
#$Script:USER = "admin_user" 
#$Script:CREDENTIALS = Get-Credential -UserName $USER -Message "Enter password"
$Script:CREDENTIALS = Import-Clixml -Path "D:\Scripts\HPE Automation\Get_HPE_Info\cred.xml"
$Script:USER = $CREDENTIALS.UserName
$PASS = $CREDENTIALS.GetNetworkCredential().Password
$base64AuthInfo = [System.Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("${USER}:${PASS}")))
Clear-Host
    
Function Start-PoshWebGUI ($ScriptBlock)
{
     # Create HttpListener Object
    $SimpleServer = New-Object Net.HttpListener
    $SimpleServer.IgnoreWriteExceptions = $true

    # Tell the HttpListener what port to listen on
    #    As long as we use wp00121232 we don't need admin rights. To listen on externally accessible IP addresses we will need admin rights
    $SimpleServer.Prefixes.Add("http://myserver:8006/")
    $SimpleServer.Prefixes.Add("http://myserver:8006/")
    
    
    # Start up the server
    $SimpleServer.Start()

    while($SimpleServer.IsListening)
    {
        Write-Host "Listening for request"
        # Tell the server to wait for a request to come in on that port.
        $Context = $SimpleServer.GetContext()

        #Once a request has been captured the details of the request and the template for the response are created in our $context variable
        Write-Verbose "Context has been captured"

        # $Context.Request contains details about the request
        # $Context.Response is basically a template of what can be sent back to the browser
        # $Context.User contains information about the user who sent the request. This is useful in situations where authentication is necessary


        # Sometimes the browser will request the favicon.ico which we don't care about. We just drop that request and go to the next one.
        if($Context.Request.Url.LocalPath -eq "/favicon.ico")
        {
            do
            {

                    $Context.Response.Close()
                    $Context = $SimpleServer.GetContext()

            }while($Context.Request.Url.LocalPath -eq "/favicon.ico")
        }

        # Creating a friendly way to shutdown the server
        if($Context.Request.Url.LocalPath -eq "/kill")
        {

                    $Context.Response.Close()
                    $SimpleServer.Stop()
                    break

        }
    
        if ($Context.Request.HttpMethod -eq "POST" -and $Context.Request.Url.LocalPath -eq "/login") {
            $body = $Context.Request.InputStream
            $reader = New-Object System.IO.StreamReader($body)
            $json = $reader.ReadToEnd() | ConvertFrom-Json

            $CLIENTUSER = $json.username
            $CLIENTPWORD = $json.password
            $Domain = $env:USERDOMAIN
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
            $ct = [System.DirectoryServices.AccountManagement.ContextType]::Domain
            $pc = New-Object System.DirectoryServices.AccountManagement.PrincipalContext $ct, $Domain
            $login_result = $pc.ValidateCredentials($CLIENTUSER, $CLIENTPWORD)
            if ($login_result)
                {
                    $groups = Get-ADPrincipalGroupMembership -Identity $CLIENTUSER | Select-Object Name
                    sleep 5
                    $isIMSInfraServMember = $groups.Name -contains "IMS_InfraServ"
                }
            $response = @{
                success = $login_result
                username = $CLIENTUSER
                isIMSInfraServMember = $isIMSInfraServMember
            } | ConvertTo-Json

            $buffer = [System.Text.Encoding]::ASCII.GetBytes($response)
            $Context.Response.ContentLength64 = $buffer.Length
            $Context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
            $Context.Response.Close()
        } else {
            $Result = try {.$ScriptBlock} catch {$_.Exception.Message}

        $Context.Request
        # Handling different URLs

        $Result = try {.$ScriptBlock} catch {$_.Exception.Message}

        if($Result -ne $null) {
            if($Result -is [string]){
                
                Write-Verbose "A [string] object was returned. Writing it directly to the response stream."

            } else {

                Write-Verbose "Converting PS Objects into JSON objects"
                $Result = $Result | ConvertTo-Json
                
            }
        }

        Write-Host "Sending response of $Result"

        # We convert the result to bytes from ASCII encoded text
        $buffer = [System.Text.Encoding]::ASCII.GetBytes($Result)

        # We need to let the browser know how many bytes we are going to be sending
        $context.Response.ContentLength64 = $buffer.Length

        # We send the response back to the browser
        try {$context.Response.OutputStream.Write($buffer, 0, $buffer.Length) } catch {Write-Host " "}

        # We close the response to let the browser know we are done sending the response
        $Context.Response.Close()

        $Context.Response
    }
   }
}

Function Get_iLO_Firmware($servers)
{
  $hpeinfo = @()
  $firmwarenames = @()
  #$servers = $Parameters["server"] -split "\s"
  $basicAuth = "Basic" + " " + $base64AuthInfo
  IF($servers -ne $null)
    {
      ForEach($server in $servers)
        {
          IF (($server -inotmatch "lo") -and ($server -inotmatch "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$")){$server = $server + "lo"}
          $is_server_valid = Test-NetConnection $server -ErrorAction SilentlyContinue
          IF ($is_server_valid.PingSucceeded)
            {
              $firmwareInventoryTableObject = New-Object -TypeName PSObject
              
              #Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Hostname" -Value $server
             <# try 
                {
                  $fishheaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                  $fishheaders.Add("Authorization", $basicAuth)
                  $appliance = $null
                  $redfish_response = Invoke-RestMethod -Uri ([URI] "https://$server/redfish/v1/") -Method 'GET' -Headers $fishheaders -ErrorAction Stop
                  $data = $redfish_response -split (",") -replace ("`"") -replace ("{") -replace ("}")
                  $appliance = $data | Select-Object | ? {$_ -imatch "xref"}
                    IF ($appliance -ne $null)
                      {
                        $OneViewURL = $appliance -replace "ManagerUrl:xref:"
                        $OneViewIP = $appliance -replace "ManagerUrl:xref:https://"
                        $nslookup = Resolve-DnsName $OneViewIP
                        $OneViewAppliance = $nslookup.NameHost
                      }
                    Else
                      {
                        $OneViewURL = "not in OneView"
                        $OneViewAppliance = "not in OneView"
                      }
                }
              catch
                {
                  $err = $Error | Select-Object -First 1 
                  $OneViewURL = $err.Exception.Message
                  $OneViewAppliance = $err.Exception.Message  
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "OneView Appliance" -Value $OneViewAppliance
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "OneView URL" -Value $OneViewURL
                  $hpeinfo += $firmwareInventoryTableObject
                }
                                            
              Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "OneView Appliance" -Value $OneViewAppliance
              Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "OneView URL" -Value $OneViewURL
              #$hpeinfo += $firmwareInventoryTableObject #>

              try 
                {
                  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                  $headers.Add("Authorization", $basicAuth)
                  $response = Invoke-RestMethod -Uri ([URI] "https://$server/redfish/v1/Systems/1/") -Method 'GET' -Headers $headers -DisableKeepAlive
                  $iloConnections = $server | Connect-HPEiLO -Credential $CREDENTIALS -DisableCertificateAuthentication -ErrorAction Stop
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Hostname" -Value $iloConnections.Hostname
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "IP Address" -Value $iloConnections.IP
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "ServerName" -Value $response.HostName
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "iLO Generation" -Value $iloConnections.TargetInfo.iLOGeneration
                  $firmwareInventory =  Get-HPEiLOFirmwareInventory -Connection $iloConnections -ErrorAction SilentlyContinue
                  $firmwareItems = $firmwareInventory.FirmwareInformation | Select-Object FirmwareName, FirmwareVersion | Where-Object {$_.FirmwareName -ne ""}
                  $firmwareItems.FirmwareName | ForEach-Object {if ( $firmwarenames -notcontains $_ ) { $firmwarenames += $_ } } 
                  try{$firmwarenames | ForEach-Object { Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name $_ -Value $null -Force }}catch{}
                  $firmwareInventoryTable = $firmwareItems | Group-Object Hostname, FirmwareName | ForEach-Object { @{ $_.Name = $_.Group.FirmwareVersion} }
                  $firmwareInventoryTable | ForEach-Object { $_.GetEnumerator() | ForEach-Object {$firmwareInventoryTableObject.($_.Name) = if ($_.Value -is [array]){ $_.Value -join ", " } else { $_.Value } } }
                  $hpeinfo += $firmwareInventoryTableObject
                  Disconnect-HPEiLO $iloConnections
                }
              catch 
                {
                  $err = $Error | Select-Object -First 1
                  $errTxt = ($err.Exception.Message)
                  if(!$firmwareInventoryTableObject.Hostname){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Hostname" -Value $server}
                  if(!$firmwareInventoryTableObject.'IP Address'){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "IP Address" -Value $is_server_valid.RemoteAddress}
                  if(!$firmwareInventoryTableObject.ServerName){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "ServerName" -Value $errTxt}
                  if(!$firmwareInventoryTableObject.'iLO Generation'){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "iLO Generation" -Value $errTxt}
                  try{$firmwarenames | ForEach-Object {Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name $_ -Value $errTxt -Force}}catch{}
                  $hpeinfo += $firmwareInventoryTableObject
                }
            }
          Else 
            {
              $err = $Error | Select-Object -First 1
              $errTxt = ($err.Exception.Message)
              $firmwareInventoryTableObject = New-Object -TypeName PSObject
              $firmwarenames | ForEach-Object {Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name $_ -Value $errTxt -Force}
              if(!$firmwareInventoryTableObject.Hostname){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Hostname" -Value $server}
              if(!$firmwareInventoryTableObject.'IP Address'){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "IP Address" -Value $errTxt}
              if(!$firmwareInventoryTableObject.ServerName){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "ServerName" -Value $errTxt}
              if(!$firmwareInventoryTableObject.'iLO Generation'){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "iLO Generation" -Value $errTxt}
              #if(!$firmwareInventoryTableObject.'OneView Appliance'){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "OneView Appliance" -Value $errTxt}
              #if(!$firmwareInventoryTableObject.'OneView URL'){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "OneView URL" -Value $errTxt}
              $hpeinfo += $firmwareInventoryTableObject
            }
        }
      $myColumns = "HostName", "IP Address", "ServerName", "iLO Generation", @{N="iLO Firmware";E={IF ($_.'iLO Generation' -match 'iLO5') {$_.'iLO 5'} Else{$_.'iLO'}}}, "System ROM", "Redundant System ROM", "Intelligent Provisioning", "Server Platform Services (SPS) Firmware", "TPM Firmware"
      $remove_col = "iLO", "iLO 5"
      $display_all_properties = $hpeinfo | ForEach-Object {$_.PSObject.Properties.Name} | Where-Object{$remove_col -inotcontains $_} | Sort-Object -Unique
      $col_order = $myColumns + ($display_all_properties | Where-Object {$myColumns -NotContains $_})
      $hpeinfo = $hpeinfo | Select-Object -Property $col_order
      $hpeinfo | ConvertTo-Html -Head $table | Out-String
    }
}

Function Check_iLO_Config($servers)
{
    $searchword = "fail"
    $textsearch = "{'ilo_firmware_check':"
    $textsearch2 = "{'ilo_check': "
    $ilocheck = @()
    $basicAuth = "Basic" + " " + $base64AuthInfo
    $url = "https://my swagger API endpoint"
    $headers = @{
    "Content-Type"= "application/json"
    "Authorization"= "$basicAuth"
    }
    #servers = $Parameters["ilo"] -split "\s"
    IF($servers -ne $null)
    {
      ForEach($server in $servers)
        {
          $body = @{
          "host"=$server
          "apply_ilo_baseline"="false"
          "apply_ilo_firmware"="false"
          }
            $jsonBody = $body | ConvertTo-Json
            $result = $null
            $ilofirmwareresult = $null
            $err = $null
            $getlog = $null
            $stat = $null
            $cmd_serverinfo = $null
            $response = $null
            $logfileContent = $null
            [System.GC]::Collect()
            try
                {
                  $cmdILOBaselineCheck = Invoke-RestMethod -Method Post -Uri $url -Body $jsonBody -Headers $headers
                  $cmd_serverinfo = Invoke-RestMethod -Uri ([URI]"my swagger API endpoint/$server")  -Method Get -UseDefaultCredentials -ErrorAction SilentlyContinue
                  IF($server -imatch '.com'){$hostname = $cmd_serverinfo.SERVERNAME}ELSE{$hostname = $cmd_serverinfo.SHORT_NAME}
                  $buildID = $cmdILOBaselineCheck.status
                  $logID = $buildID.split('/')[3]
                  $logfileURL = "https://hmy swagger API endpoint/$hostname" + "_" + $logID + ".log"
                  $timelimit = (Get-Date).AddMinutes(2)
                  Start-Sleep -Seconds 20
                  do {
                       $response = Invoke-WebRequest -Uri $logfileURL -UseBasicParsing
                       $logfileContent = $response.content
                     }
                  while (($logfileContent -inotmatch 'sendMail') -and ($timelimit -gt (Get-Date)))
                  IF($logfileContent -inotmatch 'sendMail')
                    {
                       $list = "" | Select ServerName, Model, iLOBaselineConfiguration, FailedAttributes, iLOFirmwareCompliance, Current, Standard, Details
                       $list.ServerName = $server
                       $list.Model = $cmd_serverinfo.Model
                       $list.iLOBaselineConfiguration = "checking the iLO baseline took longer than expected"
                       $list.FailedAttributes = "unable to process logfile. please try again later"
                       $list.iLOFirmwareCompliance = "na"
                       $list.Current = "na"
                       $list.Standard = "na"
                       $list.Details = $logfileURL
                       $ilocheck += $list
                    }
                  ELSE
                    {
                       IF($logfileContent -imatch 'ERROR something went wrong!')
                         {
                           $list = "" | Select ServerName, Model, iLOBaselineConfiguration, FailedAttributes, iLOFirmwareCompliance, Current, Standard, Details
                           $list.ServerName = $server
                           $list.Model = $cmd_serverinfo.Model
                           $list.iLOBaselineConfiguration = "ERROR Code: 401"
                           $list.FailedAttributes = "MessageID: Base.0.10.InsufficientPrivilege"
                           $list.iLOFirmwareCompliance = "please check the logfile"
                           $list.Current = "na"
                           $list.Standard = "na"
                           $list.Details = $logfileURL
                           $ilocheck += $list
                         }
                       ELSE
                         {
                           $matchfound = $logfileContent -cmatch "\b$searchword\b"
                           IF($matchfound){$result = "Non-Compliant"}ELSE{$result = "Compliant"}
                           $logarray = $logfileContent -split "\n"
                           $iLOFirmwareStatus = $logarray | ? {$_ -cmatch $textsearch}
                           $firmwarePASSorFAIL = $iLOFirmwareStatus -cmatch "\b$searchword\b"
                           IF($firmwarePASSorFAIL){$ilofirmwareresult = "Non-Compliant"}ELSE{$ilofirmwareresult = "Compliant"}
                           $fails = ""
                           $fails = "========================================================================================================================" + "`r`n"
                           $fails += "Attributes                                               Results   Current Value            Expected Value             " + "`r`n"
                           $fails +="========================================================================================================================" + "`r`n" + "`r`n"
                           $loglines = ($logarray | ? {$_ -cmatch "\b$searchword\b"} | ForEach-Object {if(($_ -cnotmatch $textsearch) -and ($_ -cnotmatch $textsearch2)){(($_ -split '\s', 10)[9])}  })
                           $fails += foreach($logline in $loglines){if ($logline.length -igt 130){$logline.substring(0, 67) + 'too long...              please check logfile'}else {$logline} -join "`r`n"}
                           IF($iLOFirmwareStatus -match "\b$searchword\b"){$fails += $iLOFirmwareStatus -replace '[{,},:,]', "" -replace "'", "" -replace "_check", "                                            " -replace "ilo_firmware_version", "    " -replace "standard_firmware_version", "                   "}
                           $list = "" | Select ServerName, Model, iLOBaselineConfiguration, FailedAttributes, iLOFirmwareCompliance, Current, Standard, Details
                           $list.ServerName = $server
                           $list.Model = $cmd_serverinfo.Model
                           $list.iLOBaselineConfiguration = $result
                           IF($result -match "Non-Compliant"){$list.FailedAttributes = $fails}ELSE{$list.FailedAttributes = "No Failed Attributes"}
                           $list.iLOFirmwareCompliance = $ilofirmwareresult
                           $list.Current = $iLOFirmwareStatus.split(':')[2].split(',')[0]
                           $list.Standard = $iLOFirmwareStatus.split(':')[3].split('}')[0]
                           $list.Details = $logfileURL
                           $ilocheck += $list
                         }
                    }
                }
            catch 
                {
                  $err = $error | Select-Object -First 1
                  $list = "" | Select ServerName, Model, iLOBaselineConfiguration, FailedAttributes, iLOFirmwareCompliance, Current, Standard, Details
                  $list.ServerName = $server
                  $list.Model = $cmd_serverinfo.Model
                  $list.iLOBaselineConfiguration = "NA"
                  $list.FailedAttributes = "NA"
                  $list.iLOFirmwareCompliance = "NA"
                  $list.Current = "NA"
                  $list.Standard = "NA"
                  $list.Details = $err.Exception.Message  + " " +  $err.ErrorDetails.Message
                  $ilocheck += $list
                }
          }
      $ilocheck | ConvertTo-Html -Head $table | Out-String
    }
}

Function Apply_iLO_Baseline($servers)
{
    $ilobaselineconfig = @()
    $logurls = @()
    $basicAuth = "Basic" + " " + $base64AuthInfo
    $url = "http://my swagger API endpoint"
    $headers = @{
    "Content-Type"= "application/json"
    "Authorization"= "$basicAuth"
    }
    #$servers = $Parameters["ilobaselinetxt"] -split "\s"
    IF($servers -ne $null)
      {
        ForEach($server in $servers)
          {
            $body = @{
                      "host"=$server
                      "apply_ilo_baseline"="true"
                      "apply_ilo_firmware"="false"
                                           }
            $jsonBody = $body | ConvertTo-Json
            $getlog = $null
            $err = $null
            try {
                  $cmdILOBaselineCheck = Invoke-RestMethod -Method Post -Uri $url -Body $jsonBody -Headers $headers -ErrorAction Stop
                  $timelimit = (Get-Date).AddMinutes(1)
                  do{$buildID = $cmdILOBaselineCheck.status}
                  while ((-not $cmdILOBaselineCheck.status)  -and ($timelimit -gt (Get-Date)))
                  $logID = $buildID.split('/')[3]
                  $logURL = "http://my swagger API endpoint/$logID"
                  Start-Sleep -Seconds 30
                  $getLog = Invoke-RestMethod -Uri $logURL -Method Get -UseDefaultCredentials -ErrorAction Stop
                  $stat = $getLog.status | Select-Object -Last 1
                  $logfileURL =  $getLog.metadata.logfile | Select-Object -Last 1
                  $list = "" | Select ServerName, Status, StatusDetails, Logfile
                  $list.ServerName = $server
                  $list.Status = $stat
                  $list.StatusDetails = $getLog.status_detail | Select-Object -Last 1
                  IF($stat -imatch 'QUEUED'){$list.Logfile = "this may take a few minutes. please wait."}Else{$list.Logfile = $logfileURL}
                  $ilobaselineconfig += $list
                }
            catch 
                  {
                    $err = $error | Select-Object -First 1
                    $list = "" | Select ServerName, Status, StatusDetails, Logfile
                    $list.ServerName = $server
                    $list.Status = "NA"
                    $list.StatusDetails = "NA"
                    $list.Logfile = $err.Exception.Message  + " " + $err.ErrorDetails.Message
                    $ilobaselineconfig += $list
                  }
          }
        $ilobaselineconfig | ConvertTo-Html -Head $table | Out-String
      }
}

Function Update_iLO_Firmware($servers)
{
    $ilofwupdate = @()
    $logurls = @()
    $basicAuth = "Basic" + " " + $base64AuthInfo
    $url = "http://my swagger API endpoint"
    $headers = @{
    "Content-Type"= "application/json"
    "Authorization"= "$basicAuth"
    }
    #$servers = $Parameters["ilofwupdatetxt"] -split "\s"
    IF($servers -ne $null)
      {
        ForEach($server in $servers)
            {
                $body = @{
                "host"=$server
                "apply_ilo_baseline"="false"
                "apply_ilo_firmware"="true"
                }
                $jsonBody = $body | ConvertTo-Json
                $getlog = $null
                $err = $null
                try {
                      $cmdILOBaselineCheck = Invoke-RestMethod -Method Post -Uri $url -Body $jsonBody -Headers $headers
                      $timelimit = (Get-Date).AddMinutes(1)
                      do{$buildID = $cmdILOBaselineCheck.status}
                      while ((-not $cmdILOBaselineCheck.status)  -and ($timelimit -gt (Get-Date)))
                      $logID = $buildID.split('/')[3]
                      $logURL = "http://my swagger API endpoint/$logID"
                      $timelimit = (Get-Date).AddMinutes(1)
                      do{
                      $getLog = Invoke-RestMethod -Uri $logURL -Method Get -UseDefaultCredentials -ErrorAction SilentlyContinue
                      $stat = $getLog.status | Select-Object -Last 1}
                      while (($stat -eq $null) -and ($timelimit -gt (Get-Date)))
                      #while ((($stat -match 'QUEUED')-or($stat -match 'PROCESSING')-or($stat -eq $null)) -and ($timelimit -gt (Get-Date)))
                      $logfileURL =  $getLog.metadata.logfile | Select-Object -Last 1
                      $list = "" | Select ServerName, Status, StatusDetails, Logfile
                      $list.ServerName = $server
                      $list.Status = $getLog.status | Select-Object -Last 1
                      $list.StatusDetails = $getLog.status_detail | Select-Object -Last 1
                      $list.Logfile = $logfileURL
                      $ilofwupdate += $list
                    }
                catch {
                        $err = $error | Select-Object -First 1
                        $list = "" | Select ServerName, Status, StatusDetails, Logfile
                        $list.ServerName = $server
                        $list.Status = "NA"
                        $list.StatusDetails = "NA"
                        $list.Logfile =$err.Exception.Message  + " " +  $err.ErrorDetails.Message 
                        $ilofwupdate += $list
                      }
            }
        $ilofwupdate | ConvertTo-Html -Head $table | Out-String
       }
}

Function Add_Server_to_OneView($servers)
{
    $addtoOneView = @()
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $body = @{
                                          "username"= $USER
                                          "password"= $PASS
                                         }
    $jsonBody = $body | ConvertTo-Json
    $token_url = "https://my swagger API endpoint"
    $getToken = Invoke-RestMethod -Uri $token_url -Method Post -Headers $headers -Body $jsonBody
    $tokenauth = $getToken.access_token
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer" + " " + $tokenauth )
    $basicAuth = "Basic" + " " + $base64AuthInfo
    #$servers = $Parameters["addtooneview"] -split "\s"
    IF($servers -ne $null)
      {
        ForEach($server in $servers)
          {
            try
              { 
                $response = $null
                $err = $null
                $response = Invoke-RestMethod -Uri ([URI]"https://my swagger API endpoint/$server") -Method Post -Headers $headers
                $serverinfo = Invoke-RestMethod -Uri ([URI]"https://my swagger API endpoint/$server") -Method Get -Headers $headers
                IF(($response -imatch "success") -or ($response -imatch "Host is already in OneView, if you want to add, manually remove and clean first"))
                  {
                    $server = $serverinfo.name
                    $fishheaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                    $fishheaders.Add("Authorization", $basicAuth)
                    $appliance = $null
                    $redfish_response = Invoke-RestMethod -Uri ([URI] "https://$server/redfish/v1/") -Method 'GET' -Headers $fishheaders
                    $data = $redfish_response -split (",") -replace ("`"") -replace ("{") -replace ("}")
                    $appliance = $data | Select-Object | ? {$_ -imatch "xref"}
                    IF ($appliance -ne $null)
                      {
                        $OneViewURL = $appliance -replace "ManagerUrl:xref:"
                        $OneViewIP = $appliance -replace "ManagerUrl:xref:https://"
                        $nslookup = Resolve-DnsName $OneViewIP
                        $OneViewAppliance = $nslookup.NameHost
                        $list = "" | Select ServerName, Model, Status, OneViewIP, OneViewAppliance, URL
                        $list.ServerName = $server
                        $list.Model = $serverinfo.Model
                        $list.Status = $response
                        $list.OneViewIP = $OneViewIP
                        $list.OneViewAppliance = $OneViewAppliance
                        $list.URL = $OneViewURL
                        $addtoOneView += $list
                      }
                    ELSE
                      {
                        $list = "" | Select ServerName, Model, Status, OneViewIP, OneViewAppliance, URL
                        $list.ServerName = $server
                        $list.Model = $serverinfo.Model
                        $list.Status = $response
                        $list.OneViewIP = "unable to get OneView details"
                        $list.OneViewAppliance = "unable to get OneView details"
                        $list.URL = "unable to get OneView details"
                        $addtoOneView += $list
                      }
                  }
                ELSE
                  {
                    $list = "" | Select ServerName, Model, Status, OneViewIP, OneViewAppliance, URL
                    $list.ServerName = $server
                    $list.Model = $serverinfo.Model
                    $list.Status = $response
                    $list.OneViewIP = "unable to get OneView details"
                    $list.OneViewAppliance = "unable to get OneView details"
                    $list.URL = "unable to get OneView details"
                    $addtoOneView += $list
                  }
              }
            catch
              {
                $err = $error | Select-Object -First 1
                $list = "" | Select ServerName, Model, Status, OneViewIP, OneViewAppliance, URL
                $list.ServerName = $server
                $list.Model = $serverinfo.Model
                $list.Status = (($err.ErrorDetails.Message) -replace ("`"") -replace ("`n|`r")) + ". " + $err.Exception.Message 
                $list.OneViewIP = $null
                $list.OneViewAppliance = $null
                $list.URL = $null
                $addtoOneView += $list
              }
          }
        $addtoOneView | ConvertTo-Html -Head $table | Out-String
      }
}

Function Check_Dell_PSU_Settings($servers)
{
                                $dell_psu_settings = @()
                                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                                $headers.Add("Content-Type", "application/json")
                                $body = @{
                                          "username"= $USER
                                          "password"= $PASS
                                         }
                                $jsonBody = $body | ConvertTo-Json
                                $token_url = "https://my swagger API endpoint"
                                $getToken = Invoke-RestMethod -Uri $token_url -Method Post -Headers $headers -Body $jsonBody
                                $tokenauth = $getToken.access_token
                                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                                $headers.Add("Authorization", "Bearer" + " " + $tokenauth )
                                #$servers = $Parameters["addtooneview"] -split "\s"
                                IF($servers -ne $null)
                                {
                                 ForEach($server in $servers)
                                  {
                                   try
                                    { 
                                     $response = $null
                                     $err = $null
                                     $response = Invoke-RestMethod -Uri ([URI]"https://my swagger API endpoint/$server") -Method Get -Headers $headers
                                     $list = "" | Select ServerName, Status, Power_Cap_Policy, Power_Redundancy, Power_Factor_Correction, PSRapid
                                     $list.ServerName = $server
                                     $list.Status = $response.status
                                     $pscapcv = $response.Attributes.'ServerPwr.1.PowerCapSetting'.current_value
                                     $psredcv = $response.Attributes.'ServerPwr.1.PSRedPolicy'.current_value
                                     $pspfccv = $response.Attributes.'ServerPwr.1.PSPFCEnabled'.current_value
                                     $psrapcv = $response.Attributes.'ServerPwr.1.PSRapidOn'.current_value
                                     $pscapsv = $response.Attributes.'ServerPwr.1.PowerCapSetting'.standard_value
                                     $psredsv = $response.Attributes.'ServerPwr.1.PSRedPolicy'.standard_value
                                     $pspfcsv = $response.Attributes.'ServerPwr.1.PSPFCEnabled'.standard_value
                                     $psrapsv = $response.Attributes.'ServerPwr.1.PSRapidOn'.standard_value
                                     $list.Power_Cap_Policy = "Current Value" + " " + ":" + " " + $pscapcv + "        " + "Standard Value" + " " + ":" + " " + $pscapsv
                                     $list.Power_Redundancy = "Current Value" + " " + ":" + " " + $psredcv + "        " + "Standard Value" + " " + ":" + " " + $psredsv
                                     $list.Power_Factor_Correction = "Current Value" + " " + ":" + " " + $pspfccv + "        " + "Standard Value" + " " + ":" + " " + $pspfcsv
                                     $list.PSRapid = "Current Value" + " " + ":" + " " + $psrapcv + "        " + "Standard Value" + " " + ":" + " " + $psrapsv
                                     $dell_psu_settings += $list
                                    } 
                                   catch
                                    {
                                     $err = $error | Select-Object -First 1
                                     $list = "" | Select ServerName, Status, Power_Cap_Policy, Power_Redundancy, Power_Factor_Correction, PSRapid
                                     $list.ServerName = $server
                                     $list.Status = $err.Exception.Message + "`r`n" +  $err.ErrorDetails.Message
                                     $list.Power_Cap_Policy = ""
                                     $list.Power_Redundancy = ""
                                     $list.Power_Factor_Correction = ""
                                     $list.PSRapid = ""
                                     $dell_psu_settings += $list
                                    }
                                  }
                                 $dell_psu_settings | ConvertTo-Html -Head $table | Out-String
                                }
}

Function Standardize_Dell_PSU($servers)
{
                                $dell_psu_configure = @()
                                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                                $headers.Add("Content-Type", "application/json")
                                $body = @{
                                          "username"= "$USER"
                                          "password"= "$PASS"
                                         }
                                $jsonBody = $body | ConvertTo-Json
                                $token_url = "https://my swagger API endpoint/login"
                                $getToken = Invoke-RestMethod -Uri $token_url -Method Post -Headers $headers -Body $jsonBody
                                $tokenauth = $getToken.access_token
                                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                                $headers.Add("Authorization", "Bearer" + " " + $tokenauth )
                                #$servers = $Parameters["addtooneview"] -split "\s"
                                IF($servers -ne $null)
                                {
                                 ForEach($server in $servers)
                                  {
                                   try
                                    { 
                                     $response = $null
                                     $err = $null
                                     $response = Invoke-RestMethod -Uri ([URI]"https://my swagger API endpoint/$server") -Method Post -Headers $headers
                                     $list = "" | Select ServerName, Result, Status
                                     $list.ServerName = $server
                                     IF($response -ieq 'Success'){$list.Result = "Successfully updated PSU configuration"}
                                     $response2 = Invoke-RestMethod -Uri ([URI]"https://my swagger API endpoint/$server") -Method Get -Headers $headers
                                     $list.Status = $response2.status
                                     $dell_psu_configure += $list
                                    } 
                                   catch
                                    {
                                     $err = $error | Select-Object -First 1
                                     $list = "" | Select ServerName, Result, Status
                                     $list.ServerName = $server
                                     $list.Result = $err.Exception.Message + "`r`n" +  $err.ErrorDetails.Message
                                     $list.Status = " "
                                     $dell_psu_configure += $list
                                    }
                                  }
                                 $dell_psu_configure | ConvertTo-Html -Head $table | Out-String
                                }
}

Function Get_IDRAC_Firmware($servers)
{
  $idrac_user = "Admin_User"
  $PASS = $CREDENTIALS.GetNetworkCredential().Password
  $base64AuthInfo = [System.Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("${idrac_user}:${PASS}")))
  $dell_idrac_firmware = @()
  $firmwarenames = @()
  $basicAuth = "Basic" + " " + $base64AuthInfo
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", $basicAuth)
  IF($servers -ne $null)
    {
      ForEach($server in $servers)
        {
          IF (($server -inotmatch "lo") -and ($server -inotmatch "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$")){$server = $server + "lo"}
          $is_server_valid = Test-NetConnection $server -ErrorAction SilentlyContinue
          IF ($is_server_valid.PingSucceeded)
            {
              $firmwareInventoryTableObject = New-Object -TypeName PSObject
              $firmwareInventoryTable = $null
              $firmwareItems = @()
              $baseURI = "https://$server/redfish/v1/UpdateService/FirmwareInventory"
              $systemURI = "https://$server/redfish/v1/Systems/System.Embedded.1/"
              try 
                {
                  $response = Invoke-RestMethod -Uri $baseURI -Method 'GET' -Headers $headers -DisableKeepAlive
                  $installed_comps = $response.Members | Where-Object {$_ -imatch 'installed'}
                  $installed_comps | ForEach-Object {$firmwareURI = $_.'@odata.id'
                                        $firmwareData = Invoke-RestMethod -Uri "https://$server$firmwareURI" -Method Get -Headers $headers -DisableKeepAlive
                                        $firmwareItems += [PSCustomObject]@{
                                            Name = $firmwareData.Name
                                            Version = $firmwareData.Version
                                        }
                                    }
                  $getModel_response = Invoke-RestMethod -Uri $systemURI -Method 'GET' -Headers $headers -DisableKeepAlive
                  
                  
                  Switch ($firmwareItems){
                    {$_.Name -imatch 'Mellanox'}
                        {
                            $mellanox = ($firmwareItems |  where-Object {$_.Name -imatch 'Mellanox'}).Version -join ', '
                            Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Mellanox Connect Adapter" -Value $mellanox -Force
                        }
                    {$_.Name -imatch 'NVIDIA'}
                        {
                            $nvidia = ($firmwareItems |  where-Object {$_.Name -imatch 'NVIDIA'}).Version -join ', '
                            Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "NVIDIA Adapter" -Value $nvidia -Force
                        }
                  }
                  
                  #$mellanox = ($firmwareItems |  where-Object {$_.Name -imatch 'Mellanox'}).Version -join ', '
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Hostname" -Value $server
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "IP Address" -Value $is_server_valid.RemoteAddress
                  Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Model" -Value $getModel_response.Model
                  #Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Mellanox Connect Adapter" -Value $mellanox -Force
                  $firmwareItems.Name | ForEach-Object {if ( $firmwarenames -notcontains $_ ) { $firmwarenames += $_ } } 
                  try{$firmwarenames | ForEach-Object { Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name $_ -Value $null -Force }}catch{}
                  $firmwareInventoryTable = $firmwareItems | Group-Object Hostname, Name | ForEach-Object { @{ $_.Name = $_.Group.Version} }
                  $firmwareInventoryTable | ForEach-Object { $_.GetEnumerator() | ForEach-Object {$firmwareInventoryTableObject.($_.Name) = if ($_.Value -is [array]){ $_.Value -join ", " } else { $_.Value } } }
                  $dell_idrac_firmware += $firmwareInventoryTableObject
                }
              
              catch 
                {
                  $err = $Error | Select-Object -First 1
                  $errTxt = ($err.Exception.Message)
                  if(!$firmwareInventoryTableObject.Hostname){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Hostname" -Value $server}
                  if(!$firmwareInventoryTableObject.'IP Address'){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "IP Address" -Value $is_server_valid.RemoteAddress}
                  if(!$firmwareInventoryTableObject.Model){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Model" -Value $errTxt}
                  try{$firmwarenames | ForEach-Object {Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name $_ -Value $errTxt -Force}}catch{}
                  $dell_idrac_firmware += $firmwareInventoryTableObject
                }
            }
          Else 
            {
              $err = $Error | Select-Object -First 1
              $errTxt = ($err.Exception.Message)
              $firmwareInventoryTableObject = New-Object -TypeName PSObject
              $firmwarenames | ForEach-Object {Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name $_ -Value $errTxt -Force}
              if(!$firmwareInventoryTableObject.Hostname){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Hostname" -Value $server}
              if(!$firmwareInventoryTableObject.'IP Address'){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "IP Address" -Value $errTxt}
              if(!$firmwareInventoryTableObject.Model){Add-Member -InputObject $firmwareInventoryTableObject -MemberType NoteProperty -Name "Model" -Value $errTxt}
              $dell_idrac_firmware += $firmwareInventoryTableObject
            }
        }
      $myColumns = "HostName", "IP Address", "Model", "Integrated Dell Remote Access Controller"
      #$remove_col = "iLO", "iLO 5"
      $display_all_properties = $dell_idrac_firmware | ForEach-Object {$_.PSObject.Properties.Name} | Sort-Object -Unique
      $col_order = $myColumns + ($display_all_properties | Where-Object {$myColumns -NotContains $_})
      $col_order = $col_order | Where-Object {($_ -inotmatch 'Mellanox ConnectX') -and ($_ -inotmatch 'NVIDIA ConnectX')}
      $dell_idrac_firmware = $dell_idrac_firmware | Select-Object -Property $col_order
      $dell_idrac_firmware | ConvertTo-Html -Head $table | Out-String
    }
}

Function Check_iDRAC_Config($servers)
{
    $searchword = "fail"
    #$textsearch = "{'ilo_firmware_check':"
    $textsearch = "{'idrac_check': "
    $ilocheck = @()
    $basicAuth = "Basic" + " " + $base64AuthInfo
    $url = "https://my swagger API endpoint"
    $headers = @{
    "Content-Type"= "application/json"
    "Authorization"= "$basicAuth"
    }
    #servers = $Parameters["ilo"] -split "\s"
    IF($servers -ne $null)
    {
      ForEach($server in $servers)
        {
          $body = @{
          "host"=$server
            }
            $jsonBody = $body | ConvertTo-Json
            $result = $null
            $err = $null
            $getlog = $null
            $stat = $null
            $cmd_serverinfo = $null
            $response = $null
            $logfileContent = $null
            [System.GC]::Collect()
            try
                {
                  $cmdILOBaselineCheck = Invoke-RestMethod -Method Post -Uri $url -Body $jsonBody -Headers $headers
                  $cmd_serverinfo = Invoke-RestMethod -Uri ([URI]"http://my swagger API endpoint/$server")  -Method Get -UseDefaultCredentials -ErrorAction SilentlyContinue
                  IF($server -imatch '.com'){$hostname = $cmd_serverinfo.SERVERNAME}ELSE{$hostname = $cmd_serverinfo.SHORT_NAME}
                  $buildID = $cmdILOBaselineCheck.status
                  $logID = $buildID.split('/')[3]
                  $logfileURL = "http://bmi-prod.optum.com/buildlog/$hostname" + "_" + $logID + ".log"
                  $timelimit = (Get-Date).AddMinutes(2)
                  Start-Sleep -Seconds 20
                  do {
                       $response = Invoke-WebRequest -Uri $logfileURL -UseBasicParsing
                       $logfileContent = $response.content
                     }
                  while (($logfileContent -inotmatch 'sendMail') -and ($timelimit -gt (Get-Date)))
                  IF($logfileContent -inotmatch 'sendMail')
                    {
                       $list = "" | Select ServerName, Model, iDRAC_BaselineConfiguration, FailedAttributes, Details
                       $list.ServerName = $server
                       $list.Model = $cmd_serverinfo.Model
                       $list.iDRAC_BaselineConfiguration = "checking the iLO baseline took longer than expected"
                       $list.FailedAttributes = "unable to process logfile. please try again later"
                       $list.Details = $logfileURL
                       $ilocheck += $list
                    }
                  ELSE
                    {
                       IF($logfileContent -imatch 'ERROR something went wrong!')
                         {
                           $list = "" | Select ServerName, Model, iDRAC_BaselineConfiguration, FailedAttributes, Details
                           $list.ServerName = $server
                           $list.Model = $cmd_serverinfo.Model
                           $list.iDRAC_BaselineConfiguration = "ERROR Code: 401"
                           $list.FailedAttributes = "MessageID: Base.0.10.InsufficientPrivilege"
                           $list.Details = $logfileURL
                           $ilocheck += $list
                         }
                       ELSE
                         {
                           $matchfound = $logfileContent -cmatch "\b$searchword\b"
                           IF($matchfound){$result = "Non-Compliant"}ELSE{$result = "Compliant"}
                           $logarray = $logfileContent -split "\n"
                           $loglines_header = (($logarray | ? {$_ -cmatch "Attributes"}) -split '\s', 10)[9]
                           $iDRACSettings = $logarray | ? {($_ -cmatch $textsearch) -and ($_ -cmatch 'log_my_msg()')}
                           $iDRAC_PASSorFAIL = $iDRACSettings -cmatch "\b$searchword\b"
                           IF($iDRAC_PASSorFAIL){$iDRAC_Config = "Non-Compliant"}ELSE{$iDRAC_Config = "Compliant"}
                           $fails = ""
                           $fails = "========================================================================================================================" + "`r`n"
                           $fails += $loglines_header + "`r`n"
                           $fails +="========================================================================================================================" + "`r`n" + "`r`n"
                           $loglines = ($logarray | ? {$_ -cmatch "\b$searchword\b"} | ForEach-Object {if($_ -cnotmatch $textsearch){(($_ -split '\s', 10)[9])}  })
                           $fails += foreach($logline in $loglines){if ($logline.length -igt 120){$logline.substring(0, 60) + 'too long...              please check logfile'}else {$logline} -join "`r`n"}
                           $list = "" | Select ServerName, Model, iDRAC_BaselineConfiguration, FailedAttributes, Details
                           $list.ServerName = $server
                           $list.Model = $cmd_serverinfo.Model
                           $list.iDRAC_BaselineConfiguration = $result
                           IF($result -match "Non-Compliant"){$list.FailedAttributes = $fails}ELSE{$list.FailedAttributes = "No Failed Attributes"}
                           $list.Details = $logfileURL
                           $ilocheck += $list
                         }
                    }
                }
            catch 
                {
                  $err = $error | Select-Object -First 1
                  $list = "" | Select ServerName, Model, iDRAC_BaselineConfiguration, FailedAttributes, Details
                  $list.ServerName = $server
                  $list.Model = $cmd_serverinfo.Model
                  $list.iDRAC_BaselineConfiguration = "NA"
                  $list.FailedAttributes = "NA"
                  $list.Details = $err.Exception.Message  + " " +  $err.ErrorDetails.Message
                  $ilocheck += $list
                }
          }
      $ilocheck | ConvertTo-Html -Head $table | Out-String
    }
}

Function Check_DELL_Memory($servers)
{
  $idrac_user = "Admin_user"
  $PASS = $CREDENTIALS.GetNetworkCredential().Password
  $base64AuthInfo = [System.Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("${idrac_user}:${PASS}")))
  $dell_idrac_firmware = @()
  $firmwarenames = @()
  $basicAuth = "Basic" + " " + $base64AuthInfo
  $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers.Add("Authorization", $basicAuth)
  $headers.Add("Accept", "application/json")
  $headers2 = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
  $headers2.Add("Authorization", $basicAuth)
  # Initialize an array to store disabled DIMM information
  $disabledDIMMs = @()
  
  IF($servers -ne $null)
    {
      ForEach($server in $servers)
        {
          $osResponse = $null
          $response = $null
          $tagResponse = $null
          $totalDIMMMemory = $null
          $dimmDetails = $null        
          IF (($server -inotmatch "lo") -and ($server -inotmatch "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$")){$server = $server + "lo"}
                  $is_server_valid = Test-NetConnection $server -ErrorAction SilentlyContinue
                  IF ($is_server_valid.PingSucceeded)
                        {
                           try 
                              {
                                $memURI = "https://$server/redfish/v1/Systems/System.Embedded.1/Memory"
                                  try {  
                                    $osMemoryURI = "https://$server/redfish/v1/Systems/System.Embedded.1"
                                    $osResponse = Invoke-RestMethod -Uri $osMemoryURI -Method Get -Headers $headers -ContentType "application/json" -DisableKeepAlive
                                    $osTotalMemoryGB = [math]::round($osResponse.MemorySummary.TotalSystemMemoryGiB, 2)
                                    $tagURI = "https://$server/redfish/v1/Systems/System.Embedded.1/Bios?`$select=Attributes/SystemServiceTag"
                                    $tagResponse = Invoke-RestMethod -Uri $tagURI -Method Get -Headers $headers -ContentType "application/json" -DisableKeepAlive
                                    
                                       }
                                  catch {$osTotalMemoryGB = 'error retrieving data'}
                                $response = Invoke-RestMethod -Uri $memURI -Method Get -Headers $headers -ContentType "application/json" -DisableKeepAlive
                                # Track if any disabled DIMMs are found
                                $foundDisabledDIMM = $false
                                foreach ($dimm in $response.Members)
                                    {
                                        try
                                            {
                                                $dimmURI = $dimm.'@odata.id'
                                                $dimmDetails = Invoke-RestMethod -Uri "https://$server$dimmURI" -Method Get -Headers $headers -ContentType "application/json" -DisableKeepAlive
                                                $status = $dimmDetails.Status.State
                                                $installedDIMMS = $response.Members.Count
                                                $capacityGB = [math]::round($dimmDetails.CapacityMiB / 1024, 2)
                                                $totalDIMMMemory += $capacityGB
                                                $bankLabel = $dimmDetails.DeviceLocator
                                                $partNumber = $dimmDetails.PartNumber
                                                $serialNumber = $dimmDetails.SerialNumber
                                                $manufacturer = $dimmDetails.Manufacturer
                                                $tag = $tagResponse.Attributes.SystemServiceTag
                                                If ($status -eq "Disabled")
                                                    {
                                                        $foundDisabledDIMM = $true
                                                        $disabledDIMMs   += [PSCustomObject]@{
                                                        ServerName             = $server
                                                        Status                 = $status
                                                        Location               = $bankLabel
                                                        No_of_DIMMS_Installed  = $installedDIMMS
                                                        CapacityGB             = $capacityGB
                                                        Total_DIMM_CapacityGB  = $totalDIMMMemory
                                                        Total_OS_CapacityGB    = $osTotalMemoryGB
                                                        PartNumber             = $partNumber
                                                        SerialNumber           = $serialNumber
                                                        Manufacturer           = $manufacturer
                                                        Service_Tag            = $tag
                                                        }
                                                    }
                                            }
                                        catch
                                            {
                                                Write-Error "Failed to retrieve details for DIMM at $dimmURI on server $server"
                                                $disabledDIMMs += [PSCustomObject]@{
                                                ServerName             = $server
                                                Status                 = "Error retrieving data"
                                                Location               = ""
                                                No_of_DIMMS_Installed  = ""
                                                CapacityGB             = ""
                                                Total_DIMM_CapacityGB  = ""
                                                Total_OS_CapacityGB    = ""
                                                PartNumber             = ""
                                                SerialNumber           = ""
                                                Manufacturer           = ""
                                                Service_Tag            = ""
                                                }
                                            }
                                    }
                                If ((-not $foundDisabledDIMM) -and ($totalDIMMMemory -eq $osTotalMemoryGB))
                                    {
                                        $disabledDIMMs += [PSCustomObject]@{
                                        ServerName                   = $server
                                        Status                       = "No disabled DIMMs detected"
                                        Location                     = ""
                                        No_of_DIMMS_Installed        = $installedDIMMS
                                        CapacityGB                   = $capacityGB
                                        Total_DIMM_CapacityGB        = $totalDIMMMemory
                                        Total_OS_CapacityGB          = $osTotalMemoryGB
                                        PartNumber                   = ""
                                        SerialNumber                 = ""
                                        Manufacturer                 = ""
                                        Service_Tag                  = $tag
                                        }
                                    }
                                If ((-not $foundDisabledDIMM) -and ($totalDIMMMemory -ne $osTotalMemoryGB))
                                    {
                                        $disabledDIMMs += [PSCustomObject]@{
                                        ServerName                   = $server
                                        Status                       = "No disabled DIMMs. DISCREPANCY detected!"
                                        Location                     = ""
                                        No_of_DIMMS_Installed        = $installedDIMMS
                                        CapacityGB                   = $capacityGB
                                        Total_DIMM_CapacityGB        = $totalDIMMMemory
                                        Total_OS_CapacityGB          = $osTotalMemoryGB
                                        PartNumber                   = ""
                                        SerialNumber                 = ""
                                        Manufacturer                 = ""
                                        Service_Tag                  = $tag
                                        }
                                    }
                              }
                           catch
                              {
                                Write-Error "Failed to retrieve memory information from server $server"
                                $disabledDIMMs += [PSCustomObject]@{
                                ServerName             = $server
                                Status                 = "Error retrieving data"
                                Location               = ""
                                No_of_DIMMS_Installed  = ""
                                CapacityGB             = ""
                                Total_DIMM_CapacityGB  = ""
                                Total_OS_CapacityGB    = ""
                                PartNumber             = ""
                                SerialNumber           = ""
                                Manufacturer           = ""
                                Service_Tag            = ""
                                }
                         }
                    }
                  Else
                        {
                            $err = $Error | Select-Object -First 1
                            $errTxt = ($err.Exception.Message)
                            $disabledDIMMs += [PSCustomObject]@{
                            ServerName             = $server
                            Status                 = $errTxt
                            Location               = ""
                            No_of_DIMMS_Installed  = ""
                            CapacityGB             = ""
                            Total_DIMM_CapacityGB  = ""
                            Total_OS_CapacityGB    = ""
                            PartNumber             = ""
                            SerialNumber           = ""
                            Manufacturer           = ""
                            Service_Tag            = ""
                                }
                        }
        }
      $disabledDIMMs | ConvertTo-Html -Head $table | Out-String
    }
}

Start-PoshWebGUI -ScriptBlock {
    $Parameters = $Context.Request.QueryString
    $table = @"
<style>
table {
  border-collapse: collapse;
  border-spacing: 0;
  width: 100%;
  border: 1px solid #ddd;
  text-align: left;
}
th, td {
  padding: 12px;
  border: 1px solid #ddd;
  text-align: left;
}
tr:nth-child(even){background-color: #f2f2f2}
th {
  padding-top: 12px;
  padding-bottom: 12px;
  text-align: left;
  background-color: #ADD8E6;
  color: black;
}
</style>
"@
    switch ($Context.Request.Url.LocalPath)
    {
        default {  @"
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
@import url("https://fonts.googleapis.com/css?family=Open+Sans:400,600,700");
@import url("https://netdna.bootstrapcdn.com/font-awesome/4.1.0/css/font-awesome.css");
.form-inline {  
  display: flex;
  flex-flow: row wrap;
  align-items: center;
}
.form-inline label {
  margin: 5px 10px 5px 0;
}
.form-inline input {
  vertical-align: middle;
  margin: 5px 10px 5px 0;
  padding: 10px;
  background-color: #fff;
  border: 1px solid #ddd;
}
.form-inline button {
  padding: 10px 20px;
  background-color: dodgerblue;
  border: 1px solid #ddd;
  color: white;
  cursor: pointer;
}
.form-inline button:hover {
  background-color: royalblue;
}
@media (max-width: 800px) {
  .form-inline input {
   margin: 10px 0;
}
.form-inline {
   flex-direction: column;
   align-items: stretch;
}
}
.grid-container {
  display: grid;
  grid-template-columns: auto auto auto auto;
  grid-gap: 30px;
  padding: 30px;
}
.grid-container > div {
  text-align: center;
  font-size: 12px;
}
.column {
  float: left;
  padding: 25px;
  height: 150px;
}
.left {
  width: 85%;
}
.right {
  width: 15%;
}

*, *:before, *:after {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html, body {
  height: 100%;
}
body {
  font: 14px/1 'Open Sans', sans-serif;
  color: #555;
}
section {
  display: none;
  padding: 20px 0 0;
  border-top: 1px solid #ddd;
}
label {
  display: inline-block;
  margin: 0 0 -1px;
  padding: 15px 25px;
  font-weight: 600;
  text-align: center;
  color: #bbb;
  border: 1px solid transparent;
}
label:before {
  font-family: fontawesome;
  font-weight: normal;
  margin-right: 10px;
}
label[for*='1']:before {
  content: '\f1cb';
}
label[for*='2']:before {
  content: '\f17d';
}
label[for*='3']:before {
  content: '\f16b';
}
label[for*='4']:before {
  content: '\f1a9';
}
label[for*='5']:before {
  content: '\f18e';
}
label[for*='6']:before {
  content: '\f005';
}
label[for*='7']:before {
  content: '\f011';
}
label[for*='8']:before {
  content: '\f013';
}
label[for*='9']:before {
  content: '\f017';
}
label[for*='10']:before {
  content: '\f1e2';
}
label:hover {
  color: #888;
  cursor: pointer;
}
input:checked + label {
  color: #555;
  border: 1px solid #ddd;
  border-top: 2px solid orange;
  border-bottom: 1px solid #fff;
}
#tab1:checked ~ #content1,
#tab2:checked ~ #content2,
#tab3:checked ~ #content3,
#tab4:checked ~ #content4,
#tab5:checked ~ #content5,
#tab6:checked ~ #content6,
#tab7:checked ~ #content7,
#tab8:checked ~ #content8,
#tab9:checked ~ #content9,
#tab10:checked ~ #content10 {
  display: block;
}
@media screen and (max-width: 650px) {
  label {
    font-size: 0;
  }
  label:before {
    margin: 0;
    font-size: 18px;
  }
}
@media screen and (max-width: 400px) {
  label {
    padding: 15px;
  }
}
.modal {
  display: none;
  position: fixed;
  z-index: 1;
  left: 0;
  top: 0;
  width: 100%;
  height: 100%;
  overflow: auto;
  background-color: rgb(0,0,0);
  background-color: rgba(0,0,0,0.4);
  padding-top: 60px;
}
.modal-content {
  background-color: #fefefe;
  margin: 5% auto;
  padding: 20px;
  border: 1px solid #888;
  width: 30%;
}
.login-container input[type="text"],
.login-container input[type="password"] {
  width: 100%;
  padding: 10px;
  margin: 10px 0;
  border: 1px solid #ccc;
}
.login-container button {
  background-color: #E37B06;
  color: white;
  padding: 20px 20px;
  margin: 8px 0;
  border: none;
  cursor: pointer;
  width: 100%;
}
.login-container button:hover {
  opacity: 0.7;
}
.animate {
  -webkit-animation: animatezoom 0.6s;
  animation: animatezoom 0.6s
}
@-webkit-keyframes animatezoom {
  from {-webkit-transform: scale(0)} 
  to {-webkit-transform: scale(1)}
}
@keyframes animatezoom {
  from {transform: scale(0)} 
  to {transform: scale(1)}
}
.error-message {
  color: red;
  margin-top: 10px;
}
.loader {
  border: 16px solid #f3f3f3;
  border-radius: 50%;
  border-top: 16px solid #3498db;
  width: 60px;
  height: 60px;
  animation: spin 2s linear infinite;
  display: none;
  margin: 20px auto;
  display: none;
}
@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
#tab2, #tab2 + label,
#tab3, #tab3 + label,
#tab4, #tab4 + label,
#tab5, #tab5 + label,
#tab7, #tab7 + label {
  display: none;
}
input[name="radioBtn"] {
        display: none;
}
.fixed-image {
  position: fixed;
  top: 10px;
  right: 10px;
  width: 7rem;
  height: 50px;
}
.fixed-text {
  position: fixed;
  right: 17px;
  top: 50px;
  white-space: nowrap;
  text-overflow: ellipsis;
  font-size: 9pt;
  text-align:right;
}
</style>
</head>
<body>
<main>
    <div class="row" style="width:90%; text-overflow: ellipsis">
        <div class="column left">
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab1" type="radio" name="radioBtn" value="option1" checked>
            <label for="tab1" style="text-overflow: ellipsis; white-space: nowrap">HPE ILO Firmware Data</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab2" type="radio" name="radioBtn" value="option2">
            <label for="tab2" style="text-overflow: ellipsis; white-space: nowrap">Check HPE ILO Compliance</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab3" type="radio" name="radioBtn" value="option3">
            <label for="tab3" style="text-overflow: ellipsis; white-space: nowrap">Apply HPE ILO Baseline</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab4" type="radio" name="radioBtn" value="option4">
            <label for="tab4" style="text-overflow: ellipsis; white-space: nowrap">Update HPE ILO Firmware</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab5" type="radio" name="radioBtn" value="option5">
            <label for="tab5" style="text-overflow: ellipsis; white-space: nowrap">Add HPE Server to OneView</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab6" type="radio" name="radioBtn" value="option6">
            <label for="tab6" style="text-overflow: ellipsis; white-space: nowrap">Check Dell PSU Settings</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab7" type="radio" name="radioBtn" value="option7">
            <label for="tab7" style="text-overflow: ellipsis; white-space: nowrap">Standardize Dell PSU Configuration</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab8" type="radio" name="radioBtn" value="option8">
            <label for="tab8" style="text-overflow: ellipsis; white-space: nowrap">Dell IDRAC Firmware Data</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab9" type="radio" name="radioBtn" value="option9">
            <label for="tab9" style="text-overflow: ellipsis; white-space: nowrap">Check iDRAC Compliance</label>
            <input style="display:none; text-overflow: ellipsis; white-space: nowrap" id="tab10" type="radio" name="radioBtn" value="option10">
            <label for="tab10" style="text-overflow: ellipsis; white-space: nowrap">Dell Memory Checker</label>
            <section id="content1">
                <p style="color:black; padding-bottom:15px">Please enter the servername, iLO FQDN or iLO IP to be searched.</p>
                <form name="gethpe" class="form-inline" action="/get_ilo_info">
                  <label for="server" style="color:black; padding-right:10px;padding-left:0px; margin:0">Servername or iLO IP:</label>
                  <input type="text" id="server" name="server" style:"display = 1">
                  <button type="submit" id="btSubmit">Submit</button>
                  <button type="button" id="export" onclick="tableToExcel('hpeinfo', 'HPE_Information')">Export to Excel</button>
                    <div class="grid-container">
                        <div>
                          <table id="hpeinfo" style="white-space:nowrap; text-align:center">
                          <tr>
                          <td>
                          $(
                            Get_iLO_Firmware -servers ($servers = $Parameters["server"] -split "\s")
                           )
                          </td>
                          </tr>
                          </table>
                        </div>
                    </div>
                    </form>    
                </section>
                <section id="content2">
                    <p style="color:black; padding-bottom:15px">Please enter the server to check.</p>
                    <form name="ilocheck" class="form-inline" action="/check_ilo_config">
                      <label for="ilo" style="color:black; padding-right:10px;padding-left:0px; margin:0">Server FQDN:</label>
                      <input type="text" id="ilo" name="ilo" style:"display = 1">
                      <button type="submit" id="ilobtn">Submit</button>
                      <button type="button" id="iloexport" onclick="tableToExcel('ilocheck', 'HPE_Information')">Export to Excel</button>
                          <div class="grid-container">
                              <div>
                              <table id="ilocheck">
                              <tr>
                              <td>
                              <pre>
                              $(
                                Check_iLO_Config -servers ($servers = $Parameters["ilo"] -split "\s")
                               )
                              </pre>
                              </td>
                              </tr>
                              </table>
                              </div>
                           </div>
                           </form>   
                  </section>
                  <section id="content3">
                      <p style="color:black; padding-bottom:15px">Please enter the server name.</p>
                      <form name="ilobaseline" class="form-inline" action="/ilo_baseline">
                      <label for="ilobaselinetxt" style="color:black; padding-right:10px;padding-left:0px; margin:0">Server FQDN:</label>
                      <input type="text" id="ilobaselinetxt" name="ilobaselinetxt" style:"display = 1">
                      <button type="submit" id="ilobtn">Apply iLO Baseline</button>
                          <div class="grid-container">
                              <div>
                              <table id="ilobaselineconfig">
                              <tr>
                              <td>
                              $(
                                Apply_iLO_Baseline -servers ($servers = $Parameters["ilobaselinetxt"] -split "\s")
                               )
                              </td>
                              </tr>
                              </table>
                              </div>
                           </div>
                      </form>
                  </section>
                  <section id="content4"">
                      <p style="color:black; padding-bottom:15px">Please enter the server name.</p>
                      <form name="ilofwupdate" class="form-inline" action="/udpate_ilo">
                      <label for="ilofwupdatetxt" style="color:black; padding-right:10px;padding-left:0px; margin:0">Server FQDN:</label>
                      <input type="text" id="ilofwupdatetxt" name="ilofwupdatetxt" style:"display = 1">
                      <button type="submit" id="iloupdatebtn">Update iLO Firmware</button>
                          <div class="grid-container">
                              <div>
                              <table id="iloFWupdate">
                              <tr>
                              <td>
                              $(
                                Update_iLO_Firmware -servers ($servers = $Parameters["ilofwupdatetxt"] -split "\s")
                               )
                              </td>
                              </tr>
                              </table>
                              </div>
                           </div>
                      </form>
                  </section>
                  <section id="content5"">
                      <p style="color:black; padding-bottom:15px">Please enter the server name.</p>
                      <form name="oneview" class="form-inline" action="/addtooneview">
                      <label for="addtoOneView" style="color:black; padding-right:10px;padding-left:0px; margin:0">Server FQDN:</label>
                      <input type="text" id="addtooneview" name="addtooneview" style:"display = 1">
                      <button type="submit" id="addtooneview">Add</button>
                          <div class="grid-container">
                              <div>
                              <table id="addtooneview">
                              <tr>
                              <td>
                              $(
                                Add_Server_to_OneView -servers ($servers = $Parameters["addtooneview"] -split "\s")
                               )
                              </td>
                              </tr>
                              </table>
                              </div>
                           <div>
                      </form>
                  </section>
                <section id="content6">
                <p style="color:black; padding-bottom:15px">Please enter the DELL servername/s.</p>
                <form name="dell" class="form-inline" action="/dell_psu">
                  <label for="dell_psu" style="color:black; padding-right:10px;padding-left:0px; margin:0">Servername:</label>
                  <input type="text" id="dell_psu" name="dell_psu" style:"display = 1">
                  <button type="submit" id="dell_psu">Submit</button>
                  <button type="button" id="export" onclick="tableToExcel('dell_info', 'DELL PSU Settings')">Export to Excel</button>
                    <div class="grid-container">
                        <div>
                          <table id="dell_info" style="white-space:nowrap; text-align:center">
                          <tr>
                          <td>
                          <pre>
                          $(
                            Check_Dell_PSU_Settings ($servers = $Parameters["dell_psu"] -split "\s")
                           )
                          </pre>
                          </td>
                          </tr>
                          </table>
                        </div>
                    </div>
                    </form>    
                </section>
                <section id="content7">
                <p style="color:black; padding-bottom:15px">Please enter the DELL servername/s.</p>
                <form name="dell" class="form-inline" action="/dell_psu">
                  <label for="dell_psu" style="color:black; padding-right:10px;padding-left:0px; margin:0">Servername:</label>
                  <input type="text" id="dellpsuconfig" name="dellpsuconfig" style:"display = 1">
                  <button type="submit" id="dellpsuconfig">Submit</button>
                  <button type="button" id="export" onclick="tableToExcel('dellpsuconfig', 'Result')">Export to Excel</button>
                    <div class="grid-container">
                        <div>
                          <table id="dellpsuconfig" style="white-space:nowrap; text-align:center">
                          <tr>
                          <td>
                          $(
                            Standardize_Dell_PSU ($servers = $Parameters["dellpsuconfig"] -split "\s")
                           )
                          </td>
                          </tr>
                          </table>
                        </div>
                    </div>
                    </form>    
                </section>
                <section id="content8">
                <p style="color:black; padding-bottom:15px">Please enter the servername, iDRAC FQDN or iDRAC IP to be searched.</p>
                <form name="get_iDRAC" class="form-inline" action="/get_idrac_info">
                  <label for="server" style="color:black; padding-right:10px;padding-left:0px; margin:0">Servername or iDRAC IP:</label>
                  <input type="text" id="dell_idrac" name="dell_idrac" style:"display = 1">
                  <button type="submit" id="btSubmit">Submit</button>
                  <button type="button" id="export" onclick="tableToExcel('idrac_info', 'iDRAC_Information')">Export to Excel</button>
                    <div class="grid-container">
                        <div>
                          <table id="idrac_info" style="white-space:nowrap; text-align:center">
                          <tr>
                          <td>
                          $(
                            Get_IDRAC_Firmware ($servers = $Parameters["dell_idrac"] -split "\s")
                           )
                          </td>
                          </tr>
                          </table>
                        </div>
                    </div>
                    </form>    
                </section>
                <section id="content9">
                    <p style="color:black; padding-bottom:15px">Please enter the server to check.</p>
                    <form name="iDRACcheck" class="form-inline" action="/check_iDRAC_config">
                      <label for="iDRACcheck" style="color:black; padding-right:10px;padding-left:0px; margin:0">Server FQDN:</label>
                      <input type="text" id="iDRAC" name="idrac" style:"display = 1">
                      <button type="submit" id="iDRACbtn">Submit</button>
                      <button type="button" id="iDRACexport" onclick="tableToExcel('iDRAC_check', 'HPE_Information')">Export to Excel</button>
                          <div class="grid-container">
                              <div>
                              <table id="iDRAC_check">
                              <tr>
                              <td>
                              <pre>
                              $(
                                Check_iDRAC_Config -servers ($servers = $Parameters["iDRAC"] -split "\s")
                               )
                              </pre>
                              </td>
                              </tr>
                              </table>
                              </div>
                           </div>
                           </form>   
                  </section>
                  <section id="content10">
                  <p style="color:black; padding-bottom:15px">Please enter the servername, iDRAC FQDN or iDRAC IP to be searched.</p>
                  <form name="get_iDRACmemory" class="form-inline" action="/get_idrac_memory">
                  <label for="iDRACmemlbl" style="color:black; padding-right:10px;padding-left:0px; margin:0">Servername, iDRAC or iDRAC IP:</label>
                  <input type="text" id="idrac_memtxt" name="idrac_memtxt" style:"display = 1">
                  <button type="submit" id="iDRACmembtn">Submit</button>
                  <button type="button" id="export" onclick="tableToExcel('idrac_meminfo', 'iDRAC_Information')">Export to Excel</button>
                    <div class="grid-container">
                        <div>
                          <table id="idrac_meminfo" style="white-space:nowrap; text-align:center">
                          <tr>
                          <td>
                          $(
                            Check_DELL_Memory ($servers = $Parameters["idrac_memtxt"] -split "\s")
                           )
                          </td>
                          </tr>
                          </table>
                        </div>
                    </div>
                    </form>    
                </section>
            </div>
        </div>
        
        <div>
            <img src="https://tinyurl.com/2ltzj2ts" alt="Optum Global Solutions" class="fixed-image">
            </br></br>
            <div style=" padding-top:10px" class="fixed-text">
                <p style="color: rgba(0, 0, 0, 0.3); font-weight: 600">VMware Maintenance Services</p>
                </br>
                <div id="current_date">
                    <script>
                        const options = { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' };
                        document.getElementById("current_date").innerHTML = new Date().toLocaleDateString('en-US', options);
                    </script>
                </div>
                </br>
                <a href="#" id="loginLink" style="font-weight: 600; font-size: 10pt">Login</a>
                <span id="usernameDisplay" style="display: none; font-weight: 500; font-size: 10pt; right:2px"></span>
            </div>
        </div>
        
        <!-- The Modal -->
        <div id="loginModal" class="modal">
        <div class="modal-content animate">
            <div class="login-container">
                <div style= "text-align: center; display: block"><h3>Login</h3></div>
                </br>
                <form id="loginForm">
                    <input type="text" id="username" name="username" placeholder="MSID" required>
                    <input type="password" id="password" name="password" placeholder="Password" required>
                    <div class="loader" id="loader"></div>
                    <button type="submit">Login</button>
                    </br></br>
                    <div id="errorMessage" class="error-message" style="display: none; text-align: center;">Login failed. Please try again.</div>
                    </br>
                </form>
            </div>
        </div>
    </div>
        


  <script type="text/javascript">
  var tableToExcel = (function() {
    var uri = 'data:application/vnd.ms-excel;base64,'
      , template = '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40"><head><!--[if gte mso 9]><xml><x:ExcelWorkbook><x:ExcelWorksheets><x:ExcelWorksheet><x:Name>{worksheet}</x:Name><x:WorksheetOptions><x:DisplayGridlines/></x:WorksheetOptions></x:ExcelWorksheet></x:ExcelWorksheets></x:ExcelWorkbook></xml><![endif]--></head><body><table>{table}</table></body></html>'
      , base64 = function(s) { return window.btoa(unescape(encodeURIComponent(s))) }
      , format = function(s, c) { return s.replace(/{(\w+)}/g, function(m, p) { return c[p]; }) }
    return function(table, name) {
      if (!table.nodeType) table = document.getElementById(table)
      var ctx = {worksheet: name || 'Worksheet', table: table.innerHTML}
      window.location.href = uri + base64(format(template, ctx))
    }
  })()
  </script>

  <script>
        // Get the modal
        var modal = document.getElementById("loginModal");

        // Get the link that opens the modal
        var loginLink = document.getElementById("loginLink");

        // Get the span that will display the username
        var usernameDisplay = document.getElementById("usernameDisplay");

        // Get the loader
        var loader = document.getElementById("loader");

        // When the user clicks the link, open the modal 
        loginLink.onclick = function() {
            modal.style.display = "block";
            // Reset the form and error message
            document.getElementById('loginForm').reset();
            document.getElementById('errorMessage').style.display = "none";
        }

        // When the user clicks anywhere outside of the modal, close it
        window.onclick = function(event) {
            if (event.target == modal) {
                modal.style.display = "none";
            }
        }

        // Function to show the loader
        function showLoader() {
            loader.style.display = "block";
        }

        // Function to hide the loader
        function hideLoader() {
            loader.style.display = "none";
        }

        // Function to show hidden tabs without displaying radio button inputs
        function showHiddenTabs() {
            document.querySelectorAll('#tab2, #tab3, #tab4, #tab5, #tab7').forEach(function(tab) {
                tab.style.display = "inline"; // Show the tab labels
            });

            document.querySelectorAll('#tab2 + label, #tab3 + label, #tab4 + label, #tab5 + label, #tab7 + label').forEach(function(label) {
                label.style.display = "inline"; // Show the labels
            });

            document.querySelectorAll('#tab2, #tab3, #tab4, #tab5, #tab7').forEach(function(input) {
                input.style.display = "none"; // Hide the radio button inputs
            });
        }

        // Function to handle successful login
        function handleSuccessfulLogin(username, isIMSInfraServMember) {
            modal.style.display = "none";
            loginLink.style.display = "none";
            usernameDisplay.textContent = username;
            usernameDisplay.style.display = "inline";
            
            // Store login state in local storage
            localStorage.setItem('isLoggedIn', 'true');
            localStorage.setItem('username', username);
            localStorage.setItem('isIMSInfraServMember', isIMSInfraServMember);

            // Show hidden tabs if criteria are met
            if (isIMSInfraServMember) {
                showHiddenTabs();
            }
        }

        // Handle form submission
        document.getElementById('loginForm').addEventListener('submit', function(event) {
            event.preventDefault();
            const username = document.getElementById('username').value;
            const password = document.getElementById('password').value;

            // Show the loader
            showLoader();

            fetch('https://vmstools.optum.com/login', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ username, password })
            })
            .then(response => response.json())
            .then(data => {
                // Hide the loader
                hideLoader();

                if (data.success) {
                    handleSuccessfulLogin(data.username, data.isIMSInfraServMember);
                } else {
                    document.getElementById('errorMessage').style.display = "block";
                    document.getElementById('username').value = '';
                    document.getElementById('password').value = '';
                }
            })
            .catch(error => {
                console.error('Error:', error);
                // Hide the loader
                hideLoader();

                document.getElementById('errorMessage').style.display = "block";
                document.getElementById('username').value = '';
                document.getElementById('password').value = '';
            });
        });

        // Save selected tab to localStorage
        document.querySelectorAll('input[name="radioBtn"]').forEach(function(radio) {
            radio.addEventListener('change', function() {
                localStorage.setItem('selectedTab', this.id);
            });
        });

        // Check login state and selected tab on page load
        window.onload = function() {
            const isLoggedIn = localStorage.getItem('isLoggedIn');
            const username = localStorage.getItem('username');
            const isIMSInfraServMember = localStorage.getItem('isIMSInfraServMember') === 'true';
            const selectedTab = localStorage.getItem('selectedTab');

            if (isLoggedIn === 'true' && username) {
                handleSuccessfulLogin(username, isIMSInfraServMember);
            } else {
                loginLink.style.display = "inline";
            }

            if (selectedTab) {
                document.getElementById(selectedTab).checked = true;
            }
        }
    </script>

</main>
</body> 
</html>
"@
         }

    }

}
