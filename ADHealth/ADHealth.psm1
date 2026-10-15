# Checks register themselves into this list when their file is dot-sourced.
$script:CheckRegistry = New-Object 'System.Collections.Generic.List[hashtable]'

# Private first: Checks/ call Register-ADHealthCheck at load time.
foreach ($folder in 'Private', 'Private/Checks', 'Private/Render', 'Public') {
    $path = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path -LiteralPath $path)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File | Sort-Object Name) {
        . $file.FullName
    }
}

Export-ModuleMember -Function 'Invoke-ADHealthReport'
