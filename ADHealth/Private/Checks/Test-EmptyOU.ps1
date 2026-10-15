Register-ADHealthCheck @{ Id = 'EmptyOU'; Name = 'Empty OUs'; Category = 'OUs'; Severity = 'Info'; Requires = @('OUs', 'AllObjectDNs') }

function Test-EmptyOU {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'EmptyOU'
    $parents = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dn in $Data.AllObjectDNs) {
        $parent = Get-ADHealthDnParent -DistinguishedName $dn
        if ($parent) { [void]$parents.Add($parent) }
    }
    foreach ($ou in $Data.OUs) {
        if ($parents.Contains($ou.DistinguishedName)) { continue }
        New-ADHealthFinding -Check $check -ObjectName $ou.Name -DistinguishedName $ou.DistinguishedName `
            -Detail 'OU contains no objects'
    }
}
