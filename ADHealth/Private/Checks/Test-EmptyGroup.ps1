Register-ADHealthCheck @{ Id = 'EmptyGroup'; Name = 'Empty groups'; Category = 'Groups'; Severity = 'Info'; Requires = @('Groups', 'Users', 'Computers') }

function Test-EmptyGroup {
    # A group's 'member' attribute omits objects that use it as their primary
    # group, so groups referenced by any primaryGroupID are not reported.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'EmptyGroup'
    $primaryGroupRids = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($object in @($Data.Users) + @($Data.Computers)) {
        if ($object) { [void]$primaryGroupRids.Add([int]$object.PrimaryGroupId) }
    }
    foreach ($group in $Data.Groups) {
        if (@($group.Members | Where-Object { $_ }).Count -gt 0) { continue }
        if ($group.IsCriticalSystemObject) { continue }
        if ($group.DistinguishedName -match '(^|,)CN=Builtin,') { continue }
        if ($group.Sid -and $primaryGroupRids.Contains((Get-ADHealthRid -Sid $group.Sid))) { continue }
        New-ADHealthFinding -Check $check -ObjectName $group.Name -DistinguishedName $group.DistinguishedName `
            -Detail 'Group has no members'
    }
}
