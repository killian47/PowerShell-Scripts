Add-PSsnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

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

#funtion to unmount the datastore
Function Unmount-Datastore {
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline=$true)]
        $Datastore
    )
    Process {
        if (-not $Datastore) {
            Write-Host "No Datastore defined as input"
            Exit
        }
        Foreach ($ds in $Datastore) {
            $hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent.Diskname
            if ($ds.ExtensionData.Host) {
                $attachedHosts = $ds.ExtensionData.Host
                Foreach ($VMHost in $attachedHosts) {
                    $hostview = Get-View $VMHost.Key
                    $mounted = $VMHost.MountInfo.Mounted
                    #If the device is mounted then unmount it (I added this to the function to prevent error messages in vcenter when running the script)
                    if ($mounted -eq $true) {
                        $StorageSys = Get-View $HostView.ConfigManager.StorageSystem
                        Write-Host "Unmounting VMFS Datastore $($DS.Name) from host $($hostview.Name)..."
                        $StorageSys.UnmountVmfsVolume($DS.ExtensionData.Info.vmfs.uuid);
                    }
                    #If the device isn't mounted then skip it (I added this to the function to prevent error messages in vcenter when running the script)
                    else {
                        Write-Host "VMFS Datastore $($DS.Name) is already unmounted on host $($hostview.Name)..."
                    }
                }
            }
        }
    }
}

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

#$Filename = ChooseFile

#Begin ChooseFileResult Function
Function ChooseFileResult
       {
       IF(($Filename -ieq "") -or ($Filename -eq $null))
              {
              [System.Windows.Forms.MessageBox]::Show(`
              "Either no filename was specified or you have chosen to cancel script execution."`
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
       #ChooseFileResult

#MAIN

$LogName = 'Unmount_Datastore_' + (Get-Date).ToString('MMddyyyy_hhmmsstt') + '.txt'
$LogPath = $ScriptDir
$LOG = $ScriptDir + '\' + $LogName
$ElapsedTime = [System.Diagnostics.Stopwatch]::StartNew()
$USER = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$CREDENTIALS = Get-Credential -UserName $USER -Message "Enter your vCenter password"
$vCenters = Read-Host "Enter vCenter Server (seperate by comma for multiple) "
$Viservers = $vCenters.split(',') | % {$_.trim()}
Start-Transcript -IncludeInvocationHeader -Path $LOG
Connect-VIServer $viservers -Credential $CREDENTIALS -Verbose
$Filename = ChooseFile
ChooseFileResult

foreach($Datastore in $Inputlist)

    {
        $VMonDatastore = $Datastore.ExtensionData.VM.Count
        If ($VMonDatastore -eq 0)
            {
            Get-Datastore $Datastore | Unmount-Datastore
            Write-Host "Datastore $Datastore successfully unmounted." -ForegroundColor Green
            }
        Else 
            {
            Write-Warning "Datastore $Datastore has one or more virtual machines. Please check." -Verbose
            }       
    } 


Disconnect-VIServer -Server $VIservers -Confirm:$false | Out-Null -Verbose
Write-Host $ElapsedTime.Elapsed.ToString() -Verbose
Stop-Transcript | Out-Null
Invoke-Item $LOG

#END OF SCRIPT
