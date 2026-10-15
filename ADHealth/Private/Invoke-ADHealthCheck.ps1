function Resolve-ADHealthCheckSelection {
    [CmdletBinding()]
    param(
        [string[]]$Include,
        [string[]]$Exclude
    )
    $all = @(Get-ADHealthCheck)
    $validIds = @($all | ForEach-Object { $_.Id })
    foreach ($id in @($Include) + @($Exclude)) {
        if ($id -and $validIds -notcontains $id) {
            throw "Unknown check Id '$id'. Valid Ids: $(($validIds | Sort-Object) -join ', ')"
        }
    }
    foreach ($check in $all) {
        if ($Include -and $Include -notcontains $check.Id) { continue }
        if ($Exclude -and $Exclude -contains $check.Id) { continue }
        $check
    }
}

function Invoke-ADHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable[]]$Checks,
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    foreach ($check in $Checks) {
        $status = 'Ran'
        $reason = ''
        $findings = @()
        $missing = @($check.Requires | Where-Object { $null -eq $Data.$_ -or $Data.Errors.ContainsKey($_) })
        if ($missing.Count -gt 0) {
            $status = 'Skipped'
            $reason = "Data not collected: $($missing -join ', ')"
        }
        else {
            try {
                $findings = @(& "Test-$($check.Id)" -Data $Data -Config $Config)
            }
            catch {
                $status = 'Skipped'
                $reason = "Check failed: $($_.Exception.Message)"
                $findings = @()
            }
        }
        [pscustomobject]@{
            PSTypeName = 'ADHealth.CheckResult'
            CheckId    = $check.Id
            CheckName  = $check.Name
            Category   = $check.Category
            Severity   = $check.Severity
            Status     = $status
            Reason     = $reason
            Findings   = $findings
        }
    }
}
