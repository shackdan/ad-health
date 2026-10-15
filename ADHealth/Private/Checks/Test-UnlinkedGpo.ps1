Register-ADHealthCheck @{ Id = 'UnlinkedGpo'; Name = 'Unlinked GPOs'; Category = 'GPOs'; Severity = 'Low'; Requires = @('Gpos', 'GpLinks') }

function Test-UnlinkedGpo {
    # A disabled link still counts as linked.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'UnlinkedGpo'
    $linked = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($guid in $Data.GpLinks) { [void]$linked.Add($guid) }
    foreach ($gpo in $Data.Gpos) {
        if ($linked.Contains($gpo.Guid)) { continue }
        if ($gpo.DisplayName) { $name = $gpo.DisplayName } else { $name = $gpo.Guid }
        New-ADHealthFinding -Check $check -ObjectName $name -DistinguishedName $gpo.DistinguishedName `
            -Detail "GPO '$name' is not linked anywhere"
    }
}
