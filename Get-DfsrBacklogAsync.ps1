<#
.SYNOPSIS
Retrieves backlog for every DFS replication

.DESCRIPTION
This script will retrieve all DFS replications and list out:
- Groups
- Folders (assumes same name on both ends)
- Source and destination computers
- Current backlog

A backlog of -1 means the script was unable to determine the actual backlog (i.e. an error occured).

.EXAMPLE
.\GetDFSrBacklog.ps1 -HTMLFilePath "c:\inetpub\wwwroot\dfsStatus\index.html" -DestinationComputerName "server01|server02" -HasBacklogOnly

.LINK
https://github.com/fabiofreireny/GetDFSrBacklog
#>

Param (
    # Optional name of HTML file (for report)
    [string]$HTMLFilePath,
    # Narrow down to specific host(s) (regex)
    [string]$DestinationComputerName =".",
    # Show progress. Useful for larger environments, or when there is a large backlog
    [switch]$ShowProgress,
    # Don't show result for connections which have no backlog (i.e. backlog = 0)
    [switch]$HasBacklogOnly,
    # Max time job will wait for the result of a specific connection (in mminutes)
    [int]$Timeout = 30
)

$logFolder         = ".\log"
$today             = (get-date).toString('yyyy-MM-dd')
$excludedComputers = @("DFS")
$excludedGroups    = @("excludedGroupName")

$GetBacklog = {
    param (
        [psobject]$Connection
    )

    # In my testing dfsrdiag was more reliable than the powershell get-dfsrbacklog command
    # It's also necessary to do some voodoo to get backlog count over 100 with get-dfsrbacklog
    [string]$message = invoke-command {
        dfsrdiag backlog /sendingmember:$($connection.SourceComputerName) /rgname:$($connection.GroupName) /rfname:$($connection.FolderName) /receivingmember:$($connection.DestinationComputerName)
    }

    $message -match "Member (.*) Backlog File Count: (\d*)" | Out-Null
    if ($matches) {
        #"1"
        $backLogCount = $matches[2]
        $detail = $matches[0]
    } else {
        $message -match "No Backlog - member (.*) is in sync with partner (.*)" | Out-Null
        if ($matches) {
            #"2"
            $backLogCount = 0
            $detail = $matches[0]
        } else {
            $message -match "\[ERROR\] .*" | Out-Null
            if ($matches) {
                #"3"
                $backLogCount = -1
                $detail = $matches[0]
            } else { "Arghh"}
        }
    }

    $result =  [ordered]@{
        "Group"       = $connection.GroupName
        "Folder"      = $connection.FolderName
        "Source"      = $connection.SourceComputerName
        "Destination" = $connection.DestinationComputerName
        "Backlog"     = $backLogCount
        "Details"     = $detail
    }

    $result
}

if ($ShowProgress) { get-date }

$grandResult = @()
$allFolders  = @()

# Get all DFSR connections (source/destination/group)
$connections = (Get-DfsrConnection | ? Enabled -eq $true | sort -Property GroupName) | ? SourceComputerName -NotIn $excludedComputers | ? DestinationComputerName -NotIn $excludedComputers | ? GroupName -NotIn $excludedGroups
# Get all DFSR source/destination/group/folder combinations (a group may have multiple folders)
$connections | % {
    $connection = $_
    $folders = Get-DfsReplicatedFolder -GroupName $_.GroupName
    $folders | % {
        $folder = $_
        $folderObject = [PSCustomObject]@{
            GroupName = $connection.GroupName
            SourceComputerName = $connection.SourceComputerName
            DestinationComputerName = $connection.DestinationComputerName
            FolderName = $folder.FolderName
        }
        $allFolders += $folderObject
    }
}

get-job | remove-job -force
$threshold = 30
$allFolders | where {($_.DestinationComputerName -match $DestinationComputerName)} | % {
    if ($ShowProgress) { "$($_.SourceComputerName), $($_.DestinationComputerName), $($_.FolderName)" }
    start-job -ScriptBlock $getbacklog -ArgumentList $_ | Out-Null
    # Don't overload my system... run at most $threshold threads at a time
    if ((get-job -state Running).count -gt $threshold) {
        do {
            start-sleep -seconds 1
        } until ((get-job -state Running).count -le $threshold)
    }
}

# Wait up to $Timeout minutes
get-job | wait-job -timeout ($Timeout*60) | Out-Null
$TimedOut = get-job | ? State -eq Running
get-job | receive-job  | % {
    # Select is use to specify order of columns
    $result = [pscustomobject]$_ | Select Source, Destination, Group, Folder, Backlog, Details
    if (($result.details -notmatch "Cannot find DfsrReplicatedFolderConfig") -and ($result.details -notmatch "Failed to execute GetOutboundBacklogFileCount method")) {
        $grandResult +=  $result
    }
}

if ($ShowProgress) { get-date }

if ($ShowProgress -and $TimedOut) { "Number of timed out jobs: $($TimedOut.count)" }

if ($HasBacklogOnly) {
    $grandResult = $grandResult | ? Backlog -ne 0
}

#send to HTML file
if ($HTMLFilePath) {
    $grandResult | ConvertTo-Html -Head '<meta http-equiv="refresh" content="5"><style>table, th, td {border: 1px solid black;}th{text-align:left;}th,td{padding:2px;}</style>' -property Group, Folder, Source, Destination, Backlog -PostContent ("<p>DFS Status as of " + (get-date)) > $HTMLFilePath
}

#send to log file
if (!(test-path $logFolder)) { mkdir $logFolder }
get-date     | Out-File $logFolder\backlogHistory-$today.log -Append
$grandResult | Out-File $logFolder\backlogHistory-$today.log -Append -Width 999

#send to screen
$grandResult #| ft -AutoSize
