[cmdletbinding()]
    Param(
    [parameter(Mandatory=$true)]
    [string]$vCenterServer,

    [parameter(Mandatory=$true)]
    [string]$SecondaryMSID,

    [parameter(Mandatory=$true)]
    [string]$MSPassword
    )

{<#
###########################################################################################

###########################################################################################
# Description:	Scripts that checks the uptime of VMhost in a cluster and set Maintenance on cluster     
# Script Actions
# v1.0-1.4	
# Added Menus
# -Cluster Selection
# -View host status in cluster
# -List of vmhost with more than 180 days uptime
# Shows cluster list
# Shows available cluster task
# Executes Automatic Maintenance
# Executes Reboot
# Checks Host Profile Compliance
# Checks vMotion Status
# Checks VM's if its now accepting VM's after exiting maintenance mode
# Issue Fix notes: <add info here>
# v1.7
# Added Menus
# -VMware ESX server Hardware and version	       	
# -VMware VC version				
# -Active Snapshots				
# -CDROMs connected to VMs			
# -Floppy drives connected to VMs		
# -Datastores and the free space available	
# -VM information such as VMware tools version,processor and memory limits					
# -Which VMs have VMware timesync options not enabled
# v1.7b
# Added Menu
# -to Automatic/Maintenance on Selected Single host
#>
}


#############
# Functions #
#############

function load-module {
# add modules for powerCli commands
try {
    Import-Module VMware.VimAutomation.Core
    Write-Host (get-date) ": Module VMware.VimAutomation.Core added"  -ForegroundColor Green
} catch {
    Write-Host ": Module does not exist" -ForegroundColor Red
    show-exit
}
}

function load-vcsession {
#Login into vCenter#
    Write-host (get-date) ": Connecting to $vCenterServer" -ForegroundColor Yellow
    Try 
    {
        Connect-VIServer $vCenterServer -User "$SecondaryMSID" -Password $MSPassword -ErrorAction Stop -WarningAction Ignore | Out-Null
        Write-host (get-date) ": Connected to $vCenterServer" -ForegroundColor Green
    }
    catch
    {
        Write-host (get-date)": $($_.Exception.Message)" -ForegroundColor Yellow
        show-exit
    }
  }

function show-exit {
        Write-Host (get-date) ": Script will now exit" -foregroundcolor Yellow
        if($global:DefaultVIServers -ne $null) 
            {Disconnect-VIServer -Server $global:DefaultVIServers -Confirm:$false -Force}
        break;
}

#{ #minimizer
function Show-ClusterList
{
    param ($title)
    $ccount=0
    Clear-Host
            Write-Host "=============Select Cluster to View in $title =====================" -ForegroundColor Green
            Write-Host
                foreach($ClusterName in $getcluster) {
                    write-host "Press '$ccount' to view VMHost on $($ClusterName.Name)"
                    $ccount ++
                }
            Write-Host "Press 'Q' to quit."
            Write-host 
}

function Show-vmhostList
{
    param ($title)
    $ccount=0
    Clear-Host
            Write-Host "=============Select VMhost to start maintenance mode in $title =====================" -ForegroundColor Green
            Write-Host
                foreach($VMhostPick in $getvmhost) {
                    write-host "Press '$ccount' to view VMHost on $($VMhostPick.Name)"
                    $ccount ++
                }
            Write-Host "Press 'Q' to quit."
            Write-host 
}

function Show-ClusterTasks
{
    param ($currentCluster)
                Clear-Host
                Write-Host "================ Cluster $currentCluster selected ================" -ForegroundColor Green
                Write-Host "There are $HostCounts VMhost in this cluster"
                Write-Host "Maintenance Mode: $HostInMainCount NotResponding: $HostNotrespCount Disconnected: $HostDiscCount"
                Write-Host "Press '1' to View all VMhost in cluster."
                Write-Host "Press '2' to View All VMhost that are above 180 Days uptime"
                Write-Host "Press '3' to View VMware ESX hardware"
                Write-Host "Press '4' to View VMware ESX versions"
                Write-Host "Press '5' to View VMware VC version"
                Write-Host "Press '6' to View VM Snapshots"
                Write-Host "Press '7' to View VMware CDROM connected to VMs"
                Write-Host "Press '8' to View VMware floppy drives connected to VMs"
                Write-Host "Press '9' to View Datastore information"
                Write-Host "Press '10' to View VM information"
                Write-Host "Press '11' to View VM's Timesync enabled"
                Write-Host "Type 'solo' to Automatic/Maintenance on Selected Single host"
                Write-Host "Type 'multi' to Automatic/Maintenance on all host > 180 days uptime in this cluster"
                Write-Host "Press 'Q' to quit."
                Write-host 
}

