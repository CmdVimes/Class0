$svc ="[The name of the pre-existing Cloud Service]"
$storage = "[The name of the pre-existing storage account]"
$net = "[The name of the pre-existing virtual network]"
$subnet = "[The name of the pre-existing virtual network subnet]"
$subscription = "[The name of your subscription]"

$vm = "vmAD1"
$adm = "labadmin"
$pwd = 'Pa$$w0rd!'
$nbtDomain = "CONTOSO"
$domain = "contoso.com"
$size = "Medium"
$secPwd = (ConvertTo-SecureString $pwd -AsPlainText -Force)
$vmCreds = new-object pscredential($adm, $secPwd)
$dirsyncSource = "https://go.microsoft.com/fwLink/?LinkID=278924"
$dirsyncTarget = "F:\dirsync.exe"
$session = $null
$sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck

Import-Module -Name "C:\Program Files (x86)\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1"

Write-Host "Setting Storage Account."
Set-AzureSubscription -SubscriptionName $subscription -CurrentStorageAccountName $storage
Select-AzureSubscription -SubscriptionName $subscription

#$subscription = Get-AzureSubscription -Current | select -ExpandProperty SubscriptionName
#Set-AzureSubscription -SubscriptionName $subscription -CurrentStorageAccountName $storage
#Select-AzureSubscription -SubscriptionName $subscription
Write-Host "Getting proper image for Virtual Machine."
$img = (Get-AzureVMImage | where ImageFamily -eq "Windows Server 2012 R2 Datacenter" | Sort-Object PublishedDate -Descending)[0].ImageName

Write-Host "Creating new Virtual Machine and waiting for boot."
New-AzureVMConfig -Name $vm -InstanceSize $size -ImageName $img | 
 Add-AzureProvisioningConfig -AdminUserName $adm -Windows -Password $pwd | 
 Set-AzureSubnet -SubnetNames $subnet |
 Add-AzureDataDisk -CreateNew -HostCaching None -DiskLabel 'NTDS' -DiskSizeInGB 10 -LUN 0 | New-AzureVM -ServiceName $svc -VNetName $net -WaitForBoot

Write-Host "Establishing remote session to new Virtual Machine."
$uri = Get-AzureWinRMUri -ServiceName $svc -Name $vm
$session = New-PSSession -ErrorAction SilentlyContinue -SessionOption $sessionOption -ComputerName $uri.DnsSafeHost -Credential $vmCreds -Port $uri.Port -UseSSL

Write-Host "Promoting the Virtual Machine to Domain Controller."
Invoke-Command -Session $session -ScriptBlock {
    param($domain, $nbtDomain, $secPwd)
    Write-Host "   Initializing and formatting raw disk."
    Get-Disk | 
        Where PartitionStyle -eq 'raw' |
        Initialize-Disk -PartitionStyle MBR -PassThru |
        New-Partition -UseMaximumSize -DriveLetter F |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel 'NTDS' -Confirm:$false -Force 
    Write-Host "   Installing AD Domain Services."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Write-Host "   Creating new AD Forest."
    Import-Module ADDSDeployment
    Install-ADDSForest `
        -CreateDnsDelegation:$false `
        -DatabasePath "F:\NTDS" `
        -DomainMode "Win2012R2" `
        -DomainName $domain `
        -DomainNetbiosName $nbtDomain `
        -ForestMode "Win2012R2" `
        -SafeModeAdministratorPassword $secPwd `
        -InstallDns:$true `
        -LogPath "F:\NTDS" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "F:\SYSVOL" `
        -Force:$true `
        -WarningAction SilentlyContinue
} -ArgumentList @($domain, $nbtDomain, $secPwd)
Write-Host "Machine will now be rebooted."

Remove-PSSession $session
$session = $null

Write-Host "Importing CSV files for user import."
$ous = Import-CSV .\OUs.csv 
$users = Import-CSV .\Users.csv
$groups = Import-CSV .\Groups.csv
$members = Import-CSV .\Members.csv 

Write-Host "Trying to re-establish the PowerShell session to the Domain Controller."
do {
    $session = New-PSSession -ErrorAction SilentlyContinue -SessionOption $sessionOption -ComputerName $uri.DnsSafeHost -Credential $vmCreds -Port $uri.Port -UseSSL
    if ($session -eq $null) {
        Write-Warning "Unable to establish a PowerShell session. Retry in 15 seconds..."
        Start-Sleep -Seconds 15
    }
} until ($session -ne $null)

Write-Host "Installing requirements for DirSync and downloading DirSync."
Invoke-Command -Session $session -ScriptBlock {
    param($dirsyncSource, $dirsyncTarget)
    Write-Host "   Installing .NET 3.5 features."
    Install-WindowsFeature -Name Net-Framework-Core
    Write-Host "   Downloading DirSync."
    Invoke-WebRequest -Uri $dirsyncSource -OutFile $dirsyncTarget
} -ArgumentList @($dirsyncSource, $dirsyncTarget)

Write-Host "Creating Users, Groups and Organizational Units. (Be patient!)"
Invoke-Command -Session $session -ScriptBlock {
    param($ous, $users, $groups, $members)
    Write-Host "   Importing Organizational Units..."
    $ous | New-ADOrganizationalUnit
    Write-Host "   Importing Users..."
    Foreach ($user in $users) {
	    New-ADUser -GivenName $user.GivenName -Surname $user.Surname -Initials $user.Initials -DisplayName $user.DisplayName -Name $user.Name -SamAccountName $user.SamAccountName -UserPrincipalName $user.UserPrincipalName -AccountPassword (ConvertTo-SecureString $user.AccountPassword -AsPlainText -Force) -PasswordNeverExpires $True -ChangePasswordAtLogon $False -Enabled $True -Path $user.Path
    }
    Write-Host "   Importing Groups..."
    $groups | New-ADGroup
    Write-Host "   Adding Users to Groups..."
    Foreach ($member in $members) {
	    Add-ADGroupMember -Identity $member.Identity -Members (Get-ADUser $member.Members)
    }
} -ArgumentList @($ous, $users, $groups, $members)
Write-Host "Done!"