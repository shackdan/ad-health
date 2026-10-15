BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force

    function Get-Ids { param($Checks) @($Checks | ForEach-Object { $_.Id } | Sort-Object) }
}

Describe 'Resolve-ADHealthCheckSelection' {
    It 'returns all 12 checks by default' {
        $ids = Get-Ids (Invoke-InModule Resolve-ADHealthCheckSelection)
        $ids | Should -Be @(
            'DisabledUserInGroups', 'EmptyGroup', 'EmptyOU', 'EolOperatingSystem', 'GroupOnlyDisabledMembers', 'NeverLoggedOnUser',
            'OldPassword', 'PasswordNeverExpires', 'PasswordNotRequired', 'StaleComputer', 'StaleUser', 'UnlinkedGpo'
        )
    }
    It 'keeps only included checks' {
        Get-Ids (Invoke-InModule Resolve-ADHealthCheckSelection @{ Include = @('StaleUser', 'EmptyGroup') }) | Should -Be @('EmptyGroup', 'StaleUser')
    }
    It 'drops excluded checks' {
        $ids = Get-Ids (Invoke-InModule Resolve-ADHealthCheckSelection @{ Exclude = @('StaleUser') })
        $ids.Count | Should -Be 11
        $ids | Should -Not -Contain 'StaleUser'
    }
    It 'matches Ids case-insensitively' {
        Get-Ids (Invoke-InModule Resolve-ADHealthCheckSelection @{ Include = @('staleuser') }) | Should -Be @('StaleUser')
    }
    It 'throws for an unknown Id and lists the valid ones' {
        { Invoke-InModule Resolve-ADHealthCheckSelection @{ Include = @('Nope') } } | Should -Throw "*Unknown check Id 'Nope'. Valid Ids:*StaleUser*"
        { Invoke-InModule Resolve-ADHealthCheckSelection @{ Exclude = @('Nope') } } | Should -Throw "*Unknown check Id 'Nope'*"
    }
}

Describe 'Invoke-ADHealthCheck' {
    BeforeAll {
        $staleUser = Invoke-InModule Get-ADHealthCheck @{ Id = 'StaleUser' }
        $neverExpires = Invoke-InModule Get-ADHealthCheck @{ Id = 'PasswordNeverExpires' }
        $emptyGroup = Invoke-InModule Get-ADHealthCheck @{ Id = 'EmptyGroup' }
    }

    It 'runs a check and returns its findings' {
        $data = New-FakeData -Users @(New-FakeUser -Name 'old' -LastLogonDaysAgo 200)
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($staleUser); Data = $data; Config = (New-FakeConfig) })
        $results.Count | Should -Be 1
        $results[0].CheckId | Should -Be 'StaleUser'
        $results[0].CheckName | Should -Be 'Stale enabled users'
        $results[0].Category | Should -Be 'Users'
        $results[0].Severity | Should -Be 'Medium'
        $results[0].Status | Should -Be 'Ran'
        @($results[0].Findings).Count | Should -Be 1
    }

    It 'reports Ran with no findings when nothing matches' {
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($staleUser); Data = (New-FakeData); Config = (New-FakeConfig) })
        $results[0].Status | Should -Be 'Ran'
        @($results[0].Findings).Count | Should -Be 0
    }

    It 'skips a check whose required data failed to collect' {
        $data = New-FakeData -Users $null -Errors @{ Users = 'Access denied' }
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($staleUser); Data = $data; Config = (New-FakeConfig) })
        $results[0].Status | Should -Be 'Skipped'
        $results[0].Reason | Should -Be 'Data not collected: Users'
    }

    It 'lists every missing data set in the reason' {
        $data = New-FakeData -Users $null -Computers $null
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($emptyGroup); Data = $data; Config = (New-FakeConfig) })
        $results[0].Reason | Should -Be 'Data not collected: Users, Computers'
    }

    It 'isolates a check that throws and keeps running the rest' {
        Mock -ModuleName ADHealth Test-StaleUser { throw 'boom' }
        $data = New-FakeData -Users @(New-FakeUser -Name 'svc' -PasswordNeverExpires $true)
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($staleUser, $neverExpires); Data = $data; Config = (New-FakeConfig) })
        $results[0].Status | Should -Be 'Skipped'
        $results[0].Reason | Should -Be 'Check failed: boom'
        @($results[0].Findings).Count | Should -Be 0
        $results[1].Status | Should -Be 'Ran'
        @($results[1].Findings).Count | Should -Be 1
    }

    It 'accepts an empty check list' {
        @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @(); Data = (New-FakeData); Config = (New-FakeConfig) }).Count | Should -Be 0
    }
}
