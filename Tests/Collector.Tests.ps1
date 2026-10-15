BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force
}

Describe 'Get-ADHealthData' {
    BeforeEach {
        $script:lastLogon = [datetime]'2026-06-01T09:00:00'
        $script:pwdSet = [datetime]'2026-05-01T09:00:00'

        Mock -ModuleName ADHealth Get-ADDomainController { [pscustomobject]@{ HostName = @('dc01.lab.local') } }
        Mock -ModuleName ADHealth Get-ADDomain {
            [pscustomobject]@{ DNSRoot = 'lab.local'; DistinguishedName = 'DC=lab,DC=local'; DomainSID = 'S-1-5-21-1000-2000-3000' }
        }
        Mock -ModuleName ADHealth Get-ADRootDSE { [pscustomobject]@{ configurationNamingContext = 'CN=Configuration,DC=lab,DC=local' } }
        Mock -ModuleName ADHealth Get-ADUser {
            [pscustomobject]@{
                Name = 'Alice'; SamAccountName = 'alice'; DistinguishedName = 'CN=Alice,OU=Staff,DC=lab,DC=local'
                Enabled = $true; lastLogonTimestamp = $script:lastLogon.ToFileTime(); pwdLastSet = $script:pwdSet.ToFileTime()
                whenCreated = [datetime]'2025-01-01'; userAccountControl = 512; PasswordNeverExpires = $false; PasswordNotRequired = $false
                MemberOf = @('CN=Sales,OU=Groups,DC=lab,DC=local'); primaryGroupID = 513; SID = 'S-1-5-21-1000-2000-3000-1105'
            }
            [pscustomobject]@{
                Name = 'Never'; SamAccountName = 'never'; DistinguishedName = 'CN=Never,OU=Staff,DC=lab,DC=local'
                Enabled = $true; lastLogonTimestamp = $null; pwdLastSet = [int64]0
                whenCreated = [datetime]'2025-01-01'; userAccountControl = 512; PasswordNeverExpires = $false; PasswordNotRequired = $false
                MemberOf = $null; primaryGroupID = 513; SID = 'S-1-5-21-1000-2000-3000-1106'
            }
        }
        Mock -ModuleName ADHealth Get-ADComputer {
            [pscustomobject]@{
                Name = 'PC1'; DistinguishedName = 'CN=PC1,OU=Workstations,DC=lab,DC=local'; Enabled = $true
                lastLogonTimestamp = [int64]::MaxValue; pwdLastSet = $script:pwdSet.ToFileTime(); whenCreated = [datetime]'2025-01-01'
                operatingSystem = 'Windows 11 Enterprise'; operatingSystemVersion = '10.0 (22631)'; primaryGroupID = 515
            }
        }
        Mock -ModuleName ADHealth Get-ADGroup {
            [pscustomobject]@{ Name = 'Sales'; DistinguishedName = 'CN=Sales,OU=Groups,DC=lab,DC=local'; member = @('CN=Alice,OU=Staff,DC=lab,DC=local'); SID = 'S-1-5-21-1000-2000-3000-3000'; isCriticalSystemObject = $null }
            [pscustomobject]@{ Name = 'Empty'; DistinguishedName = 'CN=Empty,OU=Groups,DC=lab,DC=local'; member = $null; SID = 'S-1-5-21-1000-2000-3000-3001'; isCriticalSystemObject = $true }
        }
        Mock -ModuleName ADHealth Get-ADOrganizationalUnit {
            [pscustomobject]@{ Name = 'Staff'; DistinguishedName = 'OU=Staff,DC=lab,DC=local' }
        }
        Mock -ModuleName ADHealth Get-ADObject { } # default: nothing
        Mock -ModuleName ADHealth Get-ADObject -ParameterFilter { $Filter -eq '*' } {
            [pscustomobject]@{ DistinguishedName = 'OU=Staff,DC=lab,DC=local' }
            [pscustomobject]@{ DistinguishedName = 'CN=Alice,OU=Staff,DC=lab,DC=local' }
        }
        Mock -ModuleName ADHealth Get-ADObject -ParameterFilter { $LDAPFilter -eq '(objectClass=groupPolicyContainer)' } {
            [pscustomobject]@{ Name = '{31b2f340-016d-11d2-945f-00c04fb984f9}'; displayName = 'Default Domain Policy'; DistinguishedName = 'CN={31B2F340-016D-11D2-945F-00C04FB984F9},CN=Policies,CN=System,DC=lab,DC=local' }
        }
        Mock -ModuleName ADHealth Get-ADObject -ParameterFilter { $LDAPFilter -eq '(gPLink=*)' -and $SearchBase -eq 'DC=lab,DC=local' } {
            [pscustomobject]@{ gPLink = '[LDAP://cn={31B2F340-016D-11D2-945F-00C04FB984F9},cn=policies,cn=system,DC=lab,DC=local;0]' }
            [pscustomobject]@{ gPLink = '[LDAP://cn={31b2f340-016d-11d2-945f-00c04fb984f9},cn=policies,cn=system,DC=lab,DC=local;0]' }
        }
        Mock -ModuleName ADHealth Get-ADObject -ParameterFilter { $LDAPFilter -eq '(gPLink=*)' -and $SearchBase -eq 'CN=Sites,CN=Configuration,DC=lab,DC=local' } {
            [pscustomobject]@{ gPLink = '[LDAP://cn={6AC1786C-016F-11D2-945F-00C04FB984F9},cn=policies,cn=system,DC=lab,DC=local;0]' }
        }
    }

    It 'discovers a DC when -Server is not given and uses it for every query' {
        $data = Invoke-InModule Get-ADHealthData
        $data.Server | Should -Be 'dc01.lab.local'
        Should -Invoke Get-ADUser -ModuleName ADHealth -ParameterFilter { $Server -eq 'dc01.lab.local' } -Times 1 -Exactly
    }

    It 'uses -Server without discovery' {
        $data = Invoke-InModule Get-ADHealthData @{ Server = 'dc02.lab.local' }
        $data.Server | Should -Be 'dc02.lab.local'
        Should -Invoke Get-ADDomainController -ModuleName ADHealth -Times 0 -Exactly
        Should -Invoke Get-ADComputer -ModuleName ADHealth -ParameterFilter { $Server -eq 'dc02.lab.local' } -Times 1 -Exactly
    }

    It 'normalizes the domain' {
        $data = Invoke-InModule Get-ADHealthData
        $data.Domain.DnsRoot | Should -Be 'lab.local'
        $data.Domain.DistinguishedName | Should -Be 'DC=lab,DC=local'
        $data.Domain.DomainSid | Should -Be 'S-1-5-21-1000-2000-3000'
        $data.SearchBase | Should -Be 'DC=lab,DC=local'
        $data.CollectedAt | Should -BeOfType [datetime]
        $data.Errors.Count | Should -Be 0
    }

    It 'requests the user properties the checks need' {
        $null = Invoke-InModule Get-ADHealthData
        Should -Invoke Get-ADUser -ModuleName ADHealth -Times 1 -Exactly -ParameterFilter {
            $p = @($Properties)
            ($p -contains 'lastLogonTimestamp') -and ($p -contains 'pwdLastSet') -and ($p -contains 'whenCreated') -and
            ($p -contains 'userAccountControl') -and ($p -contains 'PasswordNeverExpires') -and ($p -contains 'MemberOf') -and
            ($p -contains 'primaryGroupID') -and ($p -contains 'SID') -and ($p -contains 'Enabled')
        }
    }

    It 'requests the computer and group properties the checks need' {
        $null = Invoke-InModule Get-ADHealthData
        Should -Invoke Get-ADComputer -ModuleName ADHealth -Times 1 -Exactly -ParameterFilter {
            $p = @($Properties)
            ($p -contains 'lastLogonTimestamp') -and ($p -contains 'pwdLastSet') -and ($p -contains 'operatingSystem') -and ($p -contains 'primaryGroupID')
        }
        Should -Invoke Get-ADGroup -ModuleName ADHealth -Times 1 -Exactly -ParameterFilter {
            $p = @($Properties)
            ($p -contains 'member') -and ($p -contains 'isCriticalSystemObject')
        }
    }

    It 'normalizes users, converting FILETIMEs and treating 0 or missing as never' {
        $data = Invoke-InModule Get-ADHealthData
        $data.Users.Count | Should -Be 2
        $alice = $data.Users[0]
        $alice.SamAccountName | Should -Be 'alice'
        $alice.LastLogon | Should -Be $script:lastLogon
        $alice.PasswordLastSet | Should -Be $script:pwdSet
        $alice.MemberOf | Should -Be @('CN=Sales,OU=Groups,DC=lab,DC=local')
        $alice.PrimaryGroupId | Should -Be 513
        $alice.Sid | Should -Be 'S-1-5-21-1000-2000-3000-1105'
        $never = $data.Users[1]
        $never.LastLogon | Should -BeNullOrEmpty
        $never.PasswordLastSet | Should -BeNullOrEmpty
        @($never.MemberOf).Count | Should -Be 0
    }

    It 'treats a lastLogonTimestamp of Int64.MaxValue as never' {
        $data = Invoke-InModule Get-ADHealthData
        $data.Computers[0].LastLogon | Should -BeNullOrEmpty
        $data.Computers[0].OperatingSystem | Should -Be 'Windows 11 Enterprise'
    }

    It 'normalizes groups with empty member lists' {
        $data = Invoke-InModule Get-ADHealthData
        $data.Groups[0].Members | Should -Be @('CN=Alice,OU=Staff,DC=lab,DC=local')
        $data.Groups[0].IsCriticalSystemObject | Should -BeFalse
        @($data.Groups[1].Members).Count | Should -Be 0
        $data.Groups[1].IsCriticalSystemObject | Should -BeTrue
    }

    It 'collects OUs and all object DNs' {
        $data = Invoke-InModule Get-ADHealthData
        $data.OUs[0].Name | Should -Be 'Staff'
        $data.AllObjectDNs | Should -Be @('OU=Staff,DC=lab,DC=local', 'CN=Alice,OU=Staff,DC=lab,DC=local')
    }

    It 'normalizes GPO GUIDs to uppercase without braces' {
        $data = Invoke-InModule Get-ADHealthData
        $data.Gpos[0].Guid | Should -Be '31B2F340-016D-11D2-945F-00C04FB984F9'
        $data.Gpos[0].DisplayName | Should -Be 'Default Domain Policy'
    }

    It 'collects unique GPO links from the domain and from sites' {
        $data = Invoke-InModule Get-ADHealthData
        $data.GpLinks | Should -Be @('31B2F340-016D-11D2-945F-00C04FB984F9', '6AC1786C-016F-11D2-945F-00C04FB984F9')
    }

    It 'scopes objects to -SearchBase but reads GPO links from the whole domain' {
        $data = Invoke-InModule Get-ADHealthData @{ SearchBase = 'OU=Staff,DC=lab,DC=local' }
        $data.SearchBase | Should -Be 'OU=Staff,DC=lab,DC=local'
        Should -Invoke Get-ADUser -ModuleName ADHealth -ParameterFilter { $SearchBase -eq 'OU=Staff,DC=lab,DC=local' } -Times 1 -Exactly
        Should -Invoke Get-ADOrganizationalUnit -ModuleName ADHealth -ParameterFilter { $SearchBase -eq 'OU=Staff,DC=lab,DC=local' } -Times 1 -Exactly
        Should -Invoke Get-ADObject -ModuleName ADHealth -ParameterFilter { $LDAPFilter -eq '(gPLink=*)' -and $SearchBase -eq 'DC=lab,DC=local' } -Times 1 -Exactly
        $data.GpLinks | Should -Contain '31B2F340-016D-11D2-945F-00C04FB984F9'
    }

    It 'records a failed collection step and carries on' {
        Mock -ModuleName ADHealth Get-ADGroup { throw 'Access is denied' }
        $data = Invoke-InModule Get-ADHealthData
        $data.Groups | Should -BeNullOrEmpty
        $data.Errors['Groups'] | Should -Be 'Access is denied'
        $data.Users.Count | Should -Be 2
    }

    It 'records a GpLinks error when the sites query fails' {
        Mock -ModuleName ADHealth Get-ADObject -ParameterFilter { $LDAPFilter -eq '(gPLink=*)' -and $SearchBase -like 'CN=Sites,*' } { throw 'No access to Sites' }
        $data = Invoke-InModule Get-ADHealthData
        $data.GpLinks | Should -BeNullOrEmpty
        $data.Errors['GpLinks'] | Should -Be 'No access to Sites'
    }

    It 'throws a clear error when the domain cannot be reached' {
        Mock -ModuleName ADHealth Get-ADDomain { throw 'Unable to contact the server' }
        { Invoke-InModule Get-ADHealthData } | Should -Throw '*Cannot contact a domain controller: Unable to contact the server*'
    }
}
