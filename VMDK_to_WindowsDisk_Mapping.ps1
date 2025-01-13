#Script to Map windows disk to vmware harddisk (VMDK).
#Input: a txt file containing server name/s.

#Set script directory
FUNCTION Get-ScriptDirectory
	{
	$Invocation = (Get-Variable MyInvocation -Scope 1).Value
	Split-Path $Invocation.MyCommand.Path
	}

$ScriptDir = Get-ScriptDirectory
Set-Location $ScriptDir
#
#End Set working directory


Add-PSsnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$credentials = Get-Credential -UserName $username -Message "Enter your vCenter password"

$LogName = 'GetVMDK_' + (Get-Date).ToString('MMddyyyy_hhmmsstt') + '.txt'
$LogPath = $ScriptDir
$LOG = $ScriptDir + '\' + $LogName
Start-Transcript -IncludeInvocationHeader -Path $LOG


Clear-Host

#Begin ChooseFile Function
Function ChooseFile
	{
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
	Out-Null
	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.initialDirectory = $ScriptDir
	$OpenFileDialog.filter = "All files (*.txt)| *.txt"
	$OpenFileDialog.title = "Please choose a TXT input file..."
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


#MAIN
$vCenters = Read-Host "Enter vCenter Server (seperate by comma for multiple) "
$Viservers = $vCenters.split(',') | % {$_.trim()}
$DiskInfo= @()
#$path = Read-Host "Please enter the path and filename of the resulting output in .csv format (e.g. C:\temp\diskmap.csv): " #enter the path and filename of the report here
Connect-VIServer $viservers -Credential $credentials -Verbose


ForEach ($vm in $Inputlist)
    {
        #$temp_vm = $vm.ToString().ToUpper()
        $vm = Get-VM $vm -Verbose
        $Disks= Get-HardDisk -VM $vm -Verbose
        $Window_disks = Get-WmiObject -Class Win32_DiskDrive -ComputerName $vm.Name -Verbose
        $disktoparts = Get-WmiObject -class Win32_DiskDriveToDiskPartition -ComputerName $vm.Name -Verbose
        $logicaltopartitions = Get-WmiObject -class Win32_LogicalDiskToPartition -ComputerName $vm.Name -Verbose
        #$wmi_mountpoints = Get-WmiObject -Class Win32_Volume -ComputerName $vm.Name -Filter "DriveType=3 AND DriveLetter IS NULL"
        
        ForEach ($Disk in $Disks)
            {  
              $disk_serial = ($Disk.ExtensionData.Backing.Uuid)-replace '-','' 
              ForEach ($Window_disk in $Window_disks | ? {$_.SerialNumber -eq $disk_serial})
                     {
                          ForEach ($disktopart in $disktoparts)
                               {
                                   ForEach ($logicaltopartition in $logicaltopartitions | ? {$_.Antecedent -eq $disktopart.Dependent})
                                    
                                            {
                                                     $VirtualDisk = "" | Select VM, VMDisk, VMDiskSize,VMDK, WindowsDisk, WindowsDiskSize -Verbose
                                                     $VirtualDisk.VM = $vm.Name
                                                     $VirtualDisk.VMDisk = $disk.Name
                                                     $VirtualDisk.VMDiskSize = [math]::round($disk.CapacityGB,0)
                                                     $VirtualDisk.VMDK = $disk.Filename
                                                     $VirtualDisk.WindowsDisk = ($Window_disk.DeviceID).Replace("\\.\PHYSICALDRIVE","Disk ")
                                                     $VirtualDisk.WindowsDiskSize = [math]::round($Window_disk.Size/1GB,0)
                                            }
                                     
                               }
                                    
                       $DiskInfo += $VirtualDisk                    
                     }
            }
       
      }                       
        
    $DiskInfo | Out-GridView -Verbose
    #$DiskInfo | Export-csv $path -notypeinformation
    Disconnect-VIServer $viservers -Confirm:$false -Verbose
    Stop-Transcript | Out-Null
