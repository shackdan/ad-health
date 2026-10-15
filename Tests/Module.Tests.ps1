BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force
}

Describe 'ADHealth module' {
    It 'imports' {
        Get-Module ADHealth | Should -Not -BeNullOrEmpty
    }
}

Describe 'Register-ADHealthCheck / Get-ADHealthCheck' {
    It 'registers a check that can be fetched by Id' {
        Invoke-InModule Register-ADHealthCheck @{ Definition = @{ Id = 'LookupTest'; Name = 'Lookup'; Category = 'Users'; Severity = 'Low'; Requires = @('Users') } }
        $check = Invoke-InModule Get-ADHealthCheck @{ Id = 'LookupTest' }
        $check.Name | Should -Be 'Lookup'
        $check.Severity | Should -Be 'Low'
    }

    It 'lists registered checks when no Id is given' {
        Invoke-InModule Register-ADHealthCheck @{ Definition = @{ Id = 'ListTest'; Name = 'List'; Category = 'Users'; Severity = 'Info'; Requires = @() } }
        $ids = @(Invoke-InModule Get-ADHealthCheck | ForEach-Object { $_.Id })
        $ids | Should -Contain 'ListTest'
    }

    It 'rejects a duplicate Id' {
        Invoke-InModule Register-ADHealthCheck @{ Definition = @{ Id = 'DupTest'; Name = 'Dup'; Category = 'Users'; Severity = 'Low'; Requires = @() } }
        { Invoke-InModule Register-ADHealthCheck @{ Definition = @{ Id = 'DupTest'; Name = 'Dup'; Category = 'Users'; Severity = 'Low'; Requires = @() } } } |
            Should -Throw "*'DupTest' is already registered*"
    }

    It 'rejects a definition missing a required key' {
        { Invoke-InModule Register-ADHealthCheck @{ Definition = @{ Id = 'NoName'; Category = 'Users'; Severity = 'Low'; Requires = @() } } } |
            Should -Throw "*missing required key 'Name'*"
    }

    It 'rejects an invalid severity' {
        { Invoke-InModule Register-ADHealthCheck @{ Definition = @{ Id = 'BadSev'; Name = 'Bad'; Category = 'Users'; Severity = 'Critical'; Requires = @() } } } |
            Should -Throw "*invalid severity 'Critical'*"
    }

    It 'throws for an unknown Id' {
        { Invoke-InModule Get-ADHealthCheck @{ Id = 'DoesNotExist' } } | Should -Throw "*No check registered with Id 'DoesNotExist'*"
    }
}

Describe 'New-ADHealthFinding' {
    It 'copies the check metadata onto the finding' {
        $check = @{ Id = 'StaleUser'; Name = 'Stale enabled users'; Category = 'Users'; Severity = 'Medium'; Requires = @('Users') }
        $finding = Invoke-InModule New-ADHealthFinding @{ Check = $check; ObjectName = 'alice'; DistinguishedName = 'CN=alice,DC=lab,DC=local'; Detail = 'Last logon 91 days ago' }
        $finding.CheckId | Should -Be 'StaleUser'
        $finding.CheckName | Should -Be 'Stale enabled users'
        $finding.Category | Should -Be 'Users'
        $finding.Severity | Should -Be 'Medium'
        $finding.ObjectName | Should -Be 'alice'
        $finding.DistinguishedName | Should -Be 'CN=alice,DC=lab,DC=local'
        $finding.Detail | Should -Be 'Last logon 91 days ago'
        $finding.PSObject.TypeNames[0] | Should -Be 'ADHealth.Finding'
    }
}
