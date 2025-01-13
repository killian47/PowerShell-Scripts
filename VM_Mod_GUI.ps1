
<#
.SYNOPSIS

    this script is a GUI based tool to modify vCPU and vMemory configuration of a virtual machine.

.DESCRIPTION

    this tool is intended for the IMS team and vmware administrators who has access rights to modify
    virtual machine configurations. it aims to automate the implementation of the above-mentioned tasks.
    note that this script is not designed to open up change tickets or send email notifications to stakeholders.
    this tool operates under the assumption that the user has already done all the pre-work.

.INPUTS

    $txtbox_servers - list of servers that will be modified (accepts multiple, 1 per line)
    $txtbox_mem     - new virtual memory (accepts only numeric characters)
    $combo_core     - new total vCPU (combo box, user has to choose in the dropdown list)
    $txtbox_vcenter - input for vCenter server (accepts multiple)

.FUNCTIONS
    
    CONNECT_VISERVER  - to connect to the given vCenter server/s
    CONFIRMATION      - dialog box that displays the intended modification. user need to respond in order 
                        to proceed or cancel the operation/s.
    VALIDATE_CONTROLS - dialog box to make sure that all inputs are not blank/NULL in order to proceed
    SHUTDOWN_DIALOG   - dialog box to inform user that the server/s will be shutdown
    EXECUTE_MEM       - modify the vMemory of the virtual machine
    EXECUTE_CPU       - modify the vCPU of the virtual machine
    EXECUTE_BOTH      - modify both vCPU and vMemory

.NOTES

    Version: 1.0
    Author:  Rosano C. Gapud
    Created: March 2019
    Purpose: Initial script development

.FUNCTIONALITY

    as of now, the script is limited to vCPU and vMemory modification. 

.OTHERS

    keep it simple. the less click the better.

#>


#================================================================================================================================================


Add-PSsnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null



function CONNECT_VISERVER
   {
    #$vis = $txtbox_vcenter.Text
    foreach ($vi in $txtbox_vcenter.Lines)
        {
            $rtxtbox.AppendText('connecting to vCenter...' + $vi + "`r`n")
            Connect-VIServer $vi -ErrorAction SilentlyContinue | Out-String
            $vclog = Connect-VIServer $vi -ErrorAction SilentlyContinue | Out-String
            $rtxtbox.AppendText($vclog)
            $rtxtbox.AppendText('connected to vcenter server ' + $vi + "`r`n")
        }
   }


function CONFIRMATION
    {
        
       Add-Type -AssemblyName System.Windows.Forms
            If ($Combo_task.SelectedItem -eq 'CPU Add/Remove')
                {$script:confirm = [System.Windows.Forms.MessageBox]::Show('server/s will be reconfigured as follows:' + "`r`n" + "`r`n" + 'vCPU ' + $combo_core.Text,'Please Confirm', 'OKCancel', 'Information', 'Button2')}
            ElseIf($Combo_task.SelectedItem -eq 'Memory Upgrade/Downgrade')
                {$script:confirm = [System.Windows.Forms.MessageBox]::Show('server/s will be reconfigured as follows:' + "`r`n" + "`r`n" + 'vMemory ' + $txtbox_mem.Text,'Please Confirm', 'OKCancel', 'Information', 'Button2')}
            Else
                {$script:confirm = [System.Windows.Forms.MessageBox]::Show('server/s will be reconfigured as follows:' + "`r`n" + "`r`n" + 'vCPU ' + $combo_core.Text + "`r`n" + 'vMemory ' + $txtbox_mem.Text,'Please Confirm', 'OKCancel', 'Information', 'Button2')}
    }



function VALIDATE_CONTROLS
    {
        Add-Type -AssemblyName System.Windows.Forms
        $script:OK = [System.Windows.Forms.MessageBox]::Show("Please complete all information before proceeding." + "`r`n", 'Warning!', 'OK', 'Information', 'Button1')      
    }


function SHUTDOWN_DIALOG
    {
        Add-Type -AssemblyName System.Windows.Forms
        $script:result = [System.Windows.Forms.MessageBox]::Show("This operation will shutdown the server."  + "`r`n"+ "`r`n" + "Do you want to proceed?", 'Warning', 'YesNo', 'Warning', 'Button2')
    }


