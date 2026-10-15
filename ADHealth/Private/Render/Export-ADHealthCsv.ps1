function Export-ADHealthCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Prefix
    )
    foreach ($result in $Results) {
        $findings = @($result.Findings)
        if ($result.Status -ne 'Ran' -or $findings.Count -eq 0) { continue }
        $path = Join-Path $Directory "$($Prefix)_$($result.CheckId).csv"
        $findings |
            Select-Object CheckId, CheckName, Category, Severity, ObjectName, DistinguishedName, Detail |
            Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
        $path
    }
}
