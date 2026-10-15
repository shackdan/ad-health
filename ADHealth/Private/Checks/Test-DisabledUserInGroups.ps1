Register-ADHealthCheck @{ Id = 'DisabledUserInGroups'; Name = 'Disabled users in groups'; Category = 'Users'; Severity = 'Low'; Requires = @('Users') }

function Test-DisabledUserInGroups {
    # MemberOf never includes the primary group, so it is ignored naturally.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'DisabledUserInGroups'
    foreach ($user in (Select-ADHealthUser -Data $Data -Disabled)) {
        $groups = @($user.MemberOf | Where-Object { $_ })
        if ($groups.Count -eq 0) { continue }
        $names = @($groups | Select-Object -First 3 | ForEach-Object { Get-ADHealthDnName -DistinguishedName $_ })
        $detail = "Member of $($groups.Count) group(s): $($names -join ', ')"
        if ($groups.Count -gt 3) { $detail += '...' }
        New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName -Detail $detail
    }
}
