function Assert-ADHealthPrerequisite {
    [CmdletBinding()]
    param()
    if (Get-Module -Name ActiveDirectory) { return }
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw ('The ActiveDirectory PowerShell module was not found. Install RSAT: on Windows 10/11 run ' +
            '"Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"; ' +
            'on Windows Server run "Install-WindowsFeature RSAT-AD-PowerShell".')
    }
    # Skip mounting the AD: drive; it slows import and is not needed.
    $env:ADPS_LoadDefaultDrive = 0
    Import-Module ActiveDirectory -ErrorAction Stop -Verbose:$false
}

function Resolve-ADHealthOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    try {
        if (-not (Test-Path -LiteralPath $full -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $full -Force -ErrorAction Stop
        }
        $probe = Join-Path $full ".adhealth-write-test-$([guid]::NewGuid().ToString('N')).tmp"
        [System.IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
    }
    catch {
        throw "Output path '$full' is not writable: $($_.Exception.Message)"
    }
    $full
}