function read-clusterhost
{
        clear-host
        Write-Host "Loading VMhost info..." -foregroundcolor Yellow
        $esxhosts = get-vmhost -location $clusterChoice 
        $HostCounts = $esxhosts.Count
        $HostInMainCount = $($esxhosts | where {$_.ConnectionState -eq 'Maintenance'}).count
        $HostNotrespCount = $($esxhosts | where {$_.ConnectionState -eq 'NotResponding'}).count
        $HostDiscCount = $($esxhosts | where {$_.ConnectionState -eq 'Disconnected'}).count
        $esxhosts180up = $esxhosts | where {[math]::round((($_.ExtensionData.Summary.QuickStats.Uptime/3600)/24)) -ge 180 }
        return $esxhosts, $HostCounts, $HostInMainCount, $HostNotrespCount, $HostDiscCount, $esxhosts180up
        
}

function show-HostHardware
{
    
    $hostresult = Get-Cluster $clusterChoice | Get-VMhost | ForEach-Object { $server = $_ |get-view; $server.Summary.Hardware | select  @{N="Hostnames";E={$server.Name}}, Vendor, Model, @{N="MemorySize";E={[math]::Round(($server.Summary.Hardware.MemorySize/1048576)/1024,3)}}, CpuModel, CpuMhz, NumCpuPkgs, NumCpuCores, NumCpuThreads, NumNics, NumHBAs }
    $hostresult | Format-Table

}

function show-HostVersions
{
    $hostresult = Get-Cluster $clusterChoice | Get-VMhost | ForEach-Object { $server = $_ |get-view; $server.Config.Product | select @{N="Hostnames";E={$server.Name}}, Version, Build, FullName }
    $hostresult
}

function show-HostVCversion
{
    $hostresult = $(get-view serviceinstance).content.about | select Version, Build, FullName
    $hostresult
}

function show-VMSnapshot
{
    $hostresult = Get-Cluster $clusterChoice | Get-VMhost | Get-VM | get-snapshot | select vm, name,created,description,@{N="Hostnames";E={ Get-VM $_.VM|ForEach-Object{(get-view -id "$($_.ExtensionData.Summary.Runtime.Host.Type)-$($_.ExtensionData.Summary.Runtime.Host.Value)").name}}}
    if($hostresult -ne $null){
    $hostresult
    }
    else{
        Write-Host (get-date) ": No VM's with Snapshot found for this cluster" -foregroundcolor Green
    }
}

function show-VMwithCD
{
    $hostresult = Get-Cluster $clusterChoice | Get-VMhost | Get-vm | where { $_ | get-cddrive | where { $_.ConnectionState.Connected -eq "true" } } 
    if($hostresult -ne $null){
    $hostresult
    }
    else{
        Write-Host (get-date) ": No VM's with CDroms Connected found for this cluster" -foregroundcolor Green
    }
}

function show-VMwithFloppy
{
    $hostresult = Get-Cluster $clusterChoice | Get-VMhost | Get-vm | where { $_ | get-floppydrive | where { $_.ConnectionState.Connected -eq "true" } } 
    if($hostresult -ne $null){
    $hostresult
    }
    else{
        Write-Host (get-date) ": No VM's with Floppy Connected found for this cluster" -foregroundcolor Green
    }
}

function UsedSpace
{
	param($ds)
	[math]::Round(($ds.CapacityMB - $ds.FreeSpaceMB)/1024,2)
}

function FreeSpace
{
	param($ds)
	[math]::Round($ds.FreeSpaceMB/1024,2)
}

