<#
.SYNOPSIS
    Performs a digitial evidence capture operation on a target VM 

.DESCRIPTION
    This is sample code, please be sure to read
    https://docs.microsoft.com/azure/architecture/example-scenario/forensics/ to get
    all the requirements in place and adapt the code to your environment by replacing
    the placeholders and adding the required code blocks before using it. Key outputs
    are in the script for debug reasons, remove the output after the initial tests to
    improve the security of your script.
    
    This is designed to be run from a Windows Hybrid Runbook Worker in response to a
    digitial evidence capture request for a target VM.  It will create disk snapshots
    for all disks, copying them to immutable SOC storage, and take a SHA-256 hash and
    storing the results in your SOC Key Vault.

    This script depends on Az.Accounts, Az.Compute, Az.Storage, and Az.KeyVault being 
    imported in your Azure Automation account.
    See: https://docs.microsoft.com/en-us/azure/automation/az-modules

.EXAMPLE
    Copy-VmDigitialEvidence -SubscriptionId ffeeddcc-bbaa-9988-7766-554433221100 -ResourceGroupName rg-finance-vms -VirtualMachineName vm-workstation-001

.LINK
    https://docs.microsoft.com/azure/architecture/example-scenario/forensics/
#>

param (
    # The ID of subscription in which the target Virtual Machine is stored
    [Parameter(Mandatory = $true)]
    [string]
    $SubscriptionId,

    # The Resource Group containing the Virtual Machine
    [Parameter(Mandatory = $true)]
    [string]
    $ResourceGroupName,

    # The name of the target Virtual Machine
    [Parameter(Mandatory = $true)]
    [string]
    $VirtualMachineName
)

$ErrorActionPreference = 'Stop'

######################################### SOC Constants #####################################
# Update the following constants with the values related to your environment
# SOC Team Evidence Resources
$destSubId = 'xxx-xxx-xxx-xxx'              # The subscription containing the storage account being copied to (ex. 00112233-4455-6677-8899-aabbccddeeff)
$destRGName = ''             # The name of the resource group containing the storage account being copied to 
$destSAblob = ''             # The name of the storage account for BLOB
$destSAfile = ''             # The name of the storage account for FILE
$destTempShare = ''          # The temporary file share mounted on the hybrid worker
$destSAContainer = ''        # The name of the container within the storage account
$destKV = ''                 # The name of the keyvault to store a copy of the BEK in the dest subscription

$targetWindowsDir = "Z:\"            # The mapping path to the share that will contain the disk and its hash. By default the scripts assume you mounted the Azure file share on drive Z.
                                                      # If you need a different mounting point, update Z: in the script or set a variable for that. 
$snapshotPrefix = (Get-Date).toString('yyyyMMddHHmm') # The prefix of the snapshot to be created

