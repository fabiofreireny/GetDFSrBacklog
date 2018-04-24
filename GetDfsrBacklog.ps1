<#
.SYNOPSIS
Retrieves backlog for every DFS replication

.DESCRIPTION
This script will retrieve all DFS replications and list out:
- Groups
- Folders (assumes same name on both ends)
- Source and destination computers
- Current backlog

A backlog of -1 means the script was unable to determine the actual backlog.

.EXAMPLE
.\GetDFSrBacklog.ps1 -HTMLFilePath "c:\inetpub\wwwroot\dfsStatus\index.html" -logFilePath "d:\logs\dfsr-((get-date).toString('yyyy-MM-dd')).log" -Verbose

.LINK
https://github.com/fabiofreireny/GetDFSrBacklog
#>

Param(
    [Parameter(Mandatory=$False,HelpMessage="path of HTML file")]
    [string]$HTMLFilePath,

    [Parameter(Mandatory=$False,HelpMessage="path of Log file")]
    [string]$logFilePath
)

#initialie variables
$today     = (get-date).toString('yyyy-MM-dd')
$grandResult = @()

#get all DFSr connections
$connections = (Get-DfsrConnection | ? Enabled -eq $true | sort -Property GroupName)

$connections | % {
    $connection = $_
    #this is necessary to capture the "verbose" output, which gives is the actual backlog when it is > 100
    try {
        $message = $($backLog = (Get-DfsrBacklog -GroupName $connection.GroupName -SourceComputerName $connection.SourceComputerName `
            -DestinationComputerName $connection.DestinationComputerName -Verbose -ErrorAction stop)) 4>&1
    } catch {
        $message = "Error"
        $backlog = -1
    }

    #message contains one line per replicated folder
    $message | % {

        #figure out actual backlog from verbose output
        if ($_ -like "*No backlog*") {
            $backLogCount = [int]0
        } elseif ($backlog -eq -1) {
            $backLogCount = [int]-1
        } else {
            $backLogCount = [int]($_ -split(" "))[-1]
        }

        $result =  [ordered]@{
            "Group"       = $connection.GroupName
            "Folder"      = ($_ -split("`""))[1]
            "Source"      = $connection.SourceComputerName
            "Destination" = $connection.DestinationComputerName
            "Backlog"     = $backLogCount
            "Details"     = $_
        }

        $grandResult += (New-Object PSObject -Property $result)
    }
}

#send to HTML file
if ($HTMLFilePath) {
    #META tag is what causes auto refresh. Take it out if you don't want it
    #Adjust STYLE as desired
    $grandResult | ConvertTo-Html -Head '<meta http-equiv="refresh" content="5"><style>table, th, td {border: 1px solid black;}th{text-align:left;}th,td{padding:2px;}</style>' `
        -property Group, Folder, Source, Destination, Backlog -PostContent ("<p>DFS Status as of " + (get-date)) > $HTMLFilePath
}

#send to log file
if ($logFilePath) {
    $today                      | Out-File $logFilePath -Append
    $grandResult | ft -AutoSize | Out-File $logFilePath -Append -Width 999
}

#send to screen
$grandResult