function PercFree
{
	param($ds)
	[math]::Round((100 * $ds.FreeSpaceMB / $ds.CapacityMB),0)
}

function Show-Datastore
{
    $Datastores = Get-Datastore
    $myCol = @()
    ForEach ($Datastore in $Datastores){
	    $myObj = "" | Select-Object Datastore, UsedGB, FreeGB, PercFree
	    $myObj.Datastore = $Datastore.Name
	    $myObj.UsedGB = UsedSpace $Datastore
	    $myObj.FreeGB = FreeSpace $Datastore
	    $myObj.PercFree = PercFree $Datastore
	    $myCol += $myObj
    }
    $myCol | Sort-Object PercFree
}

function show-VMinfo
{
    $Report = @()
    Get-Cluster $clusterChoice | Get-VMhost | get-vm | ForEach-Object {
      $vm = Get-View $_.ID
        $vms = "" | Select-Object VMName, Hostname, IPAddress, VMState, TotalCPU, TotalMemory, MemoryUsage, TotalNics, ToolsStatus, ToolsVersion, MemoryLimit, MemoryReservation, CPUreservation, CPUlimit
        $vms.VMName = $vm.Name
        $vms.HostName = (get-view -id "$($vm.Runtime.Host.Type)-$($vm.Runtime.Host.Value)").name
        $vms.IPAddress = $vm.guest.ipAddress
        $vms.VMState = $vm.summary.runtime.powerState
        $vms.TotalCPU = $vm.summary.config.numcpu
        $vms.TotalMemory = $vm.summary.config.memorysizemb
        $vms.MemoryUsage = $vm.summary.quickStats.guestMemoryUsage
        $vms.TotalNics = $vm.summary.config.numEthernetCards
        $vms.ToolsStatus = $vm.guest.toolsstatus
        $vms.ToolsVersion = $vm.config.tools.toolsversion
        $vms.MemoryLimit = $vm.resourceconfig.memoryallocation.limit
        $vms.MemoryReservation = $vm.resourceconfig.memoryallocation.reservation
        $vms.CPUreservation = $vm.resourceconfig.cpuallocation.reservation
        $vms.CPUlimit = $vm.resourceconfig.cpuallocation.limit
        $Report += $vms
    }
    $Report
}

function show-VMTimesync
{
    $hostresult = Get-Cluster $clusterChoice | Get-VMhost | Get-VM | Get-View | Where-Object { $_.Config.Tools.syncTimeWithHost -eq $true } | Select Name, @{N="Hostnames";E={(get-view -id "$($_.Runtime.Host.Type)-$($_.Runtime.Host.Value)").name}} | Sort-object Hostnames
    if($hostresult -ne $null){
    $hostresult
    }
    else{
        Write-Host (get-date) ": No VM's configured to Sync with Host" -foregroundcolor Green
    }
}

