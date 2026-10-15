function ConvertFrom-ADHealthFileTime {
    # lastLogonTimestamp / pwdLastSet: 0 and Int64.MaxValue both mean "never".
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    $ticks = [int64]$Value
    if ($ticks -le 0 -or $ticks -eq [int64]::MaxValue) { return $null }
    [datetime]::FromFileTime($ticks)
}
