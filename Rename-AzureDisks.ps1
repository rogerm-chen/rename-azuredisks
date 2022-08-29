<#
.SYNOPSIS Rename Azure OS Disk.

.DESCRIPTION Rename Azure VM OS Disk for Linux and Windows.

.NOTES File Name : Rename-AzOSDisk.ps1
Original Author : Microsoft MVP/MCT - Charbel Nemnom
Updated by : Roger Chen
Version : 1.0
Date : 30-August-2022
Requires : PowerShell 5.1 or PowerShell 7.2.x (Core)
Module : Az Module
OS : Windows or Linux VMs
Note: This script is largely borrowed from Charbel Nemnom's original script https://charbelnemnom.com/how-to-rename-azure-virtual-machine-os-disk/
the original script didn't include the consideration of datadisks, so I expanded the script to include that function

.EXAMPLE
.\Rename-AzureDisks.ps1 -resourceGroup [ResourceGroupName] -VMName [VMName] -osdiskName [OSDiskName] -SubscriptionID [SubscriptionID]
This example will rename the OS Disk for the specified VM, you need to specify the Resource Group name, VM name and the new OS disk name.
When there's datadisks discovered, it will ask you to input original datadisks names, and renames them as well
#>

[CmdletBinding()]
Param (
	[Parameter(Position = 0, Mandatory = $true, HelpMessage = 'Enter the Resource Group of the VM')]
	[Alias('rg')]
	[String]$resourceGroup,

	[Parameter(Position = 1, Mandatory = $True, HelpMessage = 'Enter Azure VM name')]
	[Alias('VM')]
	[String]$VMName,

	[Parameter(Position = 2, Mandatory = $true, HelpMessage = 'Enter the desired OS Disk name')]
	[Alias('DiskName')]
	[String]$osdiskName,

	[Parameter(Position = 2, Mandatory = $true, HelpMessage = 'Enter the subscription id')]
	[Alias('subID')]
	[String]$subscriptionID

)

#! Install Az Module If Needed
function Install-Module-If-Needed {
	param([string]$ModuleName)

	if (Get-Module -ListAvailable -Name $ModuleName) {
		Write-Host "Module '$($ModuleName)' already exists." -ForegroundColor Green
	}
	else {
		Write-Host "Module '$($ModuleName)' does not exist, installing..." -ForegroundColor Yellow
		Install-Module $ModuleName -Force -AllowClobber -ErrorAction Stop
		Write-Host "Module '$($ModuleName)' installed." -ForegroundColor Green
	}
}

function swap-disk {
	[CmdletBinding()]
	param(
		[string]$sourcediskskuname,
		[string]$sourcedisksize,
		[string]$sourcediskid,
		[string]$newdiskname,
		[Switch]$isDatadisk,
		[Switch]$isOSdisk,
		[int]$lun,
		[string]$tempDiskName
	) 
	Write-host "Create the managed disk configuration..."
	$diskConfig = New-AzDiskConfig -SkuName $sourcediskskuname -Location $VM.Location `
		-DiskSizeGB $sourcedisksize -SourceResourceId $sourcediskid -CreateOption Copy	
	Write-host "Deleting the previous Disk: $newdiskName"
	Remove-AzDisk -ResourceGroupName $resourceGroup -DiskName $newdiskname -Force -Confirm:$false
	Write-host "Create the new disk: $newdiskName"
	$newDisk = New-AzDisk -Disk $diskConfig -DiskName $newdiskName -ResourceGroupName $resourceGroup
	if ($isOSdisk.IsPresent) {
		Write-host "Swap the OS disk to: $newdiskname"
		Set-AzVMOSDisk -VM $VM -ManagedDiskId $newDisk.Id -Name $newdiskname | Out-Null 
		
	}
	elseif ($isDatadisk.IsPresent) {
		Write-host "removing the temp data disk: $newdiskname"
		Remove-AzVMDataDisk -VM $VM -Name $tempDiskName
		Update-AzVM -ResourceGroupName $resourceGroup -VM $VM
		Write-host "Add the Data disk: $newdiskname"
		add-AzVMDataDisk -VM $VM -ManagedDiskId $newDisk.Id -Name $newdiskname -lun $lun -CreateOption attach | Out-Null 
		
	}
}

Install-Module-If-Needed Az.Accounts

#! Check Azure Connection
Try {
Write-Verbose "Connecting to Azure Cloud..."
Connect-AzAccount -ErrorAction Stop | Out-Null
Select-AzSubscription -Subscription $subscriptionID
}
Catch {
Write-Warning "Cannot connect to Azure Cloud. Please check your credentials. Exiting!"
Break
}

#! Install Az Compute Module If Needed
Install-Module-If-Needed Az.Compute

#! Get the details of the VM
Write-Verbose "Get the VM information details: $VMName"
$VM = Get-AzVM -Name $VMName -ResourceGroupName $resourceGroup

#! swap OS Disk
Write-host "Get the source OS Disk information: $($VM.StorageProfile.OsDisk.Name)"
$sourceOSDisk = Get-AzDisk -ResourceGroupName $resourceGroup -DiskName $VM.StorageProfile.OsDisk.Name
Write-host "Swapping OS Disk now" -ForegroundColor Green
swap-disk -sourcediskskuname $sourceOSDisk.Sku.Name -sourcedisksize $sourceOSDisk.DiskSizeGB -sourcediskid $sourceOSDisk.Id -newdiskname $osdiskName -isOSdisk
Write-host "OS disk swapping is done" -ForegroundColor Green

#! swap Data Disks
if ($vm.storageprofile.datadisks) { 
	Write-host "Datadisk detected! swapping data disk now, please enter data disk name in sequence" -ForegroundColor Green
	foreach ($datadisk in $vm.storageProfile.datadisks) { 
		write-host "diskname is "$datadisk.name""
		$diskdetails = Get-AzDisk -ResourceGroupName $resourceGroup -DiskName $datadisk.name
		write-host "diskdetail is "$didkdetails""
		$desireddatadiskname = Read-Host "enter your desired data disk name"
	
		swap-disk -sourcediskskuname $diskdetails.Sku.Name -sourcedisksize $diskdetails.DiskSizeGB -sourcediskid $diskdetails.Id -newdiskname $desireddatadiskname -lun $datadisk.lun -tempDiskName $datadisk.name -isDatadisk
	}
	
}



Write-host "updating VM with new disk configured..."
Update-AzVM -ResourceGroupName $resourceGroup -VM $VM
Write-host "Datadisk swapping is done" -ForegroundColor Green
