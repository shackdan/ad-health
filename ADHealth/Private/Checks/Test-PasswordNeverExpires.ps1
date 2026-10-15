Register-ADHealthCheck @{ Id = 'PasswordNeverExpires'; Name = 'Password never expires'; Category = 'Users'; Severity = 'Medium'; Requires = @('Users') }

function Test-PasswordNeverExpires {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'PasswordNeverExpires'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        if ($user.PasswordNeverExpires) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail 'Password set to never expire'
        }
    }
}
