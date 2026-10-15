Register-ADHealthCheck @{ Id = 'NeverLoggedOnUser'; Name = 'Never-logged-on users'; Category = 'Users'; Severity = 'Medium'; Requires = @('Users') }

function Test-NeverLoggedOnUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'NeverLoggedOnUser'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        if ($null -ne $user.LastLogon) { continue }
        $age = Get-ADHealthAge -Date $user.WhenCreated -Reference $Data.CollectedAt
        if ($null -ne $age -and $age -gt $Config.NeverLoggedOnGraceDays) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail "Never logged on; created $age days ago"
        }
    }
}
