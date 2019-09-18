param(
    $backupDirectory = "J:\backup_passthrough",
	$shareDirectory = "\\10.5.220.10\SQLBACKUPSHARE",
	$logDirectory = "J:\backup_passthrough\logs\backup.log",
	$nagiosCheckFile = "J:\backup_passthrough\logs\nagios_sql_backup.log"
)

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null

$server = New-Object ("Microsoft.SqlServer.Management.Smo.Server")
$dbs = $server.Databases
$global:targetDirectory = $null
$global:BackupFile = $null
$global:logDir = $logDirectory
$global:errorStatus = 0

Function dbBackup($backupDir)
{
    foreach ($database in $dbs | where { $_.IsSystemObject -eq $False })
    {
        $dbName = $database.Name
        #$dbName = "DIAGNOSTICLOG"

        $timestamp = Get-Date -format yyyy-MM-dd
		$global:targetDirectory = $backupDir + "\" + $timestamp
		md -Force $targetDirectory | Out-Null
        $targetPath = $targetDirectory + "\" + $dbName + "_" + $timestamp + ".bak"

		$startDate = Get-Date -format yyyy-MM-dd_HH:mm:ss
		"[$startDate] -- OK -- Started backup of $dbName on $server to $targetPath" | Tee-Object -FilePath $global:LogDir -Append
        $smoBackup = New-Object ("Microsoft.SqlServer.Management.Smo.Backup")
        $smoBackup.Action = "Database"
        $smoBackup.BackupSetDescription = "Full Backup of " + $dbName
        $smoBackup.BackupSetName = $dbName + " Backup"
        $smoBackup.Database = $dbName
        $smoBackup.MediaDescription = "Disk"
        $smoBackup.Devices.AddDevice($targetPath, "File")
		
		$percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                   Write-Progress -id 1 -activity "Backing up database $dbName to $targetPath " -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
        }
        $smoBackup.add_PercentComplete($percent)
        $smoBackup.add_Complete($complete)
        Try
        {
            $smoBackup.SqlBackup($server)
			$backupStatus = $?
            Write-Progress -id 1 -activity "Backing up database $dbName to $targetPath " -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))            
        }
        Catch
        {
            Write-Output $_.Exception.InnerException
        } 
		
        $endDate = Get-Date -format yyyy-MM-dd_HH:mm:ss

        if ($backupStatus) {
            "[$endDate] -- OK -- Finished backing up $dbName on $server to $targetPath" | Tee-Object -FilePath $global:LogDir -Append
        }
        else {
            "[$endDate] -- ERROR -- Failed to backup $dbName on $server to $targetPath" | Tee-Object -FilePath $global:LogDir -Append
			$global:errorStatus = 1
            }
    }
}

Function addTo7z($backupDir)
{
    if (-not (test-path "$env:ProgramFiles\7-Zip\7z.exe")) {throw "$env:ProgramFiles\7-Zip\7z.exe needed"}
    set-alias sz "$env:ProgramFiles\7-Zip\7z.exe"
	$source = $backupDir
	$global:BackupFile = $backupDir + ".7z"
	$startDate = Get-Date -format yyyy-MM-dd_HH:mm:ss
	"[$startDate] -- OK -- Started 7z archiving of $backupDir to $global:BackupFile" | Tee-Object -FilePath $global:LogDir -Append
	sz a -t7z -mmt16 $global:BackupFile $source
	$status = $?
	$endDate = Get-Date -format yyyy-MM-dd_HH:mm:ss
	if ( -not $status ) {
	$global:errorStatus = 1
	"[$endDate] -- ERROR -- Error while compressing with 7z" | Tee-Object -FilePath $global:LogDir -Append
	}
	else {
		"[$endDate] -- OK -- Finished 7z archiving of $global:BackupFile" | Tee-Object -FilePath $global:LogDir -Append
	}
}

Function cleanUp()
{
	$startDate = Get-Date -format yyyy-MM-dd_HH:mm:ss
	"[$startDate] -- OK -- Started removing $global:targetDirectory" | Tee-Object -FilePath $global:LogDir -Append
	Remove-Item -LiteralPath $global:targetDirectory -Force -Recurse
	$status = $?
	$endDate = Get-Date -format yyyy-MM-dd_HH:mm:ss
	if ( -not $status ) {
	$global:errorStatus = 1
	"[$endDate] -- ERROR -- Error while removing $global:targetDirectory" | Tee-Object -FilePath $global:LogDir -Append
	}
	else {
		"[$endDate] -- OK -- Finished removing $global:targetDirectory" | Tee-Object -FilePath $global:LogDir -Append
	}
}

Function moveToShare($shareDir)
{
	$startDate = Get-Date -format yyyy-MM-dd_HH:mm:ss
	"[$startDate] -- OK -- Started moving $global:BackupFile to $shareDir" | Tee-Object -FilePath $global:LogDir -Append
	Move-Item -Path $global:BackupFile -Destination $shareDir
	$status = $?
	$endDate = Get-Date -format yyyy-MM-dd_HH:mm:ss
	if ( -not $status ) {
	$global:errorStatus = 1
	"[$endDate] -- ERROR -- Error while moving $global:BackupFile to $shareDir" | Tee-Object -FilePath $global:LogDir -Append
	}
	else {
		"[$endDate] -- OK -- Finished moving $global:BackupFile to $shareDir" | Tee-Object -FilePath $global:LogDir -Append
	}
}

# Assume everything will go as planned
echo "OK" | Out-File $nagiosCheckFile
# Take backups of all databases to $backupDirectory
dbBackup -backupDir $backupDirectory
if ( $global:errorStatus ) {
	echo "ERROR" | Out-File $nagiosCheckFile
	Exit
	}
# Add $backupDirectory to timestamped 7z file
addTo7z $global:targetDirectory
if ( $global:errorStatus ) {
	echo "ERROR" | Out-File $nagiosCheckFile
	Exit
	}
# Delete $backupDirectory
cleanUp
if ( $global:errorStatus ) {
	echo "ERROR" | Out-File $nagiosCheckFile
	Exit
	}
# Move archived 7z file to $shareDirectory
moveToShare $shareDirectory
if ( $global:errorStatus ) {
	echo "ERROR" | Out-File $nagiosCheckFile
	Exit
	}
