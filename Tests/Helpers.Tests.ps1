BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force
}

Describe 'Get-ADHealthDnName' {
    It 'returns the first RDN value' {
        Invoke-InModule Get-ADHealthDnName @{ DistinguishedName = 'CN=Alice,OU=Staff,DC=lab,DC=local' } | Should -Be 'Alice'
    }
    It 'handles an OU' {
        Invoke-InModule Get-ADHealthDnName @{ DistinguishedName = 'OU=Staff,DC=lab,DC=local' } | Should -Be 'Staff'
    }
    It 'unescapes an escaped comma' {
        Invoke-InModule Get-ADHealthDnName @{ DistinguishedName = 'CN=Smith\, John,OU=Staff,DC=lab,DC=local' } | Should -Be 'Smith, John'
    }
}

Describe 'Get-ADHealthDnParent' {
    It 'removes the first RDN' {
        Invoke-InModule Get-ADHealthDnParent @{ DistinguishedName = 'CN=Alice,OU=Staff,DC=lab,DC=local' } | Should -Be 'OU=Staff,DC=lab,DC=local'
    }
    It 'does not split on an escaped comma' {
        Invoke-InModule Get-ADHealthDnParent @{ DistinguishedName = 'CN=Smith\, John,OU=Staff,DC=lab,DC=local' } | Should -Be 'OU=Staff,DC=lab,DC=local'
    }
    It 'returns an empty string for a single RDN' {
        Invoke-InModule Get-ADHealthDnParent @{ DistinguishedName = 'DC=local' } | Should -Be ''
    }
}

Describe 'ConvertFrom-ADHealthFileTime' {
    It 'returns null for null' {
        Invoke-InModule ConvertFrom-ADHealthFileTime @{ Value = $null } | Should -BeNullOrEmpty
    }
    It 'returns null for 0 (never)' {
        Invoke-InModule ConvertFrom-ADHealthFileTime @{ Value = [int64]0 } | Should -BeNullOrEmpty
    }
    It 'returns null for Int64.MaxValue (never)' {
        Invoke-InModule ConvertFrom-ADHealthFileTime @{ Value = [int64]::MaxValue } | Should -BeNullOrEmpty
    }
    It 'converts a FILETIME to a local datetime' {
        $date = [datetime]'2026-01-01T08:30:00'
        Invoke-InModule ConvertFrom-ADHealthFileTime @{ Value = $date.ToFileTime() } | Should -Be $date
    }
    It 'passes a datetime through unchanged' {
        $date = [datetime]'2026-01-01T08:30:00'
        Invoke-InModule ConvertFrom-ADHealthFileTime @{ Value = $date } | Should -Be $date
    }
}

Describe 'ConvertFrom-ADHealthGpLink' {
    It 'extracts uppercase GUIDs regardless of case and link options' {
        $gpLink = '[LDAP://cn={31b2f340-016d-11d2-945f-00c04fb984f9},cn=policies,cn=system,DC=lab,DC=local;0]' +
                  '[LDAP://CN={6AC1786C-016F-11D2-945F-00C04FB984F9},CN=Policies,CN=System,DC=lab,DC=local;2]'
        $guids = @(Invoke-InModule ConvertFrom-ADHealthGpLink @{ GpLink = $gpLink })
        $guids | Should -Be @('31B2F340-016D-11D2-945F-00C04FB984F9', '6AC1786C-016F-11D2-945F-00C04FB984F9')
    }
    It 'returns nothing for an empty or blank gPLink' {
        @(Invoke-InModule ConvertFrom-ADHealthGpLink @{ GpLink = '' }).Count | Should -Be 0
        @(Invoke-InModule ConvertFrom-ADHealthGpLink @{ GpLink = ' ' }).Count | Should -Be 0
    }
}

Describe 'Get-ADHealthAge' {
    It 'returns null for a null date' {
        Invoke-InModule Get-ADHealthAge @{ Date = $null; Reference = (Get-FixtureNow) } | Should -BeNullOrEmpty
    }
    It 'returns whole days' {
        Invoke-InModule Get-ADHealthAge @{ Date = (Get-FixtureNow).AddDays(-91); Reference = (Get-FixtureNow) } | Should -Be 91
    }
    It 'truncates partial days' {
        Invoke-InModule Get-ADHealthAge @{ Date = (Get-FixtureNow).AddDays(-90.5); Reference = (Get-FixtureNow) } | Should -Be 90
    }
}

Describe 'Get-ADHealthRid' {
    It 'returns the last SID component' {
        Invoke-InModule Get-ADHealthRid @{ Sid = 'S-1-5-21-1000-2000-3000-513' } | Should -Be 513
    }
}

Describe 'Test-ADHealthBuiltinAccount' {
    It 'is true for krbtgt (RID 502) in the domain' {
        Invoke-InModule Test-ADHealthBuiltinAccount @{ Sid = "$(Get-FixtureDomainSid)-502"; DomainSid = (Get-FixtureDomainSid) } | Should -BeTrue
    }
    It 'is true for Guest, DefaultAccount, WDAGUtilityAccount (501, 503, 504)' {
        foreach ($rid in 501, 503, 504) {
            Invoke-InModule Test-ADHealthBuiltinAccount @{ Sid = "$(Get-FixtureDomainSid)-$rid"; DomainSid = (Get-FixtureDomainSid) } | Should -BeTrue
        }
    }
    It 'is false for Administrator (500) and normal users' {
        Invoke-InModule Test-ADHealthBuiltinAccount @{ Sid = "$(Get-FixtureDomainSid)-500"; DomainSid = (Get-FixtureDomainSid) } | Should -BeFalse
        Invoke-InModule Test-ADHealthBuiltinAccount @{ Sid = "$(Get-FixtureDomainSid)-1105"; DomainSid = (Get-FixtureDomainSid) } | Should -BeFalse
    }
    It 'is false for RID 502 in a different domain' {
        Invoke-InModule Test-ADHealthBuiltinAccount @{ Sid = 'S-1-5-21-9-9-9-502'; DomainSid = (Get-FixtureDomainSid) } | Should -BeFalse
    }
}

Describe 'Select-ADHealthUser' {
    BeforeAll {
        $data = New-FakeData -Users @(
            New-FakeUser -Name 'on'
            New-FakeUser -Name 'off' -Enabled $false
            New-FakeUser -Name 'krbtgt' -Enabled $false -Rid 502
            New-FakeUser -Name 'guest' -Rid 501
        )
    }
    It 'returns enabled non-built-in users by default' {
        @(Invoke-InModule Select-ADHealthUser @{ Data = $data } | ForEach-Object { $_.Name }) | Should -Be @('on')
    }
    It 'returns disabled non-built-in users with -Disabled' {
        @(Invoke-InModule Select-ADHealthUser @{ Data = $data; Disabled = $true } | ForEach-Object { $_.Name }) | Should -Be @('off')
    }
}
