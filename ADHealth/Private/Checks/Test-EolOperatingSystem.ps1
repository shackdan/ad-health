Register-ADHealthCheck @{ Id = 'EolOperatingSystem'; Name = 'End-of-life operating systems'; Category = 'Computers'; Severity = 'High'; Requires = @('Computers') }

function Test-EolOperatingSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'EolOperatingSystem'
    foreach ($computer in $Data.Computers) {
        if (-not $computer.Enabled -or -not $computer.OperatingSystem) { continue }
        foreach ($pattern in $script:EolOperatingSystemPatterns) {
            if ($computer.OperatingSystem -like $pattern) {
                New-ADHealthFinding -Check $check -ObjectName $computer.Name -DistinguishedName $computer.DistinguishedName `
                    -Detail $computer.OperatingSystem
                break
            }
        }
    }
}
