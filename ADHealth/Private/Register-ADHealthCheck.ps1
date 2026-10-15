function Register-ADHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][hashtable]$Definition
    )
    foreach ($key in 'Id', 'Name', 'Category', 'Severity', 'Requires') {
        if (-not $Definition.ContainsKey($key)) {
            throw "Check definition is missing required key '$key'."
        }
    }
    if ($Definition.Severity -notin 'High', 'Medium', 'Low', 'Info') {
        throw "Check '$($Definition.Id)' has invalid severity '$($Definition.Severity)'."
    }
    foreach ($existing in $script:CheckRegistry) {
        if ($existing.Id -eq $Definition.Id) {
            throw "Check '$($Definition.Id)' is already registered."
        }
    }
    $script:CheckRegistry.Add($Definition)
}