function Start-Maintenance
{
        Write-Host (get-date) ": Setting $vmHostname to maintenance mode" -foregroundcolor Yellow
        get-VMHost $vmHostname | set-VMHost -state maintenance -confirm:$false -runasync |out-null
        sleep 10
        $count = 0
        while ($true) {
            if ( (get-VMHost $vmHostname).ConnectionState -eq "Maintenance") {
                Write-Host (get-date) ": $vmHostname in maintenance mode" -foregroundcolor Green
                break;
            }
            else{
                Write-Host (get-date) ": waiting for $vmHostname to go into maintenance..." -foregroundcolor Yellow
                sleep 60
                $count++

                if ($count -eq 10) {
                    
                    Write-Host (get-date) ": Waited too long for maintenance.. Checking Active VM!" -foregroundcolor Green
                    $clusterhosts = Get-Cluster $clusterChoice | Get-VMHost | Where-Object {$_.name -notlike "$vmHostname" -and $_.ConnectionState -notlike 'Maintenance' -and $_.ConnectionState -notlike 'Disconnected'} 
                    do{
                        $remainingVM = Get-VMHost $vmHostname | Get-VM | Where-Object {$_.PowerState -notlike 'PoweredOff'}
                        Write-Host (get-date) ": remaining "$($remainingVM).count" VMs" -foregroundcolor Yellow
                        if($(Get-Cluster $clusterChoice).DrsAutomationLevel -eq 'FullyAutomated' -and $(Get-Cluster $clusterChoice).DrsEnabled -eq $true) {
                            $ListDRS = Get-DrsRecommendation -Cluster $clusterChoice | where {$_.Reason -eq "Host is entering maintenance mode"}
                            $ListDRS | FT -AutoSize
                            $ListDRS | Apply-DrsRecommendation
                        }else {
                            foreach ($remVM in $remainingVM) {
                                #GetAffinity rule of VM
                                $vmAffHost=Get-DrsRule -Cluster $clusterChoice -VM $remVM -VMHost $vmHostname | select  name,@{N="Hostnames";E={ $_.AffineHostIds|ForEach-Object{(get-view -id $_).name}}}
                                if($vmAffHost -eq $null){
                                    $targethost = $clusterhosts | Get-Random
                                }
                                else{    
                                    $targethost=Get-VMHost -Name $vmAffHost.Hostnames | Where-Object {$_.name -notlike "$vmHostname" -and $_.ConnectionState -notlike 'Maintenance'} | Get-Random
                                    Write-Host (get-date) "$remVM is member of"$vmAffHost.Name" rule...Migrating to Host DRS Group" -foregroundcolor Cyan
                                }
                                Write-Host (get-date) ": Migrating $remVM off to $targethost from $vmHostname" -foregroundcolor Yellow
                                Try{
                                    Move-VM -VM $remVM -Destination $targethost |out-null 
                                }
                                catch{
                                    Write-Host $_.Exception.Message -ForegroundColor Yellow
                                    show-exit
                                }                    
                            }
                        }    
                    } until ($remainingVM.count -eq '0')

                    #############
                    # Function check-hang MM restart-vpxa
                    #from Alvin Borabo to everyone:
                    #Get-VMHostService -VMHost $vmHostname | where {$_.Key -eq "vpxa"} | Restart-VMHostService -Confirm:$false -ErrorAction SilentlyContinue 
                    # sleep 60
                    #if (get-VMHost $vmHostname).ConnectionState -eq "Maintenance") = true
                    #eto if false = if ($remainingVM.count -eq '0') {
                    # restart service 
                    #wait up to connected
                    #start maintenance
                    #break;
                    #Call start maintenance function
                    #############
                }

            }
            if ($count -gt 15){
            Write-Host (get-date) ": Waited too long for maintenance.. Exiting Script!" -foregroundcolor Red
            $Endloop=$true
            break;
            }
        }


        return $Endloop
        
}

function Start-Reboot
{
if (!$Endloop) {
        Write-Host (get-date) ": Rebooting $vmHostname " -foregroundcolor Yellow
        #Failsafe incase VMhost is not in maintenance mode
        if ( (get-VMHost $vmHostname).ConnectionState -eq "Maintenance") {
            get-VMHost $vmHostname | restart-VMHost -confirm:$false -force | out-null
 
            #ensure that its goes into NotResponding state first, because it takes awhile
            while ((get-VMHost $vmHostname).ConnectionState -ne "NotResponding") {
            sleep 5
            }
                $count = 0
                while ($true) {
                    if ((get-VMHost $vmHostname).ConnectionState -eq "Maintenance") {
                        Write-Host (get-date) ": $vmHostname is up and in maintenance mode" -foregroundcolor Green
                        break;
                    }
                    else {
                            Write-Host (get-date) ": waiting for $vmHostname to be online..." -foregroundcolor Yellow
                            sleep 300
                            $count++
                    }
                        if ($count -gt 24) {
                            Write-Host (get-date) ": Waited too long for host to be up. quiting!" -foregroundcolor Red
                            $Endloop=$true
                            break;
                        }
                }
 
        }
        else{
            Write-Host (get-date) ": $vmHostname is not in maintenance, cannot reboot!" -foregroundcolor Red
            $Endloop=$true
            break;
        }
 
    }

return $Endloop
        
}