#############################################################################################
################################## Hybrid Worker Check ######################################
$bios= Get-WmiObject -class Win32_BIOS
if ($bios) {   
    Write-Output "Running on Hybrid Worker - Verification is Complete Ln-67"

    ################################## Mounting fileshare #######################################
    # The Storage account also hosts an Azure file share to use as a temporary repository for calculating the snapshot's SHA-256 hash value.
    # The following doc shows a possible way to mount the Azure file share on Z:\ :
    # https://docs.microsoft.com/azure/storage/files/storage-how-to-use-files-windows
    
	# This will confirm the current running context of the runbook for debugging purposes should you need it.
    Write-Output "Confirming the currenct context"
	[Security.Principal.WindowsIdentity]::GetCurrent()

	Write-Output "Deleting mounted drives & getting a list of existing drives."
	Remove-PSDrive X,W,Z -Force -Verbose 
	Get-PSDrive
	
	Write-Output "Validating conectivity to Azure Storage and mapping drive."
	$connectTestResult = Test-NetConnection -ComputerName STORAGEACCOUNTNAME.file.core.windows.net -Port 445
	if ($connectTestResult.TcpTestSucceeded) {
    # Save the password so the drive will persist on reboot
    cmd.exe /C "cmdkey /add:`"<STORAGEACCOUNTNAME>.file.core.windows.net`" /user:`"localhost\<STORAGEACCOUNTNAME>`" /pass:`"<STORAGEACCOUNTKEY>`""
    # Mount the drive
    New-PSDrive -Name Z -PSProvider FileSystem -Root "\\<STORAGEACCOUNTNAME>.file.core.windows.net\workershare" -Persist
	} else {
    Write-Error -Message "Unable to reach the Azure storage account via port 445. Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
	}
	Write-Output "Updating the output of connected drives."
	Get-PSDrive
    ################################## Login session ############################################
    # Connect to Azure (via Managed Identity or Azure Automation's RunAs Account)
    #
    # Feel free to adjust the following lines to invoke Connect-AzAccount via
    # whatever mechanism your Hybrid Runbook Workers are configured to use.
    #
    # Whatever service principal is used, it must have the following permissions
    #  - "Contributor" on the Resource Group of target Virtual Machine. This provide snapshot rights on Virtual Machine disks
    #  - "Storage Account Contributor" on the immutable SOC Storage Account
    #  - Access policy to Get Secret (for BEK key) and Get Key (for KEK key, if present) on the Key Vault used by target Virtual Machine
    #  - Access policy to Set Secret (for BEK key) and Create Key (for KEK key, if present) on the SOC Key Vault

    Add-AzAccount -Identity
	$tenantContext = get-AzTenant
	Write-Output $tenantContext

    ############################# Snapshot the OS disk of target VM ##############################
    Write-Output "#################################"
    Write-Output "Snapshotting the OS Disk of your target VM"
    Write-Output "#################################"

    Get-AzSubscription -SubscriptionId $SubscriptionId | Set-AzContext
	$con = Get-AzContext
	Write-Output $con
    $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName

    $disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $vm.StorageProfile.OsDisk.Name
    $snapshot = New-AzSnapshotConfig -SourceUri $disk.Id -CreateOption Copy -Location $vm.Location
    $snapshotName = $snapshotPrefix + "-" + $disk.name.Replace("_","-")
    New-AzSnapshot -ResourceGroupName $ResourceGroupName -Snapshot $snapshot -SnapshotName $snapshotname


    ##################### Copy the OS snapshot from source to file share and blob container ########################
    Write-Output "#################################"
    Write-Output "Copying the OS snapshot from the source to the specified file share and blob container"
    Write-Output "#################################"

    $snapSasUrl = Grant-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $snapshotName -DurationInSecond 72000 -Access Read
    Get-AzSubscription -SubscriptionId $destSubId | Set-AzContext
    $targetStorageContextBlob = (Get-AzStorageAccount -ResourceGroupName $destRGName -Name $destSAblob).Context
    $targetStorageContextFile = (Get-AzStorageAccount -ResourceGroupName $destRGName -Name $destSAfile).Context

    Write-Output "Starting to copy to Blob $SnapshotName"
    Start-AzStorageBlobCopy -AbsoluteUri $snapSasUrl.AccessSAS -DestContainer $destSAContainer -DestContext $targetStorageContextBlob -DestBlob "$SnapshotName.vhd" -Force

    Write-Output "Starting to copy to Fileshare"
    Start-AzStorageFileCopy -AbsoluteUri $snapSasUrl.AccessSAS -DestShareName $destTempShare -DestContext $targetStorageContextFile -DestFilePath $SnapshotName -Force

    Write-Output "Waiting for the fileshare copy to end"
    Get-AzStorageFileCopyState -Context $targetStorageContextFile -ShareName $destTempShare -FilePath $SnapshotName -WaitForComplete

    #Windows hash version if you use a Windows Hybrid Runbook Worker
     $diskpath = "$targetWindowsDir\$snapshotName" 
    Write-Output "Starting the calculation of the file HASH for $diskpath using SHA256. This may take a while."
    Get-ChildItem "$diskpath" | Select-Object -Expand FullName | ForEach-Object{Write-Output $_}
    $hash = (Get-FileHash $diskpath -Algorithm SHA256).Hash
    Write-Output "Computed SHA-256 successfully: $hash"

    #################### Copy the OS BEK to the SOC Key Vault  ###################################
    $BEKurl = $disk.EncryptionSettingsCollection.EncryptionSettings.DiskEncryptionKey.SecretUrl
    Write-Output "#################################"
    Write-Output "OS Disk Encryption Secret URL: $BEKurl"
    Write-Output "#################################"
    if ($BEKurl) {
        Get-AzSubscription -SubscriptionId $SubscriptionId | Set-AzContext
        $sourcekv = $BEKurl.Split("/")
        $BEK = Get-AzKeyVaultSecret -VaultName  $sourcekv[2].split(".")[0] -Name $sourcekv[4] -Version $sourcekv[5]
        Write-Output "Key value: $BEK"
        Get-AzSubscription -SubscriptionId $destSubId | Set-AzContext
        Set-AzKeyVaultSecret -VaultName $destKV -Name $snapshotName -SecretValue $BEK.SecretValue -ContentType "BEK" -Tag $BEK.Tags
    }


    ######## Copy the OS disk hash value in key vault and delete disk in file share ##################
    Write-Output "#################################"
    Write-Output "OS disk - Putting hash value into the specified Key Vault"
    Write-Output "#################################"
    $secret = ConvertTo-SecureString -String $hash -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $destKV -Name "$SnapshotName-sha256" -SecretValue $secret -ContentType "text/plain"
    Get-AzSubscription -SubscriptionId $destSubId | Set-AzContext
    $targetStorageContextFile = (Get-AzStorageAccount -ResourceGroupName $destRGName -Name $destSAfile).Context
    Remove-AzStorageFile -ShareName $destTempShare -Path $SnapshotName -Context $targetStorageContextFile


    ############################ Snapshot the data disks, store hash and BEK #####################
    $dsnapshotList = @()

    foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
        $ddisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $dataDisk.Name
        $dsnapshot = New-AzSnapshotConfig -SourceUri $ddisk.Id -CreateOption Copy -Location $vm.Location
        $dsnapshotName = $snapshotPrefix + "-" + $ddisk.name.Replace("_","-")
        $dsnapshotList += $dsnapshotName
        Write-Output "Snapshot data disk name: $dsnapshotName"
        New-AzSnapshot -ResourceGroupName $ResourceGroupName -Snapshot $dsnapshot -SnapshotName $dsnapshotName
        
        Write-Output "#################################"
        Write-Output "Copy the Data Disk $dsnapshotName snapshot from source to specified blob container"
        Write-Output "#################################"

        $dsnapSasUrl = Grant-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $dsnapshotName -DurationInSecond 72000 -Access Read
        $targetStorageContextBlob = (Get-AzStorageAccount -ResourceGroupName $destRGName -Name $destSABlob).Context
        $targetStorageContextFile = (Get-AzStorageAccount -ResourceGroupName $destRGName -Name $destSAFile).Context

        Write-Output "Starting to copy to Blob $dsnapshotName"
        Start-AzStorageBlobCopy -AbsoluteUri $dsnapSasUrl.AccessSAS -DestContainer $destSAContainer -DestContext $targetStorageContextBlob -DestBlob "$dsnapshotName.vhd" -Force

        Write-Output "Starting to copy to Fileshare"
        Start-AzStorageFileCopy -AbsoluteUri $dsnapSasUrl.AccessSAS -DestShareName $destTempShare -DestContext $targetStorageContextFile -DestFilePath $dsnapshotName  -Force
        
        Write-Output "Waiting for the Fileshare copy task to end"
        Get-AzStorageFileCopyState -Context $targetStorageContextFile -ShareName $destTempShare -FilePath $dsnapshotName -WaitForComplete
                
        $ddiskpath = "$targetWindowsDir\$snapshotName"
        Write-Output "Starting the calculation of the file HASH for $ddiskpath using SHA256. This may take a while."
        Get-ChildItem "$ddiskpath" | Select-Object -Expand FullName | ForEach-Object{Write-Output $_}
        $hash = (Get-FileHash $diskpath -Algorithm SHA256).Hash
        Write-Output "Computed SHA-256 successfully: $dhash"

        
        
        $BEKurl = $ddisk.EncryptionSettingsCollection.EncryptionSettings.DiskEncryptionKey.SecretUrl
        Write-Output "#################################"
        Write-Output "Disk Encryption Secret URL: $BEKurl"
        Write-Output "#################################"
        if ($BEKurl) {
            Get-AzSubscription -SubscriptionId $SubscriptionId | Set-AzContext
            $sourcekv = $BEKurl.Split("/")
            $BEK = Get-AzKeyVaultSecret -VaultName  $sourcekv[2].split(".")[0] -Name $sourcekv[4] -Version $sourcekv[5]
            Write-Output "Key value: $BEK"
            Write-Output "Secret name: $dsnapshotName"
            Get-AzSubscription -SubscriptionId $destSubId | Set-AzContext
            Set-AzKeyVaultSecret -VaultName $destKV -Name $dsnapshotName -SecretValue $BEK.SecretValue -ContentType "BEK" -Tag $BEK.Tags
        }
        else {
            Write-Output "Disk not encrypted"
        }

        Write-Output "#################################"
        Write-Output "Data disk - Put hash value in Key Vault"
        Write-Output "#################################"
        $Secret = ConvertTo-SecureString -String $dhash -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $destKV -Name "$dsnapshotName-sha256" -SecretValue $Secret -ContentType "text/plain"
        $targetStorageContextFile = (Get-AzStorageAccount -ResourceGroupName $destRGName -Name $destSAfile).Context
        Remove-AzStorageFile -ShareName $destTempShare -Path $dsnapshotName -Context $targetStorageContextFile
    }


    ################################## Delete all source snapshots ###############################
    Get-AzStorageBlobCopyState -Blob "$snapshotName.vhd" -Container $destSAContainer -Context $targetStorageContextBlob -WaitForComplete
    foreach ($dsnapshotName in $dsnapshotList) {
        Get-AzStorageBlobCopyState -Blob "$dsnapshotName.vhd" -Container $destSAContainer -Context $targetStorageContextBlob -WaitForComplete
    }

    Get-AzSubscription -SubscriptionId $SubscriptionId | Set-AzContext
    Revoke-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $snapshotName
    Remove-AzSnapshot -ResourceGroupName $ResourceGroupName -SnapshotName $snapshotname -Force
    foreach ($dsnapshotName in $dsnapshotList) {
        Revoke-AzSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $dsnapshotName
        Remove-AzSnapshot -ResourceGroupName $ResourceGroupName -SnapshotName $dsnapshotname -Force
    }
}
else {
    Write-Information "This runbook must Run on an Hybrid Worker. Please retry selecting the HybridWorker"
}
