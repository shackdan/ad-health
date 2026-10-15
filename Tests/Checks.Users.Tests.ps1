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

Describe 'Test-PasswordNotRequired' {
    It 'flags an enabled user with PASSWD_NOTREQD (0x20) set' {
        $result = Invoke-Check Test-PasswordNotRequired (New-FakeData -Users @(New-FakeUser -Name 'np' -UserAccountControl (512 -bor 0x20)))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Password not required flag set'
        $result[0].Severity | Should -Be 'High'
    }
    It 'does not flag an interdomain trust account (UAC 0x800 | 0x20)' {
        (Invoke-Check Test-PasswordNotRequired (New-FakeData -Users @(New-FakeUser -Name 'TRUSTED$' -UserAccountControl 2080))).Count | Should -Be 0
    }
    It 'does not flag a normal account (UAC 512)' {
        (Invoke-Check Test-PasswordNotRequired (New-FakeData -Users @(New-FakeUser -UserAccountControl 512))).Count | Should -Be 0
    }
    It 'ignores disabled and built-in users' {
        $users = @(
            New-FakeUser -Enabled $false -UserAccountControl (514 -bor 0x20)
            New-FakeUser -Name 'Guest' -Rid 501 -UserAccountControl (512 -bor 0x20)
        )
        (Invoke-Check Test-PasswordNotRequired (New-FakeData -Users $users)).Count | Should -Be 0
    }
}

Describe 'Test-OldPassword' {
    It 'flags an enabled user whose password is older than PasswordAgeDays' {
        $result = Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -Name 'old' -PasswordLastSetDaysAgo 366))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Password last set 366 days ago'
        $result[0].Severity | Should -Be 'Low'
    }
    It 'does not flag a password exactly at the threshold' {
        (Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -PasswordLastSetDaysAgo 365))).Count | Should -Be 0
    }
    It 'skips never-expiring passwords (covered by PasswordNeverExpires)' {
        (Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -PasswordLastSetDaysAgo 900 -PasswordNeverExpires $true))).Count | Should -Be 0
    }
    It 'skips users with no pwdLastSet (must change at next logon)' {
        (Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -PasswordLastSetDaysAgo $null))).Count | Should -Be 0
    }
    It 'honours a custom PasswordAgeDays' {
        $config = New-FakeConfig -Override @{ PasswordAgeDays = 180 }
        (Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -PasswordLastSetDaysAgo 181)) $config).Count | Should -Be 1
    }
}

Describe 'Test-DisabledUserInGroups' {
    It 'flags a disabled user that is still a group member, naming up to three groups' {
        $groups = @(
            'CN=Sales,OU=Groups,DC=lab,DC=local'
            'CN=VPN Users,OU=Groups,DC=lab,DC=local'
            'CN=Smith\, Team,OU=Groups,DC=lab,DC=local'
            'CN=Extra,OU=Groups,DC=lab,DC=local'
        )
        $result = Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @(New-FakeUser -Name 'gone' -Enabled $false -MemberOf $groups))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Member of 4 group(s): Sales, VPN Users, Smith, Team...'
        $result[0].Severity | Should -Be 'Low'
    }
    It 'does not add an ellipsis for three or fewer groups' {
        $result = Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @(New-FakeUser -Enabled $false -MemberOf @('CN=Sales,OU=Groups,DC=lab,DC=local')))
        $result[0].Detail | Should -Be 'Member of 1 group(s): Sales'
    }
    It 'does not flag a disabled user with no group memberships' {
        (Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @(New-FakeUser -Enabled $false))).Count | Should -Be 0
    }
    It 'does not flag enabled users' {
        (Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @(New-FakeUser -MemberOf @('CN=Sales,OU=Groups,DC=lab,DC=local')))).Count | Should -Be 0
    }
    It 'ignores the built-in Guest account' {
        $guest = New-FakeUser -Name 'Guest' -Rid 501 -Enabled $false -MemberOf @('CN=Guests,CN=Builtin,DC=lab,DC=local')
        (Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @($guest))).Count | Should -Be 0
    }
}
