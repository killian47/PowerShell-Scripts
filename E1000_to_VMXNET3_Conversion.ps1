<#
.SYNOPSIS

    This script will replace E1000 network adapter with a VMXNET3.

.DESCRIPTION

    This script is intended for windows and vmware administrators who has access rights to modify
    virtual machine configurations. It aims to automate the implementation of the above-mentioned tasks. The script will
    add a VMXNET3 adapter in the vmware level, then it will backup the IP settings of the existing E1000 adapter to a csv file.
    Afterwhich, will reset the IP settings of the E1000 and configure those same settings to the newly VMXNET3, then will
    append/rename the E1000 to _OLD and rename the VMXNET3 to "servername_PRI". Then it will disable the E1000.

.SCOPE

    Virtual Microsoft Windows Servers with PowerShell 4.0 and above installed. Provided that the list containing the servers to be modified
    are running on E1000 virtual NIC adapters and NO VMXNET3.

.LIMITATION

    Any other OS aside from above. VMs in the serverlist must be verified and pingable.
    
.INPUTS

    $USER           - username that will be used to login to the vCenter appliance.
    $CREDENTIALS    - password for the vCenter username
    $vcenter        - vCenter to be logged in to
    
.FUNCTIONS
    
    CHOOSEFILE        - Function that will allow the user to choose the csv file that contains the servers to be modified.
    CHOOSEFILERESULT  - Function to verify and validate the file that was chosen using the CHOOSEFILE function.

.NOTES

    Version:  1.0
    Authors:  Michael Villamil
              Rosano C. Gapud
              Kenneth Roxas
    Created:  November 2019
    Purpose:  Initial script development

.FUNCTIONALITY

    As of now, the script is limited E1000 to VMXNET3 conversion. 

.IMPORTANT

    *********************************This script must be run as 'Administrator'*******************************************

#>


#================================================================================================================================================

$ElapsedTime = [System.Diagnostics.Stopwatch]::StartNew()
Import-Module VMware.VimAutomation.Core
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

$USER = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$CREDENTIALS = Get-Credential -UserName $USER -Message "Enter your vCenter password"
Clear-Host
$vcenter = Read-Host "Please enter vCenter server/s (seperate by comma for multiple)"
$Viservers = $vcenter.split(',') | % {$_.trim()}
#check the connectivity of the vcenter servers before continuing with the script


ForEach ($vi in $Viservers)
    {
     Do 
     {
     $servercheck = Test-Connection -ComputerName $vi -count 2 -ErrorAction SilentlyContinue
        IF ($servercheck)
            {Connect-VIServer $vi -Credential $CREDENTIALS -Verbose}
        Else 
            {
             Write-Host "`nThe vCenter server ($vi) entered is invalid or not reachable.`n" -ForegroundColor Red
             $vi = Read-Host "Please type in the correct vCenter server (or CTRL+C to exit)"         
            }
     } while (-not $servercheck)
    }



#Begin ChooseFile Function
Function ChooseFile
	{
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
	Out-Null
	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.initialDirectory = $ScriptDir
	$OpenFileDialog.filter = "All files (*.csv)| *.csv"
	$OpenFileDialog.title = "Please choose a CSV input file..."
 	$OpenFileDialog.ShowDialog() | Out-Null
 	$OpenFileDialog.filename
	}
#End ChooseFile Function

IF((Test-Path variable:Filename) -ieq $true)
	{
	Clear-Variable -Name Filename
	}

$Filename = ChooseFile

#Begin ChooseFileResult Function
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

#End ChooseFileResult Function

#Run ChooseFileResulf Function
	ChooseFileResult

