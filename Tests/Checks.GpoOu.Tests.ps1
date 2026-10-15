BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force

    function Invoke-Check {
        param([string]$Name, $Data, [hashtable]$Config = (New-FakeConfig))
        @(Invoke-InModule $Name @{ Data = $Data; Config = $Config })
    }
}

Describe 'Test-UnlinkedGpo' {
    BeforeAll {
        $linked = New-FakeGpo -DisplayName 'Linked' -Guid '31B2F340-016D-11D2-945F-00C04FB984F9'
        $unlinked = New-FakeGpo -DisplayName 'Orphan' -Guid 'AAAAAAAA-0000-0000-0000-000000000001'
    }
    It 'flags a GPO whose GUID is in no gPLink' {
        $result = Invoke-Check Test-UnlinkedGpo (New-FakeData -Gpos @($linked, $unlinked) -GpLinks @('31B2F340-016D-11D2-945F-00C04FB984F9'))
        $result.Count | Should -Be 1
        $result[0].ObjectName | Should -Be 'Orphan'
        $result[0].Detail | Should -Be "GPO 'Orphan' is not linked anywhere"
        $result[0].Severity | Should -Be 'Low'
    }
    It 'matches GUIDs case-insensitively' {
        (Invoke-Check Test-UnlinkedGpo (New-FakeData -Gpos @($linked) -GpLinks @('31b2f340-016d-11d2-945f-00c04fb984f9'))).Count | Should -Be 0
    }
    It 'falls back to the GUID when the GPO has no display name' {
        $nameless = New-FakeGpo -DisplayName '' -Guid 'BBBBBBBB-0000-0000-0000-000000000002'
        $result = Invoke-Check Test-UnlinkedGpo (New-FakeData -Gpos @($nameless))
        $result[0].ObjectName | Should -Be 'BBBBBBBB-0000-0000-0000-000000000002'
    }
}

Describe 'Test-EmptyOU' {
    It 'flags an OU with no child objects' {
        $ou = New-FakeOU -Name 'Empty'
        $result = Invoke-Check Test-EmptyOU (New-FakeData -OUs @($ou) -AllObjectDNs @($ou.DistinguishedName))
        $result.Count | Should -Be 1
        $result[0].ObjectName | Should -Be 'Empty'
        $result[0].Detail | Should -Be 'OU contains no objects'
        $result[0].Severity | Should -Be 'Info'
    }
    It 'does not flag an OU with a child object' {
        $ou = New-FakeOU -Name 'Staff'
        $dns = @($ou.DistinguishedName, "CN=alice,$($ou.DistinguishedName)")
        (Invoke-Check Test-EmptyOU (New-FakeData -OUs @($ou) -AllObjectDNs $dns)).Count | Should -Be 0
    }
    It 'does not flag an OU whose only child is a sub-OU' {
        $parent = New-FakeOU -Name 'Parent'
        $child = New-FakeOU -Name 'Child' -DistinguishedName "OU=Child,$($parent.DistinguishedName)"
        $dns = @($parent.DistinguishedName, $child.DistinguishedName, "CN=bob,$($child.DistinguishedName)")
        (Invoke-Check Test-EmptyOU (New-FakeData -OUs @($parent, $child) -AllObjectDNs $dns)).Count | Should -Be 0
    }
    It 'handles a child whose name contains an escaped comma' {
        $ou = New-FakeOU -Name 'Sales'
        $dns = @($ou.DistinguishedName, "CN=Smith\, John,$($ou.DistinguishedName)")
        (Invoke-Check Test-EmptyOU (New-FakeData -OUs @($ou) -AllObjectDNs $dns)).Count | Should -Be 0
    }
    It 'handles an OU whose own name contains an escaped comma' {
        $ou = New-FakeOU -Name 'Sales, EMEA' -DistinguishedName 'OU=Sales\, EMEA,DC=lab,DC=local'
        $dns = @($ou.DistinguishedName, 'CN=bob,OU=Sales\, EMEA,DC=lab,DC=local')
        (Invoke-Check Test-EmptyOU (New-FakeData -OUs @($ou) -AllObjectDNs $dns)).Count | Should -Be 0
    }
    It 'matches parent DNs case-insensitively' {
        $ou = New-FakeOU -Name 'Staff'
        $dns = @($ou.DistinguishedName, 'CN=alice,ou=staff,dc=lab,dc=local')
        (Invoke-Check Test-EmptyOU (New-FakeData -OUs @($ou) -AllObjectDNs $dns)).Count | Should -Be 0
    }
}