function Check-Profile
{
if (!$Endloop) {
        #Failsafe incase VMhost is not in maintenance mode
        if ( (get-VMHost $vmHostname).ConnectionState -eq "Maintenance") {
            $vmhost = Get-VMHost $vmHostname
            $countApply = 0
                while ($true) {
                    $HPDetails = ""
                    $HPDetails = @()
                    $Details = ""
                    $HostProfile = $VMHost | Get-VMHostProfile
                    if ($VMHost | Get-VMHostProfile) {
                        Write-Host (get-date) ": checking Host Profile compliance for $vmHostname " -foregroundcolor Green
                        $HP = $VMHost | Test-VMHostProfileCompliance
                        If ($HP.ExtensionData.ComplianceStatus -eq "nonCompliant") {
                            Write-Host (get-date) ": host Profile for $vmHostname is not compliant" -foregroundcolor Red 
                            Foreach ($issue in ($HP.IncomplianceElementList)) {
                                $Details = "" | Select VMHost, Compliance, HostProfile, IncomplianceDescription
                                $Details.VMHost = $VMHost.Name
                                $Details.Compliance = $HP.ExtensionData.ComplianceStatus
                                $Details.HostProfile = $HP.VMHostProfile
                                $Details.IncomplianceDescription = $Issue.Description
                                $HPDetails += $Details
                            }
                            Foreach ($issue in ($HPDetails.IncomplianceDescription)) {
                                Write-Host (get-date) ": Incompliance: "$issue -foregroundcolor Red
                            }

                            if ($($HPDetails.IncomplianceDescription -ccontains "The host is not joined in any domain currently") -eq $true){
                                #$SecondaryMSID -replace "([a-z]+\\)","$1"
                                $SecondaryMSID = $SecondaryMSID -replace '([a-z]+\\)',""
                                Get-VMHostAuthentication -VMHost $VMHost | Set-VMHostAuthentication -JoinDomain -Domain "ms.ds.uhc.com" -Username "$SecondaryMSID@ms.ds.uhc.com" -Password $MSPassword -Confirm:$false

                                #Write-Host (get-date) ": Using $SecondaryMSID to join to domain domain" -foregroundcolor Yellow
                                #$additionalConfiguration = Apply-VMHostProfile -Entity $vmhost -Profile $HostProfile -Confirm:$false
                                #$additionalConfiguration['authentication.activeDirectory.JoinDomainMethodPolicy.userName'] = $MSPassword
                                #$additionalConfiguration['authentication.activeDirectory.JoinDomainMethodPolicy.password'] = $SecondaryMSID
                                #Apply-VMHostProfile $vmHostname -Variable $additionalConfiguration -Confirm:$false | Out-Null
                            }

                            if ($countApply -ne 3){
                                Write-Host (get-date) ": Applying host profile "$HPDetails.hostprofile"on $vmHostname " -foregroundcolor Yellow
                                Try{
                                    $countApply++
                                    Apply-VMHostProfile $vmhost -Confirm:$false | out-null
                                }
                                catch{
                                    Write-Host $_.Exception.Message -ForegroundColor Yellow
                                    $Endloop=$true
                                    break;
                                }
                            }
                            else{
                                Write-Host (get-date) ": host Profile for $vmHostname is not compliant. apply attempts($countApply)" -foregroundcolor Red
                                $Endloop=$true
                                break;
                                }
                        }
                        else{
                            Write-Host (get-date) ": Host Profile"$HPDetails.hostprofile"is compliant on $vmHostname   " -foregroundcolor Green
                            break;             
                            }                       
                    }
                    else{
                        Write-Host (get-date) ": No Host Profile attached on $vmHostname " -foregroundcolor red
                        $Endloop=$true
                        break;             
                        }                     
            } #compliance loop
        }
        else{
            Write-Host (get-date) ": $vmHostname is not in maintenance, Apply Host profile!" -foregroundcolor Red
            $Endloop=$true
            break;
        }
 
    }
return $Endloop

}