$network_config = @()
#set the name of the report where the IP settings will be written
$reportname = '\E1000toVMXNET3.csv'
#set the location to where the script is being run from
$ScriptDir = Get-Location
#set the location to where the report will be saved
$reportpath = $ScriptDir.Path
#set the literal path of the report
$report = $reportpath + $reportname
Write-Host "`n########################################################################"
Write-Host "backing up IP configuration to a csv file...this may take a few minutes"
Write-Host "########################################################################`n"
#begin backup of the IP settings of the servers in the list
ForEach ($vm in $InputList)
    {
                $vm = $vm.Name
                $E1000 = Get-WmiObject -computername $vm Win32_NetworkAdapter | ? {$_.Name -eq "Intel(R) 82574L Gigabit Network Connection" -and $_.MACAddress -ne $null}
                $E1000_IPConfig = Get-WmiObject win32_NetworkAdapterConfiguration -ComputerName $vm | ? {$_.Index -eq $e1000.DeviceID}
                $Index = $E1000_IPConfig.InterfaceIndex
                $IP = Invoke-Command -ComputerName $VM -ScriptBlock  {param($Index) Get-NetIPAddress | ? {$_.InterfaceIndex -eq $Index -and $_.AddressFamily -ieq 'IPV4'}} -ArgumentList ($Index)
                $IPAddress = $IP.IPAddress
                $PrefixLength = $IP.PrefixLength
                $SubNet = $E1000_IPConfig.IPSubnet -replace "IPSubnet|\s|-|{|}|64|,",""
                $GateWay = $E1000_IPConfig.DefaultIPGateway
                $DNS = $E1000_IPConfig.DNSServerSearchOrder
                $Alias = $E1000.NetConnectionID
                $VMnetwork = (Get-VM $vm | Get-NetworkAdapter | ? {$_.MacAddress -eq $E1000.MACAddress}).NetworkName
                $PrimaryDNS = $DNS.Split(',')[0]
                $SecondaryDNS = $DNS.Split(',')[1]
                $ThirdDNS = $DNS.Split(',')[2]
                $list = "" | Select Name, IPAddress, InterfaceAlias, InterfaceIndex, Gateway, Subnet, PrimaryDNS, SecondaryDNS, TertiaryDNS, VMNetwork
                $list.Name = $vm
                $list.Ipaddress = $IPAddress
                $list.InterfaceAlias = $alias
                $list.InterfaceIndex = $Index
                $list.Gateway = $GateWay[0]
                $list.Subnet = $SubNet[0]
                $list.PrimaryDNS = $PrimaryDNS
                $list.SecondaryDNS = $SecondaryDNS
                $list.TertiaryDNS = $ThirdDNS
                $list.VMNetwork = $VMnetwork
                $network_config += $list
            
    }
#end backup of IP settings

$network_config | Export-csv $report -notypeinformation

#bring up the report to the screen
Invoke-Item $report

#ask implementor to go ahead or quit
Read-Host "`nPlease verify IP Information, press ENTER to continue adding VMXNET and re-configuring IP settings or CTRL-C to END"
Clear-Host

