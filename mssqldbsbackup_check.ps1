# SHELL ARGUMENTS
Set-Variable OK 0 -option Constant
Set-Variable WARNING 1 -option Constant
Set-Variable CRITICAL 2 -option Constant
Set-Variable UNKNOWN 3 -option Constant

# ASK STATUS

$nagiosFile = "C:\nagios_sql_backup.log"
$backupLog = "C:\backup.log"
$status = Get-Content -Path $nagiosFile
$modified = (Get-Item $nagiosFile).LastWriteTime
$prettyDate = $modified.ToString("yyyy-MM-dd_HH:MM:ss")

# NAGIOS OUTPUT

if ($status -eq "OK" -and (Get-Date).AddDays(-1) -lt $modified)
{
	$status_str= 'DB BACKUP OK - LAST BACKUP: ' + $prettyDate
    $exit_code = $OK
}
elseif ($status -eq "OK" -and (Get-Date).AddDays(-1) -gt $modified)
{
    $status_str= 'DB BACKUP LATE - LAST BACKUP ' + $prettyDate
    $exit_code = $WARNING
}
elseif ($status -eq "ERROR")
{
	$errorLine = Get-Content $backupLog -Tail 1
    $status_str= 'DB BACKUP FAILED - ' + $errorLine
    $exit_code = $CRITICAL
}
else
{
	$status_str='STATUS UNKNOWN'
	$exit_code = $UNKNOWN
}

Write-Host $status_str
exit $exit_code