function Check-vMotion
{
if (!$Endloop) {
        $testingsum=$(Get-VMHost $vmHostname).ExtensionData
        if ($testingsum.Summary.Config.VmotionEnabled -eq $true)
            {
                write-host (get-date) ": vMotion is enabled" -ForegroundColor Green
                if (!$Endloop) {
                    Write-Host (get-date) ": Setting $vmHostname back online" -foregroundcolor Yellow
                    get-VMHost $vmHostname | set-VMHost -state connected -confirm:$false | out-null
                    sleep 10
                    If ((get-VMHost $vmHostname).ConnectionState -eq "Connected") {
 
                    Write-Host (get-date) ": $vmHostname is up and connected" -foregroundcolor Green
                    }
                    else {
                    Write-Host (get-date) ": Host did not get back online...quiting!" -foregroundcolor Red
                    $Endloop=$true
                    }
                }
            }
        else
            {
                write-host (get-date) ": vMotion is disabled. Please check" -ForegroundColor Green
                $Endloop=$true
                break;
            }
}
else
{
Write-Host (get-date) ": Skipping Check-vMotion" -foregroundcolor Red
}
        
}

function Check-VMinHost
{
    if (!$Endloop) {
        while ($true) 
        {
            $movedinCount = $(get-vmhost $vmHostname | Get-VM | Where-Object {$_.PowerState -notlike 'PoweredOff'}).count
            if ($movedinCount -gt 0)
                {
                write-host (get-date) ": $movedinCount VM's are now migrated to $vmHostname" -ForegroundColor Green
                break;

                }
            else
                {
                write-host (get-date) ": Waiting for VM's to move $vmHostname" -ForegroundColor Yellow
                sleep 60
                }
        }

    }
    else
    {
    Write-Host (get-date) ": Skipping Check-VMinHost" -foregroundcolor Red
    }  
}       

function Check-RunningTasks
{
    if (!$Endloop) {

        while ($true) 
        {
            $RunninTasks = Get-Task -server $vCenterServer | where { $_.ObjectId -eq (get-vmhost $vmHostname | Get-View).MoRef.ToString() -and $_.State -eq 'Running'} | select Description, State, PercentComplete, StartTime
            if ($RunninTasks -eq $null)
                {
                write-host (get-date) ": No Running Tasks found on $vmHostname" -ForegroundColor Green
                break;

                }
            else
                {
                write-host (get-date) ": Waiting for running task to complete $vmHostname" -ForegroundColor Yellow
                $RunninTasks | ft -AutoSize
                sleep 60
                }
        }

    }
    else
    {
    Write-Host (get-date) ": Skipping Check-RunningTasks" -foregroundcolor Red
    }  
}                        

#} # function minimizer

