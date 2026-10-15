Register-ADHealthCheck @{ Id = 'GroupOnlyDisabledMembers'; Name = 'Groups with only disabled members'; Category = 'Groups'; Severity = 'Low'; Requires = @('Groups', 'Users', 'Computers') }

function Test-GroupOnlyDisabledMembers {
    # Members that are not collected users/computers (nested groups, contacts,
    # objects outside the search base) are ignored.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'GroupOnlyDisabledMembers'
    $enabledByDn = @{}  # PowerShell hashtables are case-insensitive
    foreach ($object in @($Data.Users) + @($Data.Computers)) {
        if ($object) { $enabledByDn[$object.DistinguishedName] = [bool]$object.Enabled }
    }
    foreach ($group in $Data.Groups) {
        $resolved = @(
            foreach ($memberDn in @($group.Members | Where-Object { $_ })) {
                if ($enabledByDn.ContainsKey($memberDn)) { $enabledByDn[$memberDn] }
            }
        )
        if ($resolved.Count -eq 0) { continue }
        if ($resolved -contains $true) { continue }
        New-ADHealthFinding -Check $check -ObjectName $group.Name -DistinguishedName $group.DistinguishedName `
            -Detail "All $($resolved.Count) user/computer member(s) disabled"
    }
}