#begin gathering the IP settings of the servers in the list and getting ready for modification
ForEach ($vm in $InputList)        
  {
                $vm = $vm.Name
                $E1000 = Get-WmiObject -computername $vm Win32_NetworkAdapter | ? {$_.Name -eq "Intel(R) 82574L Gigabit Network Connection" -and $_.MACAddress -ne $null}
                $E1000_IPConfig = Get-WmiObject win32_NetworkAdapterConfiguration -ComputerName $vm | ? {$_.Index -eq $e1000.DeviceID}
                $Index = $E1000_IPConfig.InterfaceIndex
                $IP = Invoke-Command -ComputerName $VM -ScriptBlock  {param($Index) Get-NetIPAddress | ? {$_.InterfaceIndex -eq $Index -and $_.AddressFamily -ieq 'IPV4'}} -ArgumentList ($Index)
                $IPAddress = $IP.IPAddress
                $PrefixLength = $IP.PrefixLength
                $SubNet = $E1000_IPConfig.IPSubnet -replace "IPSubnet|\s|-|{|}|64|,",""
                $GateWay = $E1000_IPConfig.DefaultIPGateway
                $DNS = $E1000_IPConfig.DNSServerSearchOrder
                $Alias = $E1000.NetConnectionID
                $VMnetwork = (Get-VM $vm | Get-NetworkAdapter | ? {$_.MacAddress -eq $E1000.MACAddress}).NetworkName
                $PrimaryDNS = $DNS.Split(',')[0]
                $SecondaryDNS = $DNS.Split(',')[1]
                $ThirdDNS = $DNS.Split(',')[2]
                #display IP settings in the screen
                Write-Host "`nIP configuration for - $vm"
                Write-Host "InterfaceAlias - $alias"
                Write-Host "InterfaceIndex - $Index"
                Write-Host "IP Address - $Ipv4"
                Write-host "Gateway - $GateWay"
                Write-Host "Subnet Mask - $SubNet"
                Write-host "DNS servers - $DNS"
                $PrimaryDNS = $DNS.Split(',')[0]
                $SecondaryDNS = $DNS.Split(',')[1]
                $ThirdDNS = $DNS.Split(',')[2]
                Write-Host "VM Network - $VMnetwork`n"
                Write-Host "`nWorking on..." $vm.toUpper()
                $vm = Get-VM $vm
                Write-Host "`nAdding VMXNET3 Adapter"
                #add VMXNET3 adapter
                New-NetworkAdapter -vm $vm -NetworkName "$VMnetwork" -Type "vmxnet3" -StartConnected -Confirm:$false
                sleep 5
                #get properties of the newly added VMXNET3
                $vmx = Get-WmiObject -computername $vm Win32_NetworkAdapter | ? {$_.Name -ieq "vmxnet3 Ethernet Adapter" -and $_.MACAddress -ne $null}
                $vmx_IPConfig = Get-WmiObject win32_NetworkAdapterConfiguration -ComputerName $vm | ? {$_.Index -eq $vmx.DeviceID}
                $vmxAlias = $vmx.NetConnectionID
                $vmxIndex = $vmx_IPConfig.InterfaceIndex
                #this will be the new name of the existing E1000 NIC inside the OS
                $old = $Alias + '_OLD'
                Write-Host "`n---------------------------------------------------------------------------------------------------------------------------------------------------"
                Write-Host "THE SCRIPT BLOCK TO TRANSFER THE IP SETTINGS FROM E1000 TO VMXNET3 WILL BE INITIATED. YOU WILL LOSE CONNECTIVITY TO THE TARGET SERVER. PLEASE WAIT."
                Write-Host "---------------------------------------------------------------------------------------------------------------------------------------------------`n"
                #script block to be executed inside the target server
                $script = Invoke-Command -ComputerName $VM -ScriptBlock {param($Alias,$old,$Index,$vmxIndex,$vmxAlias,$IPAddress,$GateWay,$PrimaryDNS,$SecondaryDNS,$PrefixLength) 
                Get-NetIPAddress | where {$_.InterfaceIndex -eq $Index -and $_.InterfaceAlias -eq $Alias -and $_.AddressFamily -eq 'IPv4'} | Remove-NetRoute -Confirm:$false
                Get-NetIPAddress | where {$_.InterfaceIndex -eq $Index -and $_.InterfaceAlias -eq $Alias -and $_.AddressFamily -eq 'IPv4'} | Remove-NetIPAddress -Confirm:$false
                Get-NetIPAddress | where {$_.InterfaceIndex -eq $vmxIndex -and $_.InterfaceAlias -eq $vmxAlias -and $_.AddressFamily -eq 'IPv4'} | New-NetIPAddress -AddressFamily IPv4 -IPAddress $IPAddress -DefaultGateway "$GateWay" -PrefixLength $PrefixLength -Type Unicast -Confirm:$false
                Get-NetIPAddress | where {$_.InterfaceIndex -eq $vmxIndex -and $_.InterfaceAlias -eq $vmxAlias -and $_.AddressFamily -eq 'IPv4'} | Set-DnsClientServerAddress -ServerAddresses $PrimaryDNS,$SecondaryDNS -Confirm:$false
                Rename-NetAdapter -Name $Alias -NewName $old
                Disable-NetAdapter -Name $old -Confirm:$false
                Rename-NetAdapter -Name $vmxAlias -NewName $Alias
                } -ArgumentList $Alias,$old,$Index,$vmxIndex,$vmxAlias,$IPAddress,$GateWay,$PrimaryDNS,$SecondaryDNS,$PrefixLength -AsJob
                #end of script block
                $script.PSBeginTime
                $script.Progress
                Wait-Job $script -Timeout 120
                Receive-Job $script | Out-Null
                Write-Host "`nDONE with" $vm
                $script.PSEndTime
                
    }

Disconnect-VIServer $global:DefaultVIServers -confirm:$false    

Write-Host "Runtime:" $ElapsedTime.Elapsed
