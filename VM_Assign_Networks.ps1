
#Begin Set working directory
#Set working location to directory where the script resides
#
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
	"This script will assign networks to newly registered "+ `
	"VMs, as listed in the input CSV file selected. "+ `
	"`r`r`r`Do you wish to continue?" , "Assign VM Networks" , 4)
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
		
	IF($ScriptChoice -eq "NO")
    	{
		Exit
		}

#
#End prompt to continue and input VIServer(s)

#Add VMWare PowerCli Snap-in
Add-PSsnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue

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

#Import list of VMs and network assignments
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

#Get Networks
#	$Networks = Get-View -ViewType Network  | Sort Name | Select Name -ExpandProperty Name


#Assign new networks to VMs
	ForEach($VMName in $Inputlist)
		{
		$VM = Get-View -ViewType VirtualMachine -Filter @{"name" = $VMName.name}
		$PriNetName = $VMName.NewPriVLAN
		(Get-NetworkAdapter -VM $VM.name | select -First 1) | Set-NetworkAdapter -NetworkName $PriNetName -Confirm:$false

		IF(($VMName.DeleteBUNIC -ieq "No") -and ($VMName.AssignBUNetwork -ieq "Yes"))
			{
			IF((Get-NetworkAdapter -VM $VM.name).count -igt 1)
				{
				$BUNetName = $VMName.NewBUVLAN
				(Get-NetworkAdapter -VM $VM.name)[1] | Set-NetworkAdapter -NetworkName $BUNetName -Confirm:$false
				}
			}
		}
	}
