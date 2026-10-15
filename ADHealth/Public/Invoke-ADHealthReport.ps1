function Invoke-ADHealthReport {
    <#
    .SYNOPSIS
    Reports Active Directory object hygiene problems. Read-only.

    .DESCRIPTION
    Reads users, computers, groups, OUs and GPOs from AD in a single pass, runs
    12 hygiene checks, prints a summary to the console and writes an HTML
    report (and optionally one CSV per check with findings).

    .EXAMPLE
    Invoke-ADHealthReport -OutputPath .\reports

    .EXAMPLE
    Invoke-ADHealthReport -SearchBase 'OU=Staff,DC=lab,DC=local' -StaleDays 60 -Csv

    .EXAMPLE
    Invoke-ADHealthReport -Include StaleUser, StaleComputer -NoHtml -PassThru | Format-Table ObjectName, Detail
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SearchBase,
        [pscredential]$Credential,
        [string]$OutputPath = '.',
        [switch]$Csv,
        [switch]$NoHtml,
        [ValidateRange(1, 36500)][int]$StaleDays = 90,
        [ValidateRange(1, 36500)][int]$NeverLoggedOnGraceDays = 30,
        [ValidateRange(1, 36500)][int]$PasswordAgeDays = 365,
        [string[]]$Include,
        [string[]]$Exclude,
        [switch]$PassThru
    )
    Assert-ADHealthPrerequisite
    $checks = @(Resolve-ADHealthCheckSelection -Include $Include -Exclude $Exclude)
    if ($Csv -or -not $NoHtml) {
        $outputDirectory = Resolve-ADHealthOutputPath -Path $OutputPath
    }
    $config = @{
        StaleDays              = $StaleDays
        NeverLoggedOnGraceDays = $NeverLoggedOnGraceDays
        PasswordAgeDays        = $PasswordAgeDays
    }

    $data = Get-ADHealthData -Server $Server -SearchBase $SearchBase -Credential $Credential
    $results = @(Invoke-ADHealthCheck -Checks $checks -Data $data -Config $config)

    $prefix = 'ADHealth_{0}_{1}' -f $data.Domain.DnsRoot, $data.CollectedAt.ToString('yyyyMMdd-HHmm')
    $files = @()
    if (-not $NoHtml) {
        $htmlPath = Join-Path $outputDirectory "$prefix.html"
        Export-ADHealthHtml -Data $data -Results $results -Config $config -Path $htmlPath
        $files += $htmlPath
    }
    if ($Csv) {
        $files += @(Export-ADHealthCsv -Results $results -Directory $outputDirectory -Prefix $prefix)
    }

    Write-ADHealthConsole -Data $data -Results $results -OutputFiles $files

    if ($PassThru) {
        foreach ($result in $results) { $result.Findings }
    }
}
