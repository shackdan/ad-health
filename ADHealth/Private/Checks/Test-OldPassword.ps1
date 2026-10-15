Register-ADHealthCheck @{ Id = 'OldPassword'; Name = 'Old passwords'; Category = 'Users'; Severity = 'Low'; Requires = @('Users') }

function Test-OldPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'OldPassword'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        if ($user.PasswordNeverExpires) { continue }
        $age = Get-ADHealthAge -Date $user.PasswordLastSet -Reference $Data.CollectedAt
        if ($null -ne $age -and $age -gt $Config.PasswordAgeDays) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail "Password last set $age days ago"
        }
    }
}