function EXECUTE_MEM
    {
    $memlog = ''
    ForEach ($vm in $txtbox_servers.Lines)
        {
        $vm = Get-vm $vm
        If ($vm.ExtensionData.Config.MemoryHotAddEnabled -eq "True")
            {
                IF (([INT]$txtbox_mem.Text -lt $vm.MemoryGB) -and ($vm.ExtensionData.Runtime.PowerState -ne "PoweredOff"))
                    {
                        SHUTDOWN_DIALOG
                        SWITCH ($result)
                          {  
                            "YES"
                                {
                                    $rtxtbox.AppendText("`r`n" +'Unable to reduce memory at this state' + "`r`n" +'Shutting DOWN virtual machine' + ' ' + $vm.Name + "`r`n")
                                    Get-VM $vm.Name | Shutdown-VMGuest -Confirm:$false
                                    do 
                                        {
                                            sleep 2
                                            $vm = Get-vm $vm
                                            $vmstate = $vm.ExtensionData.Runtime.PowerState
		                                    $rtxtbox.AppendText('.')
                                        }
                                    while  ($vmstate -eq "poweredOn")
        
                                    $rtxtbox.AppendText("`r`n" + 'Successfully shutdown' + ' ' + $vm + "`r`n" + 'reconfiguring virtual machine')
                                    Sleep 2
                                    Set-VM $vm.Name -MemoryGB $txtbox_mem.Text -Confirm:$false
                                    $rtxtbox.AppendText("`r`n" + 'completed successfully' + "`r`n" + 'restarting')
                                    Start-Sleep 5 
                                    Get-VM $vm.Name | Start-VM -Confirm:$false
                                    $memlog = Get-VM $vm | Out-String
                                    $rtxtbox.AppendText("`r`n" + $memlog + "`r`n")
                                    $rtxtbox.AppendText("`r`n" + 'FINISHED' + "`r`n"+ "`r`n")
                                }
                            
                            "NO"
                                {
                                    $rtxtbox.AppendText("`r`n" + 'operation was CANCELLED' + "`r`n")
                                    BREAK
                                }

                          } #END of SWITCH
                    }
                ELSEIF (([INT]$txtbox_mem.Text -ge $vm.MemoryGB) -and ($vm.ExtensionData.Runtime.PowerState -ne "PoweredOff"))
                    {
                        $rtxtbox.AppendText("`r`n" + 'MemoryHotPlug is ENabled...proceeding without shutdwon' + "`r`n")
                        Set-VM $vm.Name -MemoryGB $txtbox_mem.Text -Confirm:$false
                        $memlog = Get-VM $vm | Out-String
                        $rtxtbox.AppendText("`r`n" + $memlog + "`r`n")  
                        $rtxtbox.AppendText('FINISHED' + "`r`n"+ "`r`n")
                    }
                Else
                    {
                        $rtxtbox.AppendText("`r`n" + $vm + ' ' + 'is already PoweredOff' + "`r`n" + 'reconfiguring virtual machine')
                        Sleep 1
                        Set-VM $vm.Name -MemoryGB $txtbox_mem.Text -Confirm:$false
                        $memlog = Get-VM $vm | Out-String
                        $rtxtbox.AppendText("`r`n" + $memlog + "`r`n")
                        $rtxtbox.AppendText("`r`n" + 'FINISHED' + "`r`n"+ "`r`n")
                    }
            }

	    ElseIf ($vm.ExtensionData.Runtime.PowerState -ne "PoweredOff")	
                {
                    SHUTDOWN_DIALOG
                    SWITCH ($result)
                        {  
                            "YES"
                                {
                                    $rtxtbox.AppendText("`r`n" +'MemoryHotPlug is DISabled' + "`r`n" +'Shutting DOWN virtual machine' + ' ' + $vm.Name + "`r`n")
                                    Get-VM $vm.Name | Shutdown-VMGuest -Confirm:$false

                                    do 
                                        {
                                            sleep 2
                                            $vm = Get-vm $vm
                                            $vmstate = $vm.ExtensionData.Runtime.PowerState
		                                    $rtxtbox.AppendText('.')
                                        }
                                    while  ($vmstate -eq "poweredOn")
        
                                    $rtxtbox.AppendText("`r`n" + 'Successfully shutdown' + ' ' + $vm + "`r`n" + 'reconfiguring virtual machine')
                                    Sleep 2
                                    Set-VM $vm.Name -MemoryGB $txtbox_mem.Text -Confirm:$false
                                    $rtxtbox.AppendText("`r`n" + 'completed successfully' + "`r`n" + 'restarting')
                                    Start-Sleep 5 
                                    Get-VM $vm.Name | Start-VM -Confirm:$false
                                    $memlog = Get-VM $vm | Out-String
                                    $rtxtbox.AppendText("`r`n" + $memlog + "`r`n") 
                                    $rtxtbox.AppendText("`r`n" + 'FINISHED' + "`r`n"+ "`r`n")    
                                }
                            "NO"
                                {
                                    $rtxtbox.AppendText("`r`n" + 'operation was CANCELLED' + "`r`n")
                                    BREAK
                                }
                        }#END OF SWITCH   
                }

        Else
            {
                $rtxtbox.AppendText("`r`n" + $vm + ' ' + 'is already PoweredOff' + "`r`n" + 'reconfiguring virtual machine')
                Sleep 1
                Set-VM $vm.Name -MemoryGB $txtbox_mem.Text -Confirm:$false
                $memlog = Get-VM $vm | Out-String
                $rtxtbox.AppendText("`r`n" + $memlog + "`r`n")
                $rtxtbox.AppendText("`r`n" + 'FINISHED' + "`r`n"+ "`r`n") 
            
            }
        $rtxtbox.SelectionStart = $rtxtbox.Text.Length
	    $rtxtbox.ScrollToCaret()
        }
        
     }



