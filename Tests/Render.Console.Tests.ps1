BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force
}

Describe 'Format-ADHealthSummary' {
    It 'orders rows by severity then name and labels skipped checks' {
        $results = @(
            New-FakeResult -Id 'EmptyOU' -Name 'Empty OUs' -Severity 'Info'
            New-FakeResult -Id 'OldPassword' -Name 'Old passwords' -Severity 'Low' -Status 'Skipped' -Reason 'Data not collected: Users'
            New-FakeResult -Id 'PasswordNotRequired' -Name 'Password not required' -Severity 'High' -Findings @((New-FakeFinding), (New-FakeFinding -ObjectName 'bob'))
            New-FakeResult -Id 'StaleUser' -Name 'Stale enabled users' -Severity 'Medium'
            New-FakeResult -Id 'EolOperatingSystem' -Name 'End-of-life operating systems' -Severity 'High'
        )
        $rows = @(Invoke-InModule Format-ADHealthSummary @{ Results = $results })
        @($rows | ForEach-Object { $_.Check }) | Should -Be @(
            'End-of-life operating systems', 'Password not required', 'Stale enabled users', 'Old passwords', 'Empty OUs'
        )
        $rows[0].Display | Should -Be '0'
        $rows[1].Count | Should -Be 2
        $rows[1].Display | Should -Be '2'
        $rows[3].Count | Should -BeNullOrEmpty
        $rows[3].Display | Should -Be 'Skipped'
    }
}

Describe 'Get-ADHealthCountText' {
    It 'returns n/a for null and the count otherwise' {
        Invoke-InModule Get-ADHealthCountText @{ Items = $null } | Should -Be 'n/a'
        Invoke-InModule Get-ADHealthCountText @{ Items = @() } | Should -Be '0'
        Invoke-InModule Get-ADHealthCountText @{ Items = @(1, 2, 3) } | Should -Be '3'
    }
}

Describe 'Write-ADHealthConsole' {
    BeforeEach {
        Mock -ModuleName ADHealth Write-Host { }
        $data = New-FakeData -Users @(New-FakeUser) -Gpos $null -Errors @{ Gpos = 'Access denied' }
        $results = @(
            New-FakeResult -Id 'PasswordNotRequired' -Name 'Password not required' -Severity 'High' -Findings @(New-FakeFinding)
            New-FakeResult -Id 'StaleUser' -Name 'Stale enabled users' -Severity 'Medium'
            New-FakeResult -Id 'UnlinkedGpo' -Name 'Unlinked GPOs' -Severity 'Low' -Status 'Skipped' -Reason 'Data not collected: Gpos'
        )
        Invoke-InModule Write-ADHealthConsole @{ Data = $data; Results = $results; OutputFiles = @('C:\reports\r.html') }
    }

    It 'prints a header with domain, DC and object counts' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*lab.local*' }
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*dc01.lab.local*2026-10-15 12:00*' }
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*1 users*n/a GPOs*' }
    }
    It 'colours rows by severity' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like 'Password not required*High*1' -and $ForegroundColor -eq 'Red' }
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like 'Stale enabled users*Medium*0' -and $ForegroundColor -eq 'Yellow' }
    }
    It 'greys out skipped checks and explains why' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like 'Unlinked GPOs*Skipped' -and $ForegroundColor -eq 'DarkGray' }
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*Unlinked GPOs: Data not collected: Gpos*' }
    }
    It 'lists collection errors in yellow' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*Gpos*Access denied*' -and $ForegroundColor -eq 'Yellow' }
    }
    It 'lists the files written' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*C:\reports\r.html*' }
    }
}
