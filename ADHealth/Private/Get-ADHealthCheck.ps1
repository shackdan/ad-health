function Get-ADHealthCheck {
    [CmdletBinding()]
    param(
        [string]$Id
    )
    if (-not $Id) {
        return $script:CheckRegistry.ToArray()
    }
    foreach ($check in $script:CheckRegistry) {
        if ($check.Id -eq $Id) { return $check }
    }
    throw "No check registered with Id '$Id'."
}
