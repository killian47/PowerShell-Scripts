<#
.SYNOPSIS
    
        This script will stop/start a vcenter service, display its health and services.
.DESCRIPTION
        This script will display the over-all health of the vcenter and the status of each service as well as start or stop a service.
        This script takes advantage of the API for the vcenter appliance. There is no need to putty or remote login to the appliance itself.
        An email notification will then be sent to vSphere-Notification_DL@ds.uhc.com for information
.INPUTS/VARIABLES
    
        $vcenter - the vcenter server which will be queried for its health and services
        $USER - username of the resource running the script
        $CREDENTIALS - SSO password of the user
        $service - display name of the service that needs to be stopped or restarted
        $choice - user input from the main-menu
        $confirm - user input from the sub-menu
.FUNCTIONS
        Get-VCSAService - function that will display all the services related to the vcenter
        Get-VCSA_Health - function to get the overall health of the vcenter
        Stop-VAMIService - function that will stop a service defined by the user
        Start-VAMIService - function that will start a service defined by the user
        Validate - validates entries from user.
        Sub-Menu - contains confirmation of action from user.
        Main-Menu - main menu for the script.
        Post-Check-Service - get the state of the service that was stopped or restarted.
.NOTES
        Version: 1.0
        Author: ROSANO C. GAPUD
        Created: October 2019
        Purpose: Initial script development
        
.FUNCTIONALITY
        
        To display the overall health of a vcenter server
        To display the services related to a vcenter server.
        To stop/start a vcenter service without logging in to the vcenter appliance
        Send an email notification to vSphere-Notification_DL@ds.uhc.com for information
.IMPORTANT
        administrator@vsphere.local account only
#>


Import-Module VMware.VimAutomation.Cis.Core
 
Function Get-VCSAService {
 
    $Script:serviceResult = $null
    $Service_API = Get-CisService 'com.vmware.appliance.vmon.service'
    $services = $Service_API.list_details()
    $serviceResult = @()
    ForEach ($key in $services.keys | Sort-Object -Property Value)
        {
         $serviceString = [pscustomobject] @{
         Name = $key;
         State =  $services[$key].state;
         Health = "N/A";
         Startup = $services[$key].Startup_type
        }
    If($services[$key].health -eq $null) { $serviceString.Health = "N/A"} else { $serviceString.Health = $services[$key].health }
    $serviceResult += $serviceString
    }
    $serviceResult
    }
  
Function Get-VCSA_Health {
 
    $healthOverall = (Get-CisService -Name 'com.vmware.appliance.health.system').get()
    $healthLastCheck = (Get-CisService -Name 'com.vmware.appliance.health.system').lastcheck()
    $healthCPU = (Get-CisService -Name 'com.vmware.appliance.health.load').get()
    $healthMem = (Get-CisService -Name 'com.vmware.appliance.health.mem').get()
    $healthSwap = (Get-CisService -Name 'com.vmware.appliance.health.swap').get()
    $healthStorage = (Get-CisService -Name 'com.vmware.appliance.health.storage').get()
    # DB health only applicable for Embedded/External VCSA Node
    $vami = (Get-CisService -Name 'com.vmware.appliance.system.version').get()
    If($vami.type -eq "vCenter Server with an embedded Platform Services Controller" -or $vami.type -eq "vCenter Server with an external Platform Services Controller")
        {
            $healthVCDB = (Get-CisService -Name 'com.vmware.appliance.health.databasestorage').get()
        }
        else
        {
            $healthVCDB = "N/A"
        }
    $healthSoftwareUpdates = (Get-CisService -Name 'com.vmware.appliance.health.softwarepackages').get()
    $healthResult = [pscustomobject] @{
        HealthOverall = $healthOverall;
        HealthLastCheck = $healthLastCheck;
        HealthCPU = $healthCPU;
        HealthMem = $healthMem;
        HealthSwap = $healthSwap;
        HealthStorage = $healthStorage;
        HealthVCDB = $healthVCDB;
        HealthSoftware = $healthSoftwareUpdates
    }
    $healthResult
}
 
Function Stop-VAMIService {

    param(
            [Parameter(
                Mandatory=$true,
                ValueFromPipeline=$true,
                ValueFromPipelineByPropertyName=$true)
            ]
            [String]$Name
         )

    $Service_API = Get-CisService 'com.vmware.appliance.vmon.service'

    try 
        {
            Write-Host "`nStopping $name service ..."
            $Service_API.stop($name)
        } 
    
    catch
    
        {
            Write-Error $Error[0].exception.Message
        }
}

Function Start-VAMIService {

    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [String]$Name
        )

    $Service_API = Get-CisService 'com.vmware.appliance.vmon.service'

    try
    
        {
            Write-Host "`nStarting $name service ..."
            $Service_API.start($name)
        }
    
    catch
    
        {
            Write-Error $Error[0].exception.Message
        }
}