function EXECUTE_CPU
    {
    $cpulog = ''
    ForEach ($vm in $txtbox_servers.Lines)
        {
        $Script:vm = Get-vm $vm
        If (($vm.ExtensionData.Config.CpuHotAddEnabled -eq "True") -and ([INT]$combo_core.SelectedItem -ge $vm.NumCpu) )
            {
                $rtxtbox.AppendText("`r`n" + 'CpuHotPlug is ENabled...proceeding without shutdwon')
                $VMSpec=New-Object –Type VMware.Vim.VirtualMAchineConfigSpec –Property @{“NumCoresPerSocket” = $combo_soc.SelectedItem}
                $vm.ExtensionData.ReconfigVM_Task($VMSpec)
                $vm | Set-VM -NumCPU $combo_core.SelectedItem -Confirm:$false
                $cpulog = Get-VM $vm | Out-String
                $rtxtbox.AppendText("`r`n" + $cpulog + "`r`n" + "FINISHED"+ "`r`n")
                
            }
	    
        
        ElseIf ($vm.ExtensionData.Runtime.PowerState -ne "PoweredOff")	
                {
                
                    SHUTDOWN_DIALOG
                    SWITCH ($result)
                          {  
                            "YES"
                                {
                                    $rtxtbox.AppendText("`r`n" +'CpuHotAdd/Remove is DISabled' + "`r`n" +'Shutting DOWN virtual machine' + ' ' + $vm.Name + "`r`n")
                                    Get-VM $vm.Name | Shutdown-VMGuest -Confirm:$false
                
                                    do 
                                        {
                                            sleep 1
                                            $vm = Get-vm $vm
                                            $vmstate = $vm.ExtensionData.Runtime.PowerState
		                                    $rtxtbox.AppendText('.')
                                        }
                                
                                    while  ($vmstate -eq "poweredOn")
        
                                    $rtxtbox.AppendText("`r`n" + 'Successfully shutdown' + ' ' + $vm + "`r`n" + 'reconfiguring virtual machine')
                                    $VMSpec=New-Object –Type VMware.Vim.VirtualMAchineConfigSpec –Property @{“NumCoresPerSocket” = $combo_soc.SelectedItem}
                                    $vm.ExtensionData.ReconfigVM_Task($VMSpec)
                                    $vm | Set-VM -NumCPU $combo_core.SelectedItem -Confirm:$false
                                    $rtxtbox.AppendText("`r`n" + 'completed successfully' + "`r`n" + 'restarting')
                                    Start-Sleep 5 
                                    Get-VM $vm.Name | Start-VM -Confirm:$false
                                    $cpulog = Get-VM $vm | Out-String
                                    $rtxtbox.AppendText("`r`n" + $cpulog + "`r`n" + "FINISHED"+ "`r`n")
                                }
                           
                             "NO"
                                 { 
                                   $rtxtbox.AppendText("`r`n" + 'operation was CANCELLED' + "`r`n")  
                                   BREAK
                                 }
                            } # END OF SWITCH
                   }

        Else 
            {
                $rtxtbox.AppendText("`r`n" + $vm + ' ' + 'is already PoweredOff' + "`r`n" + 'reconfiguring virtual machine')
                Sleep 1
                $VMSpec=New-Object –Type VMware.Vim.VirtualMAchineConfigSpec –Property @{“NumCoresPerSocket” = $combo_soc.SelectedItem}
                $vm.ExtensionData.ReconfigVM_Task($VMSpec)
                $vm | Set-VM -NumCPU $combo_core.SelectedItem -Confirm:$false
                $cpulog = Get-VM $vm | Out-String
                $rtxtbox.AppendText("`r`n" + $cpulog + "`r`n" + "FINISHED"+ "`r`n") 
            }
        $rtxtbox.SelectionStart = $rtxtbox.Text.Length
	    $rtxtbox.ScrollToCaret()
         }
    }


