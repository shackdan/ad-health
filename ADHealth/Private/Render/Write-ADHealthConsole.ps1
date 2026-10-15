function Write-ADHealthConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [string[]]$OutputFiles = @()
    )
    $colors = @{ High = 'Red'; Medium = 'Yellow'; Low = 'Cyan'; Info = 'Gray' }
    $rowFormat = '{0,-34} {1,-8} {2,7}'

    Write-Host ''
    Write-Host "AD Health Report - $($Data.Domain.DnsRoot)" -ForegroundColor White
    Write-Host "DC: $($Data.Server)   Collected: $($Data.CollectedAt.ToString('yyyy-MM-dd HH:mm'))"
    Write-Host ('Objects: {0} users, {1} computers, {2} groups, {3} OUs, {4} GPOs' -f
        (Get-ADHealthCountText -Items $Data.Users), (Get-ADHealthCountText -Items $Data.Computers),
        (Get-ADHealthCountText -Items $Data.Groups), (Get-ADHealthCountText -Items $Data.OUs),
        (Get-ADHealthCountText -Items $Data.Gpos))
    Write-Host ''
    Write-Host ($rowFormat -f 'Check', 'Severity', 'Count')
    Write-Host ($rowFormat -f ('-' * 34), ('-' * 8), ('-' * 7))

    foreach ($row in (Format-ADHealthSummary -Results $Results)) {
        if ($row.Status -eq 'Skipped') { $color = 'DarkGray' } else { $color = $colors[$row.Severity] }
        Write-Host ($rowFormat -f $row.Check, $row.Severity, $row.Display) -ForegroundColor $color
    }

    $skipped = @($Results | Where-Object { $_.Status -eq 'Skipped' })
    if ($skipped.Count -gt 0) {
        Write-Host ''
        foreach ($result in $skipped) {
            Write-Host "Skipped $($result.CheckName): $($result.Reason)" -ForegroundColor DarkGray
        }
    }

    if ($Data.Errors.Count -gt 0) {
        Write-Host ''
        foreach ($key in ($Data.Errors.Keys | Sort-Object)) {
            Write-Host "Collection error ($key): $($Data.Errors[$key])" -ForegroundColor Yellow
        }
    }

    if ($OutputFiles.Count -gt 0) {
        Write-Host ''
        foreach ($file in $OutputFiles) {
            Write-Host "Written: $file" -ForegroundColor Green
        }
    }
}