Function Validate {

    $task = ''
    $Script:services_temp = Get-VCSAService
    IF ($choice -eq '3'){$task = 'STOPPED'}
    ElseIf ($choice -eq '4'){$task = 'STARTED'}
    
    Do{
        $Script:service = Read-Host "`nEnter the service to be $task or [B] to go back to the main menu"
        IF ($service -eq ''){Write-Host "`nplease type in the name of the service" -ForegroundColor Red}
        ElseIf ($services_temp.name -inotcontains $service -and $service -ine 'B' ){Write-Host "`nthere is no service named $service associated with vcenter, please check the spelling`n" -ForegroundColor Red}  
        ElseIf ($service -ieq 'B'){Main-Menu; Break}
      }
    while (($service -eq '') -or ($services_temp.name -inotcontains $service))
    Sub-Menu
}

Function Post-Check-Service {

    $task = ''
    IF ($choice -eq '3'){$task = 'STOPPED'}
    ElseIf ($choice -eq '4'){$task = 'STARTED'}
    $services_temp = Get-VCSAService
    If(($services_temp | ? {$_.name.value -ieq $service}).state -eq $task){Write-Host "`nSUCCESSFULY $task $service" -ForegroundColor Green}
    Else{Write-Host "something went wrong. please login to the appliance and check.`n" -ForegroundColor Red}
}

Function Main-Menu {
	
    do 
    {
        Write-Host 
        "---------Please choose a task:---------
    1. Show vCenter Health Status
    2. Get vCenter SERVICES
    3. Stop a Service
    4. Start a Service
    5. Quit `n"
        
        $choice = Read-Host 'Choice'
        IF ($choice -eq '1' -or $choice -eq '2' -or $choice -eq '3' -or $choice -eq '4' -or $choice -eq '5')
            {Switch ($choice)
                    {
                        '1' {Get-VCSA_Health;pause}
                        '2' {Get-VCSAService | FT;pause}
                        '3' {
                                Validate
                                Stop-VAMIService -Name $service -ErrorAction SilentlyContinue
                                Post-Check-Service
                                Email
                                pause
                            }
                        '4' {
                                Validate
                                Start-VAMIService -Name $service -ErrorAction SilentlyContinue
                                Post-Check-Service
                                Email
                                pause
                            }
                        '5' {Disconnect-CisServer $global:DefaultCisServers -Confirm:$false -ErrorAction SilentlyContinue;Exit}
                    } #end of switch
            }
        ELSE
            {
                Clear-Host
                Write-Host "`nnot a valid choice, please try again" -ForegroundColor Red
            }
    }
   while ($choice -ne '5')
}

Function Sub-Menu {

Write-Host
"*************************************************************************
This action will STOP/START $service service for $vcenter.
*************************************************************************`n"
    
            $confirm = Read-Host 'Proceed? [Y/N]'
            IF ($confirm -ieq 'Y' -or $confirm -ieq 'N')
                {
                 Switch ($confirm)
                    {
                        'Y' {
                             Continue
                             Main-Menu; Break
                            }
                        'N' {
                             Main-Menu; Break
                            }
                    }
                }
            ELSE
                {
                 Write-Host "`nnot a valid choice. please type Y or N`n" -ForegroundColor Red
                 Sub-Menu
                }
}

Function Email {
$smtpServer = "Mailo2.uhc.com"
$recipients = "vSphere-Notification_DL@ds.uhc.com"
$msg = new-object Net.Mail.MailMessage
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$msg.From = “vmware@optum.com”
$msg.To.Add($recipients)
$msg.Subject = "Notification from " + $CisServer
$msg.Body = “The $service service for $CisServer has been started/stopped by $USER on $date”
$smtp.Send($msg)
}      

#MAIN
Clear-Host
$date = Get-Date
$USER = "administrator@vsphere.local"
$CREDENTIALS = Get-Credential -UserName $USER -Message "Enter admin password"
$vcenter = Read-Host "Please enter vCenter server (FQDN)"
#$ServerIP = (Test-Connection -ComputerName $vcenter -count 1).IPV4Address.ipaddressTOstring
$servercheck = Test-Connection -ComputerName $vcenter -count 1 -ErrorAction SilentlyContinue
$CisServer = $vcenter

IF ($servercheck)
    {
      Connect-CisServer $CisServer -Credential $CREDENTIALS | Out-Null
    }

Else
    {
      Clear-Host
      Write-Host "`nThe vCenter server ($vcenter) entered is invalid or not reachable.`n" -ForegroundColor Red
      Break   
    }
    
Main-Menu