function EXECUTE_BOTH

    {
    $bothlog = ''
    ForEach ($vm in $txtbox_servers.Lines)
        {
        $vm = Get-vm $vm
        If (($vm.ExtensionData.Config.CpuHotAddEnabled -eq "True")-and ([INT]$combo_core.SelectedItem -ge $vm.NumCpu) -and ($vm.ExtensionData.Config.MemoryHotAddEnabled -eq "True") -and ([INT]$txtbox_mem.Text -ge $vm.MemoryGB))
            {
                $rtxtbox.AppendText("`r`n" + 'CpuHotPlug and MemoryHotPlug is ENabled...proceeding without shutdwon')
                Sleep 1
                Set-VM $vm.Name -MemoryGB $txtbox_mem.Text -Confirm:$false
                $VMSpec=New-Object –Type VMware.Vim.VirtualMAchineConfigSpec –Property @{“NumCoresPerSocket” = $combo_soc.SelectedItem}
                $vm.ExtensionData.ReconfigVM_Task($VMSpec)
                $vm | Set-VM -NumCPU $combo_core.SelectedItem -Confirm:$false
                $bothlog = Get-VM $vm | Out-String
                $rtxtbox.AppendText("`r`n" + $bothlog + "`r`n" + "FINISHED"+ "`r`n")
            }
	    

        ElseIf ($vm.ExtensionData.Runtime.PowerState -ne "PoweredOff")	
                {
                    
                    SHUTDOWN_DIALOG
                    SWITCH ($result)
                          {  
                            "YES"
                                {
                                    $rtxtbox.AppendText("`r`n" +'CpuHotAdd/Remove and/or MemoryHotPlug is DISabled' + "`r`n" +'Shutting DOWN virtual machine' + ' ' + $vm.Name + "`r`n")
                                    Get-VM $vm.Name | Shutdown-VMGuest -Confirm:$false
                                    do 
                                        {
                                            sleep 1
                                            $vm = Get-vm $vm
                                            $vmstate = $vm.ExtensionData.Runtime.PowerState
		                                    $rtxtbox.AppendText('.')
                            
                                        }
                                    while  ($vmstate -eq "poweredOn")
                
                                    $rtxtbox.AppendText("`r`n" + 'Successfully shutdown' + ' ' + $vm + "`r`n" + 'reconfiguring virtual machine')
                                    Sleep 1
                                    Set-VM $vm.Name -MemoryGB $txtbox_mem.Text -Confirm:$false
                                    $VMSpec=New-Object –Type VMware.Vim.VirtualMAchineConfigSpec –Property @{“NumCoresPerSocket” = $combo_soc.SelectedItem}
                                    $vm.ExtensionData.ReconfigVM_Task($VMSpec)
                                    $vm | Set-VM -NumCPU $combo_core.SelectedItem -Confirm:$false
                                    $rtxtbox.AppendText("`r`n" + 'completed successfully' + "`r`n" + 'restarting' + "`r`n")
                                    Start-Sleep 5 
                                    Get-VM $vm.Name | Start-VM -Confirm:$false
                                    $bothlog = Get-VM $vm | Out-String
                                    $rtxtbox.AppendText("`r`n" + $bothlog + "`r`n" + "FINISHED"+ "`r`n")
                                }
                                
                            "NO"
                                {
                                    $rtxtbox.AppendText("`r`n" + 'operation is CANCELLED' + "`r`n")
                                    BREAK
                                }
                            } # END OF SWITCH                                 
                
                }

        Else 
            {
                $rtxtbox.AppendText("`r`n" + $vm + ' ' + 'is already PoweredOff' + "`r`n" + 'reconfiguring virtual machine'  + "`r`n" + 'FINISHED')
                Sleep 1
                Set-VM $vm.Name -MemoryGB $txtbox_mem.Text -Confirm:$false
                $VMSpec=New-Object –Type VMware.Vim.VirtualMAchineConfigSpec –Property @{“NumCoresPerSocket” = $combo_soc.SelectedItem}
                $vm.ExtensionData.ReconfigVM_Task($VMSpec)
                $vm | Set-VM -NumCPU $combo_core.SelectedItem -Confirm:$false
                $bothlog = Get-VM $vm | Out-String
                $rtxtbox.AppendText("`r`n" + $bothlog + "`r`n" + "FINISHED"+ "`r`n")
            }

        $rtxtbox.SelectionStart = $rtxtbox.Text.Length
	    $rtxtbox.ScrollToCaret()
        }
        
     }


function UPGRADE_HARDWARE
    
    {
    ForEach ($vm in $txtbox_servers.Lines)
        {
 	        $temp = $vm
            $vm = Get-vm $vm
            Get-VM $vm | Get-AdvancedSetting -Name ctkEnabled | Set-AdvancedSetting -Value "false" -Confirm:$false
            sleep 10
            $state = $vm.Powerstate
            $hostver = $vm.VMHost.Version
            $vmtoolsstatus = $vm.ExtensionData.Guest.ToolsRunningStatus
            $hwver = $vm.Version

            If (($state -eq "PoweredOn") -and ($vmtoolsstatus -eq "guestToolsRunning") -and ($hostver -ige "6.0.0") -and ($vm.Version -ilt "v11"))
    	        {
                    $rtxtbox.AppendText("`r`n" + 'Shutting DOWN' + ' ' + $vm + "`r`n")
                    #Write-Host "Shutting DOWN $vm" -BackgroundColor Red
                    Get-VM $vm.Name | Stop-VMGuest -Confirm:$false | Out-Null
                        
                        do 
                            {
                                sleep 15
                                $vm = Get-vm $vm.Name
                                $vmstate = $vm.PowerState
		                        Write-Host "." -BackgroundColor Red
                            }
                        while  ($vmstate -eq "PoweredOn")

  	                Set-VM $vm -Version v11 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                    Start-Sleep 5
   	                $vm = Get-VM $vm.Name
    
                    If ($vm.Version -eq "v11")
                        {
                            $rtxtbox.AppendText("`r`n" + 'VM Hardware Successfully Upgraded on' + ' ' + $vm + ' to version 11'+ "`r`n")
                            #Write-Host "VM Hardware Successfully Upgraded on $vm to version 11" -BackgroundColor Green
                        }
                    Else
                        {
                            $rtxtbox.AppendText("`r`n" + 'unable to upgrade' + ' ' + $vm + ' to version 11' + 'PLEASE perform manual upgrade instead' + "`r`n")
                            #Write-Host "unable to upgrade $vm to version 11. PLEASE perform manual upgrade instead" -BackgroundColor Green
                        }
    
                    $rtxtbox.AppendText("`r`n" + 'Powering up' + ' ' + $vm + "`r`n")
                    #Write-Host "Powering up $vm" -BackgroundColor DarkGreen
                    Get-VM $vm | Start-VM -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                }

            ElseIf (($state -eq "PoweredOff") -and ($hostver -ige "6.0.0") -and ($hwver -ilt "v11"))
                {
                        $rtxtbox.AppendText("`r`n" + $vm + 'is already PoweredOFF. Upgrading VM Hardware to version 11' + "`r`n")
                        #Write-Host "$vm is already PoweredOFF. Upgrading VM Hardware to version 11"
                        Set-VM $vm -Version v11 -confirm:$false -ErrorAction SilentlyContinue | Out-Null
                        Start-Sleep 5
                        $vm = Get-VM $vm.Name

                        If ($vm.Version -eq "v11")
            
                            {
                                $rtxtbox.AppendText("`r`n" + 'VM Hardware Successfully Upgraded on' + ' ' + $vm + ' to version 11'+ "`r`n")
                                #Write-Host "VM Hardware Successfully Upgraded to version 11" -BackgroundColor Green
                            }
                
                        Else
                            {
                                $rtxtbox.AppendText("`r`n" + $vm + ' is already at hardware version v11 or higher. Skipping to next vm in the list' + "`r`n")
                                #Write-Host "$vm is already at hardware version v11 or higher. Skipping to next vm in the list" -BackgroundColor Green
                            }
                 }
   
            ElseIf ($vm -eq $null) {Write-Host "$temp is not found"}

            ElseIf ($hostver -ilt "6") { $rtxtbox.AppendText("`r`n" + 'Unable to upgrade' + ' ' + $vm + ' to version 11 because ESXI Host is below 6.0'+ "`r`n")}

            ElseIf (($state -eq "PoweredOn") -and ($vmtoolsstatus -ne "guestToolsRunning")) {$rtxtbox.AppendText("`r`n" + 'Manual upgrade needed. Unable to perform operation. VM Tools is not RUNNING on ' + ' ' + $vm + "`r`n")}

            ElseIf ($vm.Version -ge "v11"){$rtxtbox.AppendText("`r`n" + $vm + ' is already at hardware version v11 or higher. Skipping to next vm in the list' + "`r`n")}

            Sleep 20

            Get-VM $vm | Get-AdvancedSetting -Name ctkEnabled | Set-AdvancedSetting -Value "true" -Confirm:$false
            }
    }