#############
# Main Menu #
#############
load-module
load-vcsession
do{
    do{
        $getcluster = Get-Cluster -Server $vCenterServer | Sort-Object Name
        Show-ClusterList($vCenterServer)
        $selection = Read-Host "Please make a selection"
        foreach($number in $getcluster){
            if($number.Name -eq $getcluster[$selection].Name){
                $Chosen = $true
                $clusterChoice = $number.Name
                break;}
            else{$chosen = $false}
        }
    }
    until ($selection -eq 'q'-or $Chosen -eq $true)
#####################
# Cluster info Menu #
#####################

    if ($selection -ne 'q'){
        $esxhosts, $HostCounts, $HostInMainCount, $HostNotrespCount, $HostDiscCount, $esxhosts180up = read-clusterhost
        if($HostCounts -ne '0'){
                do{
            Show-ClusterTasks($clusterChoice)
            $selectionVM = Read-Host "Please make a selection"
                switch ($selectionVM){
                    '1' {
                            if($HostCounts -ne '0'){
                                $esxhosts | Select-Object Name, ConnectionState, PowerState, CpuUsageMhz, CpuTotalMhz,`
                                @{N="MemoryUsageGB"; E={[Math]::Round(($_.MemoryUsageGB), 3)}},`
                                @{N="MemoryTotalGB"; E={[Math]::Round(($_.MemoryTotalGB), 3)}},`
                                Version,`
                                @{N="UptimeDays"; E={[math]::round((($_.ExtensionData.Summary.QuickStats.Uptime/3600)/24))}} | Format-Table -AutoSize
                                pause
                            }
                            else{
                                Write-Host (get-date) ": No VMhost's Found in $clusterChoice Cluster" -foregroundcolor Green
                                pause
                            }
                        } 
                    '2' {
                            if($esxhosts180up -ne $null){
                                $esxhosts180up | Select-Object Name, ConnectionState, PowerState, CpuUsageMhz, CpuTotalMhz,`
                                @{N="MemoryUsageGB"; E={[Math]::Round(($_.MemoryUsageGB), 3)}},`
                                @{N="MemoryTotalGB"; E={[Math]::Round(($_.MemoryTotalGB), 3)}},`
                                Version,`
                                @{N="UptimeDays"; E={[math]::round((($_.ExtensionData.Summary.QuickStats.Uptime/3600)/24))}} | Format-Table -AutoSize
                                pause
                            }
                            else{
                                Write-Host (get-date) ": All host in $clusterChoice Cluster are below 180" -foregroundcolor Green
                                pause
                            }
                        } 
                    '3' {
                            show-HostHardware | Format-Table
                            pause
                        }
                    '4' {
                            show-HostVersions | Format-Table
                            pause
                        } 
                    '5' {
                            show-HostVCversion | Format-Table
                            pause 
                        }
                    '6' {
                            show-VMSnapshot | Format-Table
                            pause
                        }
                    '7' {
                            show-VMwithCD | Format-Table
                            pause
                        }
                    '8' {
                            show-VMwithFloppy | Format-Table
                            pause
                        }
                    '9' {
                            Show-Datastore | Format-Table
                            pause
                        }  
                    '10'{
                            show-VMinfo | Format-Table
                            pause
                        }
                    '11'{
                            show-VMTimesync | Format-Table
                            pause
                        } 
                    'solo'{
                            do{
                                $getvmhost = get-vmhost -location $clusterChoice | Sort-Object Name | where {$_.ConnectionState -eq 'Connected'}
                                Show-vmhostList($clusterChoice)
                                $selVMhost = Read-Host "Please make a selection"
                                foreach($number in $getvmhost){
                                    if($number.Name -eq $getvmhost[$selVMhost].Name){
                                        $Chosen = $true
                                        $vmhostChoice = $number.Name
                                        break;}
                                    else{$chosen = $false}
                                }
                            }
                            until ($selVMhost -eq 'q'-or $Chosen -eq $true)



                            if($Chosen -eq $true){
                            Write-Host (get-date) ": Running script on $vmhostChoice for automatic reboot." -foregroundcolor Yellow
                                $vmHostname = $vmhostChoice
                                 Write-Host (get-date) "Checking $vmHostname " -foregroundcolor Yellow
                                    $Endloop = Start-Maintenance
                                    $Endloop = Start-Reboot
                                    Check-RunningTasks
                                    $Endloop = Check-Profile
                                    Check-vMotion
                                    Check-VMinHost
                                    pause
                                    $Chosen = $false
                                    if ($Endloop) {
                                        show-exit
                                    }
                            }
                            else{
                                Write-Host (get-date) "Press Enter to return to menu..." -foregroundcolor Yellow
                                pause
                            }
                            
                    }
                    'multi'{
                            if($esxhosts180up -ne $null){
                            Write-Host (get-date) ": Running script on $clusterChoice for automatic reboot." -foregroundcolor Yellow
                                foreach ($vmHostname in $esxhosts180up.name){
                                    $Endloop = Start-Maintenance
                                    $Endloop = Start-Reboot
                                    Check-RunningTasks
                                    $Endloop = Check-Profile
                                    Check-vMotion
                                    Check-VMinHost
                                    if ($Endloop) {
                                        show-exit
                                    }
                                }
                                show-exit
                            }
                            else{
                                Write-Host (get-date) ": All host in $clusterChoice Cluster are below 180" -foregroundcolor Green
                                pause
                            }
                            show-exit
                        }
                }
        }until ($selectionVM -eq 'q')
        }
        else{
        Write-Host (get-date) ": There are $HostCounts VMhost in this cluster. Press Enter to return to menu..." -foregroundcolor Yellow
        pause
        }
    }
    Else{
        show-exit
    }
}until ($selection -eq 'q')


