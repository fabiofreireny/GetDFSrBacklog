Param (
    [string]$outFile
)

#$outFile = "c:\temp\dfsStatus.html"

$today     = (get-date).toString('yyyy-MM-dd') 

$grandResult = @()
$connections = (Get-DfsrConnection | ? Enabled -eq $true | sort -Property GroupName)

$connections | % {
    $connection = $_
    #this is necessary to capture the "verbose" output, which gives is the actual backlog when it is > 100
    try {
        $message = $($backLog = (Get-DfsrBacklog -GroupName $connection.GroupName -SourceComputerName $connection.SourceComputerName -DestinationComputerName $connection.DestinationComputerName -Verbose -ErrorAction stop)) 4>&1
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
if ($outFile) {
    $grandResult | ConvertTo-Html -Head '<meta http-equiv="refresh" content="5"><style>table, th, td {border: 1px solid black;}th{text-align:left;}th,td{padding:2px;}</style>' -property Group, Folder, Source, Destination, Backlog -PostContent ("<p>DFS Status as of " + (get-date)) > $outFile
}

#send to log file
get-date                    | Out-File D:\Scripts\Logs\getDfsrBacklog\backlogHistory-$today.log -Append
$grandResult | ft -AutoSize | Out-File D:\Scripts\Logs\getDfsrBacklog\backlogHistory-$today.log -Append -Width 999

#send to screen
$grandResult | ft -AutoSize
