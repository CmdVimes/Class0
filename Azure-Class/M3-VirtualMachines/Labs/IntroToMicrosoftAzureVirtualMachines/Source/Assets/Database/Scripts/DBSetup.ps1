#You will need to make sure you install the PowerShell extensions for SQL Server from http://sqlpsx.codeplex.com/
Import-Module SqlServer

#Create a timer that will be used for waiting until the SQL instance has stopped and started
$hrs = 0
$min = 0
$sec = 30
$timeout = New-Object System.TimeSpan -ArgumentList $hrs,$min,$sec

Set-ExecutionPolicy RemoteSigned

#If you name your server something different, change it here
$serverName = "."
$loginName = "CloudShop"
$dbUserName = "CloudShop"
$databaseName = "AdventureWorks2012"
$roleName = "db_owner"
$password = "Azure$123"
$scvmSQL = new-object System.Collections.Specialized.StringCollection

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
$instance = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $serverName

#Change the instance to mixed mode
$instance.Settings.LoginMode = [Microsoft.SqlServer.Management.SMO.ServerLoginMode]::Mixed
$instance.Alter()

$sql_service = "MSSQLSERVER"
$service = Get-Service -Name $sql_service
Write-Output "Service status is: $service.Status"

#Set the appropriate directories for data, log, backup
$instance.BackupDirectory = "F:\Backup"
$instance.DefaultFile = "F:\Data"
$instance.DefaultLog = "F:\Logs"
$instance.Alter()

#Need to restart the service to pick up changes
$service.Stop()
$service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,$timeout)
'Service status after Stop request is: ' + $service.Status
$service.Start()

$service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running,$timeout)
'Service status after Start request is: ' + $service.Status

#Attach the database - manual at the current time
$sc = new-object System.Collections.Specialized.StringCollection
$sc.Add("F:\Data\AdventureWorks2012_Data.mdf")
$sc.Add("F:\Data\AdventureWorks2012_log.ldf")
$instance.AttachDatabase($databaseName,$sc)
#$error[0] | fl -force

#check to make sure that CloudShop login does not exist, if it does, remove it 
#$login = Get-SqlLogin -sqlserver $serverName | where{$_.Name -eq $loginName}
#if($login -ne $null)
#{
#   #$dbs = Get-SqlDatabase -sqlserver $serverName -dbname $databaseName -force
#  $dbs = Get-SqlDatabase -sqlserver $serverName -force
#  foreach($db in $dbs)
#{
#    $logins = $db.EnumLoginMappings();
#    foreach($dbLogin in $logins)
#    {   
#        #Write-Host $dbLogin.LoginName
#        if($dbLogin.LoginName -eq $loginName)
#        {
#            Remove-SqlUser -dbname $db.Name -sqlserver $srv -name $dbLogin.LoginName
#        }
#    }
#}
#
#   #Remove-SqlUser -dbname $dbs.Name -sqlserver $serverName -name $loginName
#   Remove-SqlLogin -sqlserver $serverName -name $loginName
#}


#Create the new login
$myLogin = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $instance, $loginName
$myLogin.PasswordPolicyEnforced = $false
$myLogin.LoginType = 'SqlLogin'
$myLogin.DefaultDatabase = $databaseName
$myLogin.Create('Azure$123')
'Login has been created for: ' + $loginName

$NewUser = New-Object Microsoft.SqlServer.Management.Smo.User($instance.Databases[$databaseName], $dbUserName)
$NewUser.Login = $loginName
$NewUser.Create()
'User ' + $dbUserName + ' has been added to the database'

$NewUser.AddToRole($roleName)
'Role ' + $roleName + ' has been added to the database'

