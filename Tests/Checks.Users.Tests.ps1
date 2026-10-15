BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force

    function Invoke-Check {
        param([string]$Name, $Data, [hashtable]$Config = (New-FakeConfig))
        @(Invoke-InModule $Name @{ Data = $Data; Config = $Config })
    }
}

Describe 'Test-StaleUser' {
    It 'flags an enabled user whose last logon is older than StaleDays' {
        $result = Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -Name 'old' -LastLogonDaysAgo 91))
        $result.Count | Should -Be 1
        $result[0].ObjectName | Should -Be 'old'
        $result[0].DistinguishedName | Should -Be 'CN=old,OU=Staff,DC=lab,DC=local'
        $result[0].Detail | Should -Be 'Last logon 91 days ago'
        $result[0].Severity | Should -Be 'Medium'
        $result[0].CheckId | Should -Be 'StaleUser'
    }
    It 'does not flag a user exactly at the threshold' {
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo 90))).Count | Should -Be 0
    }
    It 'ignores disabled users' {
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -Enabled $false -LastLogonDaysAgo 200))).Count | Should -Be 0
    }
    It 'ignores users that never logged on' {
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo $null))).Count | Should -Be 0
    }
    It 'ignores built-in accounts' {
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -Name 'krbtgt' -Rid 502 -LastLogonDaysAgo 400))).Count | Should -Be 0
    }
    It 'honours a custom StaleDays' {
        $config = New-FakeConfig -Override @{ StaleDays = 30 }
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo 31)) $config).Count | Should -Be 1
    }
}

Describe 'Test-NeverLoggedOnUser' {
    It 'flags an enabled user with no logon created longer ago than the grace period' {
        $result = Invoke-Check Test-NeverLoggedOnUser (New-FakeData -Users @(New-FakeUser -Name 'new' -LastLogonDaysAgo $null -CreatedDaysAgo 31))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Never logged on; created 31 days ago'
        $result[0].Severity | Should -Be 'Medium'
    }
    It 'does not flag a user created exactly at the grace period' {
        (Invoke-Check Test-NeverLoggedOnUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo $null -CreatedDaysAgo 30))).Count | Should -Be 0
    }
    It 'does not flag a user that has logged on' {
        (Invoke-Check Test-NeverLoggedOnUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo 5 -CreatedDaysAgo 400))).Count | Should -Be 0
    }
    It 'ignores disabled and built-in users' {
        $users = @(
            New-FakeUser -Enabled $false -LastLogonDaysAgo $null -CreatedDaysAgo 400
            New-FakeUser -Name 'Guest' -Rid 501 -LastLogonDaysAgo $null -CreatedDaysAgo 400
        )
        (Invoke-Check Test-NeverLoggedOnUser (New-FakeData -Users $users)).Count | Should -Be 0
    }
}

Describe 'Test-PasswordNeverExpires' {
    It 'flags an enabled user with PasswordNeverExpires' {
        $result = Invoke-Check Test-PasswordNeverExpires (New-FakeData -Users @(New-FakeUser -Name 'svc' -PasswordNeverExpires $true))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Password set to never expire'
        $result[0].Severity | Should -Be 'Medium'
    }
    It 'does not flag users without the flag' {
        (Invoke-Check Test-PasswordNeverExpires (New-FakeData -Users @(New-FakeUser))).Count | Should -Be 0
    }
    It 'ignores disabled and built-in users' {
        $users = @(
            New-FakeUser -Enabled $false -PasswordNeverExpires $true
            New-FakeUser -Name 'krbtgt' -Rid 502 -PasswordNeverExpires $true
        )
        (Invoke-Check Test-PasswordNeverExpires (New-FakeData -Users $users)).Count | Should -Be 0
    }
}
