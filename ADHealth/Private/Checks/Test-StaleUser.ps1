Register-ADHealthCheck @{ Id = 'StaleUser'; Name = 'Stale enabled users'; Category = 'Users'; Severity = 'Medium'; Requires = @('Users') }

function Test-StaleUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'StaleUser'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        $age = Get-ADHealthAge -Date $user.LastLogon -Reference $Data.CollectedAt
        if ($null -ne $age -and $age -gt $Config.StaleDays) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail "Last logon $age days ago"
        }
    }
}
