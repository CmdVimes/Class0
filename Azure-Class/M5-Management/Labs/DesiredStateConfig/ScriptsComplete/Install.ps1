#region Load dependent modules
Import-Module Azure -Force
#endregion

#region Initialize variables
$currentDirectory = "[Local-directory-where-scripts-are-located]"
$subscriptionName = "[The-name-of-your-Azure-subscription]”
$publishSettingsFileName = "[The-name-of-your-publishsettings-file-including-file-extension]"
$location = "[Data-Center or Region]"
$contentInstallPath = "[Location where you xWebAdministration source folder exists]"

$storageAccountName = "[Your-storage-account-name]"
$configurationScript = Join-Path $currentDirectory 'SimpleWebServerConfiguration.ps1'
$configurationName = "InstallWebServer"

$vmName = "[Name-to-give-new-virtual-machine]"
$vmServiceName = "${vmName}-Service"
$vmFQDN = "$vmServiceName.cloudapp.net"

# Local Credential for the Azure VM
$userName = "[RDP-User-name]"
$password = "[RDP-Password]"


$dscExtensionVersion = "1.9" #you may need to change this depending on which version of DSC is installed
$configurationArchive = [IO.Path]::GetFileName($configurationScript) + ".zip"
$configurationDataPath = Join-Path $currentDirectory "ConfigurationData.psd1"

# This is the location, on the new VM, where the Bakery web site code will be pulled from
$websiteSourceLocation = "C:\Program Files\WindowsPowerShell\Modules\xWebAdministration\BakeryWebsite"
#endregion


#region Initialize Azure Subscription settings in current context
Get-AzureSubscription | Remove-AzureSubscription -Force

# Set the full path to the publishsettingsfile, then import the file and select the subscription and storage
# account to use
$myConfigPath = Join-Path $currentDirectory $publishSettingsFileName
Import-AzurePublishSettingsFile $myConfigPath
Select-AzureSubscription -SubscriptionName $subscriptionName
Set-AzureSubscription -CurrentStorageAccountName $storageAccountName -SubscriptionName $subscriptionName -Verbose
#endregion

#region Obtain Azure Storage Context
$storageAccountKey = (Get-AzureStorageKey $storageAccountName).Primary
$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey -Protocol https 

#endregion

# Copy the BakeryWebsite folder into the xWebAdministration folder so it is zipped up as a resource to be deployed to Azure
Copy-Item "..\Source\BakeryWebsite" $contentInstallPath -Recurse

#region Publish the VM DSC configuration
# Typically, what you would do is just zip up the contents of the package and place it immediately into Storage. In 
# our case, we need to build a zip file that contains our web Source code. 
Publish-AzureVMDscConfiguration $configurationScript -ConfigurationArchivePath $configurationArchive -Force -Verbose

Publish-AzureVMDscConfiguration $configurationArchive -Force -Verbose

#endregion

#region Initialize arguments for Set-AzureVMDscExtension


$configurationArgument = @{
    websiteSourceLocation = $websiteSourceLocation;
}

$configurationDataPath = Join-Path $currentDirectory "ConfigurationData.psd1"

# Arguments for Set-AzureVMDscExtension
$arguments = @{
    Version = $dscExtensionVersion;
    StorageContext = $storageContext;
    ConfigurationArchive = $configurationArchive;
    ConfigurationName = $configurationName;
    ConfigurationArgument = $configurationArgument
    ConfigurationDataPath = $configurationDataPath
}

#endregion


#region Apply the Extension to the VM
# Get the instance of the VM
$vm = Get-AzureVM -ServiceName $vmServiceName -Name $vmName -ErrorAction SilentlyContinue

if ($vm)
{
    # VM already exists, so apply the configuration using the Extension
    $vm | Set-AzureVMDSCExtension @arguments -Verbose | Update-AzureVM 
}
else
{
    # VM does not exist. Initialize the provisioning config
    $vm2012R2images = Get-AzureVMImage | Where-Object {$_.ImageName -match "2012-R2"}
    $vm = New-AzureVMConfig -Name $vmName -InstanceSize Small -ImageName $vm2012R2images[0].ImageName | Add-AzureEndpoint –Name ‘web’ –PublicPort 80 –LocalPort 80 –Protocol tcp
    Add-AzureProvisioningConfig -Windows -Password $password -AdminUsername $userName -VM $vm
        
    # Set the DSC Extension properties on the VM object, Create a new VM
    $vm | Set-AzureVMDSCExtension @arguments -Verbose | New-AzureVM -Location "East US" -ServiceName $vmServiceName -WaitForBoot
}

#Now that the script has completed, remove the Bakery website from the DSC resources directory
Remove-Item (Join-Path $contentInstallPath "\BakeryWebsite") –Recurse

#endregion
