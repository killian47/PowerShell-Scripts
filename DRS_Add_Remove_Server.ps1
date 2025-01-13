#Begin Set working directory
#Set working location to directory where the script resides
#
#IMPORTANT: Headers of the csv file should be as follows... Device, Cluster, vCenter, DrsVMGroup

FUNCTION Get-ScriptDirectory
	{
	$Invocation = (Get-Variable MyInvocation -Scope 1).Value
	Split-Path $Invocation.MyCommand.Path
	}

$ScriptDir = Get-ScriptDirectory
Set-Location $ScriptDir
#
#End Set working directory

#Clear-Host
Clear-Host

#Add VMWare PowerCli Snap-in
Add-PSsnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Import-Module DRSRule
#Get POwershell Engine Version
$PoshVer = ($PSVersionTable.psversion | Select Major).major

#Begin ChooseFile Function
Function ChooseFile
	{
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
	Out-Null
	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.initialDirectory = $ScriptDir
	$OpenFileDialog.filter = "All files (*.csv)| *.csv"
	$OpenFileDialog.title = "Please choose a csv input file..."
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

#MAIN
$i=0

Do
 {
    $vCenter = $InputList.vCenter[$i]
    Connect-VIServer $vCenter -ErrorAction SilentlyContinue 
    $ObjDrsVMGroup = Get-DrsVMGroup -Cluster $InputList.Cluster[$i] -Name $InputList.DRSVMGroup[$i]
    If ($ObjDrsVMGroup.VM -notcontains $InputList.Device[$i]) #replace -notcontains with -contains if trying to remove a vm from a DRS group
        { 
            Set-DrsVMGroup -Name $InputList.DRSVMGroup[$i] -Append -VM $InputList.Device[$i] -Cluster $InputList.Cluster[$i] #to ADD a VM to a DRS group
            #Set-DrsVMGroup -Name $InputList.DRSVMGroup[$i] -RemoveVM $InputList.Device[$i] -Cluster $InputList.Cluster[$i] #to REMOVE a VM from a DRS group
        }
    $i++
 }
While ($i -ne $InputList.Count)

Disconnect-VIServer $global:DefaultVIServers -Confirm:$false -ErrorAction SilentlyContinue

#IMPORTANT: Headers of the csv file should be as follows... Device, Cluster, vCenter, DrsVMGroup
#WARNING : Removing all VMs from a DRS group is not allowed. Atleast 1 vm should remain in the group. An alternative is to delete the said DRS Group.
