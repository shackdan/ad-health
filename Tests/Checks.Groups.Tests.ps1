BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force

    function Invoke-Check {
        param([string]$Name, $Data, [hashtable]$Config = (New-FakeConfig))
        @(Invoke-InModule $Name @{ Data = $Data; Config = $Config })
    }
}

Describe 'Test-EmptyGroup' {
    It 'flags a group with no members' {
        $result = Invoke-Check Test-EmptyGroup (New-FakeData -Groups @(New-FakeGroup -Name 'Unused'))
        $result.Count | Should -Be 1
        $result[0].ObjectName | Should -Be 'Unused'
        $result[0].Detail | Should -Be 'Group has no members'
        $result[0].Severity | Should -Be 'Info'
    }
    It 'does not flag a group with members' {
        (Invoke-Check Test-EmptyGroup (New-FakeData -Groups @(New-FakeGroup -Members @('CN=a,DC=lab,DC=local')))).Count | Should -Be 0
    }
    It 'ignores critical system objects' {
        (Invoke-Check Test-EmptyGroup (New-FakeData -Groups @(New-FakeGroup -IsCriticalSystemObject $true))).Count | Should -Be 0
    }
    It 'ignores groups under CN=Builtin' {
        $group = New-FakeGroup -Name 'Print Operators' -DistinguishedName 'CN=Print Operators,CN=Builtin,DC=lab,DC=local'
        (Invoke-Check Test-EmptyGroup (New-FakeData -Groups @($group))).Count | Should -Be 0
    }
    It 'ignores a group used as a user primary group' {
        $data = New-FakeData -Groups @(New-FakeGroup -Name 'Contractors' -Rid 4000) -Users @(New-FakeUser -PrimaryGroupId 4000)
        (Invoke-Check Test-EmptyGroup $data).Count | Should -Be 0
    }
    It 'ignores a group used as a computer primary group' {
        $data = New-FakeData -Groups @(New-FakeGroup -Name 'Kiosks' -Rid 4001) -Computers @(New-FakeComputer -PrimaryGroupId 4001)
        (Invoke-Check Test-EmptyGroup $data).Count | Should -Be 0
    }
}

Describe 'Test-GroupOnlyDisabledMembers' {
    BeforeAll {
        $offUser = New-FakeUser -Name 'off' -Enabled $false
        $offPc = New-FakeComputer -Name 'offpc' -Enabled $false
        $onUser = New-FakeUser -Name 'on'
    }
    It 'flags a group whose user and computer members are all disabled' {
        $group = New-FakeGroup -Name 'Old Team' -Members @($offUser.DistinguishedName, $offPc.DistinguishedName)
        $result = Invoke-Check Test-GroupOnlyDisabledMembers (New-FakeData -Groups @($group) -Users @($offUser) -Computers @($offPc))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'All 2 user/computer member(s) disabled'
        $result[0].Severity | Should -Be 'Low'
    }
    It 'does not flag a group with an enabled member' {
        $group = New-FakeGroup -Members @($offUser.DistinguishedName, $onUser.DistinguishedName)
        (Invoke-Check Test-GroupOnlyDisabledMembers (New-FakeData -Groups @($group) -Users @($offUser, $onUser))).Count | Should -Be 0
    }
    It 'ignores members that are groups or unknown objects' {
        $group = New-FakeGroup -Members @($offUser.DistinguishedName, 'CN=Nested,OU=Groups,DC=lab,DC=local', 'CN=Contact,OU=Other,DC=lab,DC=local')
        $result = Invoke-Check Test-GroupOnlyDisabledMembers (New-FakeData -Groups @($group) -Users @($offUser))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'All 1 user/computer member(s) disabled'
    }
    It 'does not flag a group with no resolvable user or computer members' {
        $group = New-FakeGroup -Members @('CN=Nested,OU=Groups,DC=lab,DC=local')
        (Invoke-Check Test-GroupOnlyDisabledMembers (New-FakeData -Groups @($group))).Count | Should -Be 0
    }
    It 'ignores built-in accounts so Guests and Denied RODC are not flagged' {
        $guest = New-FakeUser -Name 'Guest' -Rid 501 -Enabled $false -DistinguishedName 'CN=Guest,CN=Users,DC=lab,DC=local'
        $krbtgt = New-FakeUser -Name 'krbtgt' -Rid 502 -Enabled $false -DistinguishedName 'CN=krbtgt,CN=Users,DC=lab,DC=local'
        $guests = New-FakeGroup -Name 'Guests' -DistinguishedName 'CN=Guests,CN=Builtin,DC=lab,DC=local' `
            -Members @($guest.DistinguishedName, 'CN=Domain Guests,CN=Users,DC=lab,DC=local')
        $deniedRodc = New-FakeGroup -Name 'Denied RODC Password Replication Group' `
            -Members @($krbtgt.DistinguishedName, 'CN=Domain Admins,CN=Users,DC=lab,DC=local', 'CN=Domain Controllers,CN=Users,DC=lab,DC=local')
        (Invoke-Check Test-GroupOnlyDisabledMembers (New-FakeData -Groups @($guests, $deniedRodc) -Users @($guest, $krbtgt))).Count | Should -Be 0
    }
    It 'matches member DNs case-insensitively' {
        $group = New-FakeGroup -Members @($onUser.DistinguishedName.ToLowerInvariant(), $offUser.DistinguishedName.ToUpperInvariant())
        (Invoke-Check Test-GroupOnlyDisabledMembers (New-FakeData -Groups @($group) -Users @($offUser, $onUser))).Count | Should -Be 0
    }
}
