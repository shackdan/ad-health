function Get-ADHealthAge {
    [CmdletBinding()]
    param(
        [AllowNull()][Nullable[datetime]]$Date,
        [Parameter(Mandatory)][datetime]$Reference
    )
    if ($null -eq $Date) { return $null }
    ($Reference - $Date).Days
}

function Get-ADHealthRid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Sid
    )
    [int]($Sid.Split('-')[-1])
}

function Test-ADHealthBuiltinAccount {
    # Guest (501), krbtgt (502), DefaultAccount (503), WDAGUtilityAccount (504).
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Sid,
        [Parameter(Mandatory)][string]$DomainSid
    )
    if (-not $Sid) { return $false }
    foreach ($rid in 501, 502, 503, 504) {
        if ($Sid -eq "$DomainSid-$rid") { return $true }
    }
    $false
}

function Select-ADHealthUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [switch]$Disabled
    )
    foreach ($user in $Data.Users) {
        if ([bool]$user.Enabled -eq [bool]$Disabled) { continue }
        if (Test-ADHealthBuiltinAccount -Sid $user.Sid -DomainSid $Data.Domain.DomainSid) { continue }
        $user
    }
}
