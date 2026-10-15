Register-ADHealthCheck @{ Id = 'PasswordNotRequired'; Name = 'Password not required'; Category = 'Users'; Severity = 'High'; Requires = @('Users') }

function Test-PasswordNotRequired {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $passwdNotReqd = 0x20
    $check = Get-ADHealthCheck -Id 'PasswordNotRequired'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        if ($user.UserAccountControl -band $passwdNotReqd) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail 'Password not required flag set'
        }
    }
}
