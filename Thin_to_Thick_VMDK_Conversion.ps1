<#
    .SYNOPSIS
    Converts disk storage format from Thin to Thick Lazy Zeroed.

    .DESCRIPTION
    Converts vmdk type from Thin Provision to Thick Lazy Zeroed by migrating the vm to another datastore and specifying the disk format.

    .PARAMETER VC[]
    A txt file containing the names of the vcenter servers needed to connect to.

    .PARAMETER VMS[]
    CSV file containing the virtual machines to be processed.

    .PARAMETER DSTreshold
    Indicates the current treshold set for the datastores (30%).

    .PARAMETER DS
    Datastore where the current VM being processed is located.

    .PARAMETER VMSize
    Provisioned space of the vm currently being processed.

    .PARAMETER Cluster
    Cluster/SILO where the vm belongs.

    .PARAMETER Datastores[]
    Gets all the datastores within the cluster.

    .PARAMETER TargetDS
    Free space of the target datastore.

    .PARAMETER DSCapacity
    Capacity of the target datastore.

    .PARAMETER Eligible.
    Computes if the target datastore will still be above treshold once the vm is moved into it

    .PARAMETER PercentEligible
    Free space percentage of the datastore once the vm is moved into it.

    .FUNCTION Convert
    migrate the vm to another capable datstore while converting the disk storage format from thin to thick.

  #>

Clear-Host


FUNCTION Get-ScriptDirectory
	{
	$Invocation = (Get-Variable MyInvocation -Scope 1).Value
	Split-Path $Invocation.MyCommand.Path
	}

$ScriptDir = Get-ScriptDirectory
Set-Location $ScriptDir
#
#End Set working directory


Clear-Host


#Prompt to continue and input VIServer(s)
#

