<#PSScriptInfo

.DESCRIPTION

  This script tests various registry values to see if a remote computer is pending a reboot.

.SYNOPSIS

	This script tests various registry values to see if a remote computer is pending a reboot

#>

#Get POwershell Engine Version
$PoshVer = ($PSVersionTable.psversion | Select Major).major

<#[CmdletBinding()]
param(
    # ComputerName is optional. If not specified, localhost is used.
    [ValidateNotNullOrEmpty()]
    [string[]]$ComputerName,
	
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [pscredential]$Credential
)#>
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

$report = @()
$ComputerName = $InputList

$ErrorActionPreference = 'Stop'

$scriptBlock = {
    if ($null -ne $using) {
        # $using is only available if this is being called with a remote session
        $VerbosePreference = $using:VerbosePreference
    }

    function Test-RegistryKey {
        [OutputType('bool')]
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Key
        )
    
        $ErrorActionPreference = 'Stop'

        if (Get-Item -Path $Key -ErrorAction Ignore) {
            $true
        }
    }

    function Test-RegistryValue {
        [OutputType('bool')]
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Key,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Value
        )
    
        $ErrorActionPreference = 'Stop'

        if (Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) {
            $true
        }
    }

    function Test-RegistryValueNotNull {
        [OutputType('bool')]
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Key,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Value
        )
    
        $ErrorActionPreference = 'Stop'

        if (($regVal = Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) -and $regVal.($Value)) {
            $true
        }
    }

    # Added "test-path" to each test that did not leverage a custom function from above since
    # an exception is thrown when Get-ItemProperty or Get-ChildItem are passed a nonexistant key path
    $tests = @(
        { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' }
        { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress' }
        { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
        { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending' }
        { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting' }
        { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations' }
        { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations2' }
        { 
            # Added test to check first if key exists, using "ErrorAction ignore" will incorrectly return $true
            'HKLM:\SOFTWARE\Microsoft\Updates' | Where-Object { test-path $_ -PathType Container } | ForEach-Object {            
                (Get-ItemProperty -Path $_ -Name 'UpdateExeVolatile' -ErrorAction Ignore | Select-Object -ExpandProperty UpdateExeVolatile) -ne 0 
            }
        }
        { Test-RegistryValue -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Value 'DVDRebootSignal' }
        { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttemps' }
        { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'JoinDomain' }
        { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'AvoidSpnSet' }
        {
            # Added test to check first if keys exists, if not each group will return $Null
            # May need to evaluate what it means if one or both of these keys do not exist
            ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' | Where-Object { test-path $_ } | % { (Get-ItemProperty -Path $_ ).ComputerName } ) -ne 
            ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' | Where-Object { Test-Path $_ } | % { (Get-ItemProperty -Path $_ ).ComputerName } )
        }
        {
            # Added test to check first if key exists
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending' | Where-Object { 
                (Test-Path $_) -and (Get-ChildItem -Path $_) } | ForEach-Object { $true }
        }
    )

    foreach ($test in $tests) {
        Write-Verbose "Running scriptblock: [$($test.ToString())]"
        if (& $test) {
            $true
            break
        }
    }
}

# if ComputerName was not specified, then use localhost 
# to ensure that we don't create a Session.
<#if ($null -eq $ComputerName) {
    $ComputerName = "localhost"
}#>

foreach ($computer in $ComputerName) {
    If (Test-Connection $computer -Count 3 -ErrorAction SilentlyContinue -ErrorVariable err) {
    
    $ConnectionStatus = "True"
    
    try {
        $connParams = @{
            'ComputerName' = $computer
            #'IsConnected' = $ConnectionStatus

        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $connParams.Credential = $Credential
        }

        $output = @{
            ComputerName    = $computer
            IsPendingReboot = $false
            #IsConnected = $ConnectionStatus
        }

        if ($computer -in ".", "localhost", $env:COMPUTERNAME ) {        
            if (-not ($output.IsPendingReboot = Invoke-Command -ScriptBlock $scriptBlock)) {
                $output.IsPendingReboot = $false
            }
        }
        else {
            $psRemotingSession = New-PSSession @connParams
        
            if (-not ($output.IsPendingReboot = Invoke-Command -Session $psRemotingSession -ScriptBlock $scriptBlock)) {
                $output.IsPendingReboot = $false
                #$output.IsConnected = $ConnectionStatus
            }
        }
        [pscustomobject]$output
    } catch {
        Write-Error -Message $_.Exception.Message
    } finally {
        if (Get-Variable -Name 'psRemotingSession' -ErrorAction Ignore) {
            $psRemotingSession | Remove-PSSession
        }
    }
}
    Else
        {
            Write-Host "`n$computer is unreachable.`n"
            $ConnectionStatus = "False"
        }

    $list = "" | Select ComputerName, IsPendingReboot, IsConnected
    $list.ComputerName = $computer
    $list.IsPendingReboot = $output.IsPendingReboot
    $list.IsConnected = $ConnectionStatus
    $report += $list
}

