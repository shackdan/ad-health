Register-ADHealthCheck @{ Id = 'StaleComputer'; Name = 'Stale enabled computers'; Category = 'Computers'; Severity = 'Medium'; Requires = @('Computers') }

function Test-StaleComputer {
    # Stale = logon AND machine password both older than StaleDays. A missing
    # date counts as stale only if the object was created more than StaleDays ago.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'StaleComputer'
    foreach ($computer in $Data.Computers) {
        if (-not $computer.Enabled) { continue }
        $createdAge = Get-ADHealthAge -Date $computer.WhenCreated -Reference $Data.CollectedAt
        $createdStale = $null -ne $createdAge -and $createdAge -gt $Config.StaleDays

        $logonAge = Get-ADHealthAge -Date $computer.LastLogon -Reference $Data.CollectedAt
        if ($null -ne $logonAge) { $logonStale = $logonAge -gt $Config.StaleDays } else { $logonStale = $createdStale }

        $passwordAge = Get-ADHealthAge -Date $computer.PasswordLastSet -Reference $Data.CollectedAt
        if ($null -ne $passwordAge) { $passwordStale = $passwordAge -gt $Config.StaleDays } else { $passwordStale = $createdStale }

        if (-not ($logonStale -and $passwordStale)) { continue }

        if ($null -ne $logonAge) { $logonText = "$logonAge days ago" } else { $logonText = 'never' }
        if ($null -ne $passwordAge) { $passwordText = "set $passwordAge days ago" } else { $passwordText = 'never set' }
        New-ADHealthFinding -Check $check -ObjectName $computer.Name -DistinguishedName $computer.DistinguishedName `
            -Detail "Last logon $logonText; password $passwordText"
    }
}
