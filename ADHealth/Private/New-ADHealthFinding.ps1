function New-ADHealthFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Check,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ObjectName,
        [AllowEmptyString()][string]$DistinguishedName = '',
        [Parameter(Mandatory)][string]$Detail
    )
    [pscustomobject]@{
        PSTypeName        = 'ADHealth.Finding'
        CheckId           = $Check.Id
        CheckName         = $Check.Name
        Category          = $Check.Category
        Severity          = $Check.Severity
        ObjectName        = $ObjectName
        DistinguishedName = $DistinguishedName
        Detail            = $Detail
    }
}