#Generate FORM and CONTROLS
function GENERATE_FORM()
{
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
$Script:main_form = New-Object System.Windows.Forms.Form
$Script:txtbox_servers = New-Object System.Windows.Forms.TextBox
$Script:txtbox_sockets = New-Object System.Windows.Forms.TextBox
$Script:combo_core = New-Object System.Windows.Forms.ComboBox
$Script:combo_soc = New-Object System.Windows.Forms.ComboBox
$lbl_cor = New-Object System.Windows.Forms.Label
$lbl_soc = New-Object System.Windows.Forms.Label
$lbl_sockets = New-Object System.Windows.Forms.Label
$script:txtbox_mem = New-Object System.Windows.Forms.NumericUpDown  #New-Object System.Windows.Forms.TextBox
$lbl_mem = New-Object System.Windows.Forms.Label
$Script:cmd_button = New-Object System.Windows.Forms.Button
$Script:rtxtbox = New-Object System.Windows.Forms.RichTextBox
$Label3 = New-Object System.Windows.Forms.Label
$Script:txtbox_vcenter = New-Object System.Windows.Forms.TextBox
$main_form.Text ='CPU/Memory Configuration'
$main_form.Width = 685
$main_form.Height = 450
$main_form.AutoSize = $true
$main_form.FormBorderStyle = "Fixed3D"
$main_form.MaximizeBox = $false
$Label2 = New-Object System.Windows.Forms.Label
$Label2.Text = "Choose a task"
$Label2.Location  = New-Object System.Drawing.Point(30,20)
$Label2.AutoSize = $true
$main_form.Controls.Add($Label2)
$Label1 = New-Object System.Windows.Forms.Label
$Label1.Text = "vCenter Server:"
$Label1.Location  = New-Object System.Drawing.Point(30,70)
$Label1.AutoSize = $true
$main_form.Controls.Add($Label1)
$script:Combo_task = New-Object System.Windows.Forms.ComboBox
$Combo_task.FlatStyle = "Standard"
$Combo_task.Width = 170
$Combo_task.BackColor = "#ffffff"
$Combo_task.DropDownStyle = 'DropDownList'
$Combo_task.Items.Add(' ')
$Combo_task.Items.Add('Memory Upgrade/Downgrade')
$Combo_task.Items.Add('CPU Add/Remove')
$Combo_task.Items.Add('Both')
$Combo_task.Items.Add('Upgrade VM Hardware')
$Combo_task.Items.Add('Get VM Information')
$Combo_task.Items.Add('Update VM Tools')
$Combo_task.Location = New-Object System.Drawing.Point(30,40)
$Combo_task.Add_SelectedValueChanged(
    {
        $txtbox_sockets.Text = ""
        $txtbox_mem.Text = ""
        IF ($Combo_task.SelectedItem -eq 'CPU Add/Remove')
            {
                $ifexist_txtboxmem = Test-Path variable:txtbox_mem -ErrorAction SilentlyContinue
                $ifexist_lblmem = Test-Path variable:lbl_mem -ErrorAction SilentlyContinue
                IF (($ifexist_txtboxmem -eq 'True') -and ($ifexist_lblmem -eq 'True'))
                    {
                    $txtbox_mem.Visible = $false
                    $lbl_mem.Visible = $false
                    $combo_core.Visible = $true
                    $lbl_cor.Visible = $true
                    $combo_soc.Visible = $true
                    $lbl_soc.Visible = $true
                    $txtbox_sockets.Visible = $true
                    $lbl_sockets.Visible = $true
                    }
                $combo_core.Items.Clear()
                $combo_core.FlatStyle = 'Standard'
                $combo_core.BackColor = "#ffffff"
                $combo_core.Width = 40
                $combo_core.Height = 21
                $combo_core.Location = New-Object System.Drawing.Point(290,40)
                $combo_core.DropDownStyle = 'DropDownList'
                $item = 0
                do
                {
                $item = $item + 1
                $combo_core.Items.Add($item)
                } while ($item -ne 32)
                $main_form.Controls.Add($combo_core)
                $lbl_cor.Text = "Total vCPU"
                $lbl_cor.Location  = New-Object System.Drawing.Point(215,44)
                $lbl_cor.AutoSize = $true
                $main_form.Controls.Add($lbl_cor)
                               
                
                $combo_soc.Items.Clear()
                $combo_soc.FlatStyle = 'Standard'
                $combo_soc.BackColor = "#ffffff"
                $combo_soc.Width = 40
                $combo_soc.Height = 21
                $combo_soc.Location = New-Object System.Drawing.Point(290,65)
                $combo_soc.DropDownStyle = 'DropDownList'
                $main_form.Controls.Add($combo_soc)

                $lbl_soc.Text = "Cores per Socket"
                $lbl_soc.Location  = New-Object System.Drawing.Point(185,69)
                $lbl_soc.AutoSize = $true
                $main_form.Controls.Add($lbl_soc)
                 
                $combo_core.Add_SelectedValueChanged(
                    {
                     $txtbox_sockets.Text = ""
                     $combo_soc.Items.Clear()
                     $vcpu = $combo_core.SelectedItem
                     $n = 1
                        do
                         {
                          $remainder = $vcpu%$n
                          if ($remainder -eq 0)
                          {$combo_soc.Items.Add($n.ToString())}
                          $n = $n + 1
                         }
                        while ($n -ne $vcpu + 1 )
                     })

                
                $txtbox_sockets.Width = 40
                $txtbox_sockets.Height = 21
                $txtbox_sockets.Multiline = $false
                $txtbox_sockets.Location = New-Object System.Drawing.Point(290,90)
                $txtbox_sockets.TextAlign = 'Left'
                $txtbox_sockets.ReadOnly = $true
                $main_form.Controls.Add($txtbox_sockets)
                $lbl_sockets.Text = "no. of Sockets" 
                $lbl_sockets.Location  = New-Object System.Drawing.Point(208,94)
                $lbl_sockets.AutoSize = $true
                $main_form.Controls.Add($lbl_sockets)

                $combo_soc.Add_SelectedValueChanged(
                    {
                      $txtbox_sockets.Text = ($combo_core.SelectedItem/$combo_soc.SelectedItem)
                     
                    })
                
            }
        ELSEIF ($Combo_task.SelectedItem -eq 'Memory Upgrade/Downgrade')
            {
                $ifexist_combo_core = Test-Path variable:combo_core -ErrorAction SilentlyContinue
                $ifexist_lblcor = Test-Path variable:lbl_cor -ErrorAction SilentlyContinue
                $ifexist_combo_soc = Test-Path variable:combo_soc -ErrorAction SilentlyContinue
                $ifexist_lbl_soc = Test-Path variable:lbl_soc -ErrorAction SilentlyContinue
                $ifexist_txtbox_sockets = Test-Path variable:txtbox_sockets -ErrorAction SilentlyContinue
                $ifexist_lbl_sockets = Test-Path variable:lbl_sockets -ErrorAction SilentlyContinue
                
                IF (($ifexist_combo_core -eq 'True') -and ($ifexist_lblcor -eq 'True') -and ($ifexist_combo_soc -eq 'True') -and ($ifexist_lbl_soc -eq 'True') -and ($ifexist_lbl_sockets -eq 'True')-and ($ifexist_txtbox_sockets -eq 'True'))
                    {
                    $txtbox_mem.Visible = $True
                    $lbl_mem.Visible = $True
                    $combo_core.Visible = $false
                    $combo_soc.Visible = $false
                    $lbl_cor.Visible = $false
                    $lbl_soc.Visible = $false
                    $txtbox_sockets.Visible = $false
                    $lbl_sockets.Visible = $false

                    }
                $txtbox_mem.Width = 40
                $txtbox_mem.Height = 21
                #$txtbox_mem.Multiline = $false
                $txtbox_mem.Location = New-Object System.Drawing.Point(290,40)
                $txtbox_mem.TextAlign = 'Left'
                $main_form.Controls.Add($txtbox_mem)
                $lbl_mem.Text = "Memory in GB" 
                $lbl_mem.Location  = New-Object System.Drawing.Point(208,44)
                $lbl_mem.AutoSize = $true
                $main_form.Controls.Add($lbl_mem)
            }
        
        ELSEIF ($Combo_task.SelectedItem -eq 'Both')
            {
                $ifexist_combo_core = Test-Path variable:combo_core -ErrorAction SilentlyContinue
                $ifexist_lblcor = Test-Path variable:lbl_cor -ErrorAction SilentlyContinue
		        $ifexist_txtboxmem = Test-Path variable:txtbox_mem -ErrorAction SilentlyContinue
                $ifexist_lblmem = Test-Path variable:lbl_mem -ErrorAction SilentlyContinue
                $ifexist_combo_soc = Test-Path variable:combo_soc -ErrorAction SilentlyContinue
                $ifexist_lbl_soc = Test-Path variable:lbl_soc -ErrorAction SilentlyContinue
                $ifexist_txtbox_sockets = Test-Path variable:txtbox_sockets -ErrorAction SilentlyContinue
                $ifexist_lbl_sockets = Test-Path variable:lbl_soc -ErrorAction SilentlyContinue
                IF (($ifexist_combo_core -eq 'True') -and ($ifexist_lblcor -eq 'True') -and ($ifexist_txtboxmem -eq 'True') -and ($ifexist_lblmem -eq 'True')-and ($ifexist_combo_soc -eq 'True') -and ($ifexist_lbl_soc -eq 'True')-and ($ifexist_lbl_sockets -eq 'True')-and ($ifexist_txtbox_sockets -eq 'True'))
                    {
                    $txtbox_mem.Visible = $True
                    $lbl_mem.Visible = $True
                    $combo_core.Visible = $True
                    $lbl_cor.Visible = $True
                    $combo_soc.Visible = $True
                    $lbl_soc.Visible = $True
                    $txtbox_sockets.Visible = $true
                    $lbl_sockets.Visible = $true
                    }
                $txtbox_mem.Width = 40
                $txtbox_mem.Height = 21
                #$txtbox_mem.Multiline = $false
                $txtbox_mem.Location = New-Object System.Drawing.Point(290,115)
                $txtbox_mem.TextAlign = 'Left'
                $main_form.Controls.Add($txtbox_mem)
                $lbl_mem.Text = "Memory in GB" 
                $lbl_mem.Location  = New-Object System.Drawing.Point(208,119)
                $lbl_mem.AutoSize = $true
                $main_form.Controls.Add($lbl_mem)
		        $combo_core.Items.Clear()
                $combo_core.FlatStyle = 'Standard'
                $combo_core.BackColor = "#ffffff"
                $combo_core.Width = 40
                $combo_core.Height = 21
                $combo_core.Location = New-Object System.Drawing.Point(290,40)
                $combo_core.DropDownStyle = 'DropDownList'
                $item = 0
                do
                {
                $item = $item + 1
                $combo_core.Items.Add($item)
                } while ($item -ne 64)
                $main_form.Controls.Add($combo_core)
                $lbl_cor.Text = "Total vCPU"
                $lbl_cor.Location  = New-Object System.Drawing.Point(215,44)
                $lbl_cor.AutoSize = $true
                $main_form.Controls.Add($lbl_cor)

                $combo_soc.Items.Clear()
                $combo_soc.FlatStyle = 'Standard'
                $combo_soc.BackColor = "#ffffff"
                $combo_soc.Width = 40
                $combo_soc.Height = 21
                $combo_soc.Location = New-Object System.Drawing.Point(290,65)
                $combo_soc.DropDownStyle = 'DropDownList'
                $main_form.Controls.Add($combo_soc)

                $lbl_soc.Text = "Cores per Socket"
                $lbl_soc.Location  = New-Object System.Drawing.Point(185,69)
                $lbl_soc.AutoSize = $true
                $main_form.Controls.Add($lbl_soc)


                $combo_core.Add_SelectedValueChanged(
                    {
                     $combo_soc.Items.Clear()
                     $vcpu = $combo_core.SelectedItem
                     $n = 1
                        do
                         {
                          $remainder = $vcpu%$n
                          if ($remainder -eq 0)
                          {$combo_soc.Items.Add($n.ToString())}
                          $n = $n + 1
                         }
                        while ($n -ne $vcpu + 1 )
                     })


                $txtbox_sockets.Width = 40
                $txtbox_sockets.Height = 21
                $txtbox_sockets.Multiline = $false
                $txtbox_sockets.Location = New-Object System.Drawing.Point(290,90)
                $txtbox_sockets.TextAlign = 'Left'
                $txtbox_sockets.ReadOnly = $true
                $main_form.Controls.Add($txtbox_sockets)
                $lbl_sockets.Text = "no. of Sockets" 
                $lbl_sockets.Location  = New-Object System.Drawing.Point(208,94)
                $lbl_sockets.AutoSize = $true
                $main_form.Controls.Add($lbl_sockets)

                $combo_soc.Add_SelectedValueChanged(
                    {
                      $txtbox_sockets.Text = ($combo_core.SelectedItem/$combo_soc.SelectedItem)
                     
                    })

            }

        
        ELSE
            {
            $combo_core.Visible = $false
            $lbl_cor.Visible = $false
            $txtbox_mem.Visible = $false
            $lbl_mem.Visible = $false
            $combo_soc.Visible = $false
            $lbl_soc.Visible = $false
            $txtbox_sockets.Visible = $false
            $lbl_sockets.Visible = $false
            }
    })


$main_form.Controls.Add($Combo_task)
$txtbox_servers.Width = 300
$txtbox_servers.Height = 230
$txtbox_servers.Multiline = $true
$txtbox_servers.Location = New-Object System.Drawing.Point(30,140)
$watermark =  'one server per line, no spaces...'
$txtbox_servers.Text = $watermark
$txtbox_servers.ForeColor = 'LightGray'
$txtbox_servers.add_MouseClick(
    {
        If ($txtbox_servers.Text-eq $watermark)
            {
                $txtbox_servers.Text = ""
                $txtbox_servers.ForeColor = 'WindowText'
            }
    })
$txtbox_servers.add_GotFocus(
    {
        If ($txtbox_servers.Text-eq $watermark)
            {
                $txtbox_servers.Text = ""
                $txtbox_servers.ForeColor = 'WindowText'
            }
    })
$main_form.Controls.Add($txtbox_servers)
$cmd_button.Location = New-Object System.Drawing.Size(211,382)
$cmd_button.Size = New-Object System.Drawing.Size(120,23)
$cmd_button.Text = "Execute"
$main_form.Controls.Add($cmd_button)
$CancelButton = New-Object System.Windows.Forms.Button
$CancelButton.Location = New-Object System.Drawing.Size(530,382)
$CancelButton.Size = New-Object System.Drawing.Size(120,23)
$CancelButton.Text = "Cancel"
$main_form.Controls.Add($CancelButton)
$CancelButton.Add_Click({$main_form.Close()})
$rtxtbox.Width = 300
$rtxtbox.Height = 330
$rtxtbox.Multiline = $true
$rtxtbox.font = "Arial"
$rtxtbox.Location = New-Object System.Drawing.Point(350,40)
$rtxtbox.ReadOnly = $true
$rtxtbox.ScrollBars = "Vertical"
$rtxtbox.WordWrap = $true 
$rtxtbox.BackColor = "#ffffff"
$main_form.Controls.Add($rtxtbox)
$Label3 = New-Object System.Windows.Forms.Label
$Label3.Text = "Details"
$Label3.Location  = New-Object System.Drawing.Point(350,18)
$Label3.AutoSize = $true
$main_form.Controls.Add($Label3)
$txtbox_vcenter.Width = 170
$txtbox_vcenter.Multiline = $true
$txtbox_vcenter.Location = New-Object System.Drawing.Point(30,90)
$main_form.Controls.Add($txtbox_vcenter)
$Label4 = New-Object System.Windows.Forms.Label
$Label4.Text = "Enter server/s here:"
$Label4.Location  = New-Object System.Drawing.Point(30,120)
$Label4.AutoSize = $true
$main_form.Controls.Add($Label4)
#MAIN
$cmd_button.add_Click(
    {
    
    $rtxtbox.Text = ""
    CONNECT_VISERVER
    
    
    SWITCH ($Combo_task.Text)
    {
    "Memory Upgrade/Downgrade" 
        {
            IF ([string]::IsNullOrWhiteSpace($txtbox_servers.Text) -or [string]::IsNullOrWhiteSpace($txtbox_vcenter.Text) -or [string]::IsNullOrWhiteSpace($txtbox_mem.Text))
                {
                    VALIDATE_CONTROLS
                }
        
            Else
                {
                    CONFIRMATION
                        Switch ($confirm)
                            {
                            "OK"
                                {
                                    EXECUTE_MEM
                                }
                            "Cancel"
                                {
                                    Break
                                }
                            } #END OF SWITCH
                    
                }
        }
    
    "CPU Add/Remove"
        {
        
            IF ([string]::IsNullOrWhiteSpace($txtbox_servers.Text) -or [string]::IsNullOrWhiteSpace($txtbox_vcenter.Text) -or [string]::IsNullOrWhiteSpace($combo_core.Text) -or [string]::IsNullOrWhiteSpace($combo_soc.Text))
                {
                    VALIDATE_CONTROLS
                }
            Else
                {
                    CONFIRMATION
                        Switch ($confirm)
                            {
                            "OK"
                                {
                                    EXECUTE_CPU
                                }
                            "Cancel"
                                {
                                    Break
                                }
                            } #END OF SWITCH
                }
        }

    
    "Both"
        {
            IF ([string]::IsNullOrWhiteSpace($txtbox_servers.Text) -or [string]::IsNullOrWhiteSpace($txtbox_vcenter.Text) -or [string]::IsNullOrWhiteSpace($combo_core.Text) -or [string]::IsNullOrWhiteSpace($combo_soc.Text) -or [string]::IsNullOrWhiteSpace($txtbox_servers.Text) -or [string]::IsNullOrWhiteSpace($txtbox_vcenter.Text) -or [string]::IsNullOrWhiteSpace($txtbox_mem.Text))
                {
                    VALIDATE_CONTROLS
                }
        
            Else
                {
                    CONFIRMATION
                        Switch ($confirm)
                            {
                            "OK"
                                {
                                    EXECUTE_BOTH
                                }
                            "Cancel"
                                {
                                    Break
                                }
                            } #END OF SWITCH

                }
        }
    }
    
    
    
    })   #END OF SWITCH             

$main_form.ShowDialog()


}


GENERATE_FORM