[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
$ScriptChoice = [System.Windows.Forms.MessageBox]::Show(`
	"This script will convert Thin provisioned vmdk to Thick Lazy Zeroed"+ `
	" for VM's listed in the input text file selected. "+ `
	"`r`r`r`Do you wish to continue?","Convert VMDK Format"   ,4)
	IF($ScriptChoice -eq "YES")
		{
		IF(($DefaultVIServers.count -eq 0) -or ($DefaultVIServers -eq $null) -or (!(Test-Path Variable:DefaultVIServers)))
			{
			[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
			$VIServersInput = [Microsoft.VisualBasic.Interaction]::InputBox(`
			"Enter the Virtual Center Server Name(s), separated by commas:","VIServers")
			IF(($VIServersInput -ieq "") -or ($VIServersInput -ieq $null))
				{
				[System.Windows.Forms.MessageBox]::Show(`
				"Either no VIServers were provided or you have chosen to cancel script execution."`
				,"Cancelling...",0,48) | Out-Null
				Exit
				}
			Else
				{
				$Viservers = $VIServersInput.split(',') | % {$_.trim()}
				}
			}
		Else
			{
			$ConnectedVIServers = $DefaultVIServers | Select Name -ExpandProperty Name
			$ConnectedVIServersList = $null
			ForEach($ConnectedVIServer in $ConnectedVIServers)
				{
				$ConnectedVIServerCR = " "+$ConnectedVIServer+"`r "
				$ConnectedVIServersList += $ConnectedVIServerCR
				}
			$ConnectAdditionalVIServers =  [System.Windows.Forms.MessageBox]::Show(`
			"The following Virtual Center Server(s) are currently connected:"+ `
			"`r`r $ConnectedVIServersList `r`r`r Do you wish to connect to additional"+ `
			"  Virtual Center Server(s)?",`
			" Additional VIServer Connect" , 4)
			IF($ConnectAdditionalVIServers -ieq "Yes")
				{
				[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
				$VIServersInputAdtl = [Microsoft.VisualBasic.Interaction]::InputBox(`
				"Enter the Virtual Center Server Name(s), separated by commas:","VIServers")
				$Viservers = $VIServers + ($VIServersInput.Split(',') | % {$_.trim()})
				}
			}
        }
		
	IF($ScriptChoice -eq "NO")
    	{
		Exit
		}

#
#End prompt to continue and input VIServer(s)

#Add VMWare PowerCli Snap-in
Add-PSsnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
#Get POwershell Engine Version
$PoshVer = ($PSVersionTable.psversion | Select Major).major

#Begin VIServer Connect Function
Function VIServerConnect
	{
	IF(($DefaultVIServers.count -eq 0) -or ($DefaultVIServers -eq $null) -or ((Test-Path Variable:DefaultVIServers) -eq $False))
		{
		Foreach($VIserver in $VIservers)
			{
			IF($VIserver -imatch ".dmzmgmt.uhc.com")
				{
				IF(($cred -eq $null) -or ((Test-Path variable:cred) -eq $false))
					{
					IF($PoshVer -ieq 3)
						{
						$script:cred = Get-Credential -Message "DMZMGMT Credentials:"
						}
					Else
						{
						$script:cred = Get-Credential
						}
					}
				Connect-viserver $VIserver -Credential $cred
				}
			ELSE
				{
				Connect-VIServer $VIserver
				}
			}
		}
	ELSE
		{
		Foreach($VIserver in $Viservers)
			{
			IF($DefaultVIServers -inotmatch $VIserver)
				{
				IF($VIserver -imatch ".dmzmgmt.uhc.com")
					{
					IF(($cred -eq $null) -or ((Test-Path variable:cred) -eq $false))
						{
						IF($PoshVer -ieq 3)
							{
							$script:cred = Get-Credential -Message "DMZMGMT Credentials:"
							}
						Else
							{
							$script:cred = Get-Credential
							}
						}
					Connect-viserver $VIserver -Credential $cred
					}
				ELSE
					{
					Connect-VIServer $VIserver
					}
				}
			}
		}
	}
#End VIServer Connect Function

#Run VIserverConnect Function
VIServerConnect


#Begin ChooseFile Function
Function ChooseFile
	{
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
	Out-Null
	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.initialDirectory = $ScriptDir
	$OpenFileDialog.filter = "All files (*.txt)| *.txt"
	$OpenFileDialog.title = "Please choose a txt input file..."
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
	IF($Filename -imatch ".txt")
		{
		$Script:InputList = Get-Content $Filename
		}
	}

#End ChooseFileResult Function

#Run ChooseFileResulf Function
	ChooseFileResult

#$convert = Move-VM $VM.Name -Datastore $Datastore.Name -DiskStorageFormat Thick



Function Validate
{
	IF ($Datastores.count -gt 1)
		{
			IF ($Datastore.Name -ne $DS.Name)
				{
					$TargetDSfreeGB = [math]::Round($Datastore.FreespaceGB,2) #free space of the target datastore in GB rounded off to 2 decimal places
					$TargetDSCapacity = [math]::Round($Datastore.CapacityGB,2) # capacity of the target datastore in GB rounded off to 2 decimal places
					Write-Host "`r`n" "Datastore" $Datastore.Name "in cluster" $Cluster.name "has free space of" $TargetDSfreeGB "(GB)"
					$Eligible = [math]::Round((($TargetDSfreeGB - $VMSize)/$TargetDSCapacity),3) # compute if the target datastore can accomodate the vm while maintaining the treshold of 30%
					$PercentEligible = “{0:P}” -f (($TargetDSfreeGB - $VMSize)/$TargetDSCapacity)
					Write-Host "`r`n" "After calculation, it will have" $PercentEligible "free space after migrating" $VM.Name
					IF($Eligible -gt $DStreshold)
						{
							Write-Host "`r`n" "Datastore" $Datastore.Name "will still have more than 30% freespace even after migrating" $VM.Name
							Write-Host "`r`n" "MIGRATING VM AND CONVERTING VMDK TO THICK-LAZY-ZERO..."
							#$convert
							Break
						}
					ELSE
						{
							write-Host "`r`n" "Datastore" $Datastore.Name "doesnt have enough space to move vm. Checking the next datastore." -ForegroundColor Red
						}
				}
            ELSE {Write-Host $Datastore "is the source datastore. Moving on to the next in the list." -ForegroundColor DarkRed}
		}
	Else {Write-Host "There is only 1 datastore in this cluster that has the same prefix as the source datastore. Unable to migrate vm and convert disk format."}
}

#MAIN
#Add VMWare PowerCli Snap-in
Add-Pssnapin vmware.vimautomation.core -ErrorAction SilentlyContinue | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
$ElapsedTime = [System.Diagnostics.Stopwatch]::StartNew()
# this is the treshold of the datastores 30%
$Script:DSTreshold = 0.3
$Script:Datastores = ""
$Script:Datastore = ""
$Script:VMSize = ""
$Script:DS = ""
#logging
$conversion_log = @()
$reportname = '\conversionlog.csv'
$ScriptDir = Get-Location
$reportpath = $ScriptDir
$report = -join ($reportpath,$reportname)

ForEach($VM in $InputList)
    {
          $Script:VM = Get-VM $VM
          # gets the current datastore where the vm resides
          $DS = $VM | Get-Datastore
          # gets the provisioned space for the vm in GB rounded to 2 decimal places
          $VMSize = [math]::Round($VM.ProvisionedSpaceGB,2)
          Write-Host "`r`n" $VM.Name "on datastore " $DS.Name "has a provisioned size of " $VMSize "(GB)" -ForegroundColor White
          $Cluster = $VM | Get-Cluster
      
          # get all the datastores in the cluster where the vm belongs that has the same naming convention as the source datastore
          IF ($DS.Name -imatch "DNU")
            {
                $Datastores = $VM | Get-Cluster | Get-Datastore | ? {$_.Name -imatch "dnu"}
                ForEach ($Datastore in $Datastores){Validate}
            }
      
          ElseIF ($DS.Name -imatch "AREP")
            {
                $Datastores = $VM | Get-Cluster | Get-Datastore | ? {$_.Name -imatch "arep"}
                ForEach ($Datastore in $Datastores){Validate} 
            }
      
          ElseIF ($DS.Name -imatch "vmsan")
            {
                $Datastores = $VM | Get-Cluster | Get-Datastore | ? {$_.Name -imatch "vmsan" -and $_.Name -inotmatch "DNU" -and $_.Name -inotmatch "arep"}
                ForEach ($Datastore in $Datastores){Validate}
            }
      
          ElseIF ($DS.Name -imatch "local")
            {
                $Datastores = $VM | Get-Cluster | Get-Datastore | ? {$_.Name -imatch "local"}
                ForEach ($Datastore in $Datastores){Validate}
            }
      
          ElseIF ($DS.Name -imatch "EMC")
            {
                $Datastores = $VM | Get-Cluster | Get-Datastore | ? {$_.Name -imatch "EMC" -and $_.Name -inotmatch "arep"-and $_.Name -inotmatch "template" -and $_.Name -inotmatch "srmmgmt"}
                ForEach ($Datastore in $Datastores){Validate}
            }
      
          ElseIF ($DS.Name -imatch "template")
            {
                $Datastores = $VM | Get-Cluster | Get-Datastore | ? {$_.Name -imatch "template"}
                ForEach ($Datastore in $Datastores){Validate}
            }         
      
          ElseIF ($DS.Name -imatch "srmmgmt")
            {
                $Datastores = $VM | Get-Cluster | Get-Datastore | ? {$_.Name -imatch "srmmgmt"}
                ForEach ($Datastore in $Datastores){Validate}
            } 
      
          ElseIF ($DS.Name -imatch "rto")
            {
                $Datastores = $VM | Get-Cluster | Get-Datastore | ? {$_.Name -imatch "rto"}
                ForEach ($Datastore in $Datastores){Validate}
            }
     #start logging
     $name = $vm.Name
     $oldDS = $ds.Name
     $newDS = $Datastore
     $list = "" | Select Name, OLDDatastore, NEWDatastore
     $list.Name = $name
     $list.OLDDatastore = $oldDS
     $list.NEWDatastore = $newDS
     $conversion_log += $list
    }    
           
$conversion_log | Export-csv $report -notypeinformation
Invoke-Item $report          
#disconnect the vcenter servers
#Disconnect-VIServer $global:DefaultVIServers -Confirm:$false 
#$ElapsedTime = [System.Diagnostics.Stopwatch]::StartNew()
