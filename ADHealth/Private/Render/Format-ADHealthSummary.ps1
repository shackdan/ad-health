function Sort-ADHealthResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results
    )
    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $Results | Sort-Object @{ Expression = { $rank[$_.Severity] } }, @{ Expression = { $_.CheckName } }
}

function Format-ADHealthSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results
    )
    foreach ($result in (Sort-ADHealthResult -Results $Results)) {
        if ($result.Status -eq 'Ran') {
            $count = @($result.Findings).Count
            $display = [string]$count
        }
        else {
            $count = $null
            $display = 'Skipped'
        }
        [pscustomobject]@{
            CheckId  = $result.CheckId
            Check    = $result.CheckName
            Category = $result.Category
            Severity = $result.Severity
            Status   = $result.Status
            Count    = $count
            Display  = $display
        }
    }
}

function Get-ADHealthCountText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Items
    )
    if ($null -eq $Items) { return 'n/a' }
    [string]@($Items).Count
}
