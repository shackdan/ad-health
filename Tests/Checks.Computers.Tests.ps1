BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force

    function Invoke-Check {
        param([string]$Name, $Data, [hashtable]$Config = (New-FakeConfig))
        @(Invoke-InModule $Name @{ Data = $Data; Config = $Config })
    }
}

Describe 'Test-StaleComputer' {
    It 'flags an enabled computer whose logon and password are both older than StaleDays' {
        $result = Invoke-Check Test-StaleComputer (New-FakeData -Computers @(New-FakeComputer -Name 'pc-old' -LastLogonDaysAgo 120 -PasswordLastSetDaysAgo 100))
        $result.Count | Should -Be 1
        $result[0].ObjectName | Should -Be 'pc-old'
        $result[0].Detail | Should -Be 'Last logon 120 days ago; password set 100 days ago'
        $result[0].Severity | Should -Be 'Medium'
    }
    It 'does not flag when only the logon is stale' {
        (Invoke-Check Test-StaleComputer (New-FakeData -Computers @(New-FakeComputer -LastLogonDaysAgo 120 -PasswordLastSetDaysAgo 10))).Count | Should -Be 0
    }
    It 'does not flag when only the password is stale' {
        (Invoke-Check Test-StaleComputer (New-FakeData -Computers @(New-FakeComputer -LastLogonDaysAgo 10 -PasswordLastSetDaysAgo 120))).Count | Should -Be 0
    }
    It 'does not flag at exactly the threshold' {
        (Invoke-Check Test-StaleComputer (New-FakeData -Computers @(New-FakeComputer -LastLogonDaysAgo 90 -PasswordLastSetDaysAgo 90))).Count | Should -Be 0
    }
    It 'treats a never-logged-on computer as stale when created more than StaleDays ago' {
        $result = Invoke-Check Test-StaleComputer (New-FakeData -Computers @(New-FakeComputer -LastLogonDaysAgo $null -PasswordLastSetDaysAgo 200 -CreatedDaysAgo 200))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Last logon never; password set 200 days ago'
    }
    It 'does not flag a never-logged-on computer created recently' {
        (Invoke-Check Test-StaleComputer (New-FakeData -Computers @(New-FakeComputer -LastLogonDaysAgo $null -PasswordLastSetDaysAgo 200 -CreatedDaysAgo 10))).Count | Should -Be 0
    }
    It 'ignores disabled computers' {
        (Invoke-Check Test-StaleComputer (New-FakeData -Computers @(New-FakeComputer -Enabled $false -LastLogonDaysAgo 300 -PasswordLastSetDaysAgo 300))).Count | Should -Be 0
    }
}

Describe 'Test-EolOperatingSystem' {
    It 'flags <os>' -ForEach @(
        @{ os = 'Windows XP Professional' }
        @{ os = 'Windows Vista Business' }
        @{ os = 'Windows 7 Enterprise' }
        @{ os = 'Windows 8 Pro' }
        @{ os = 'Windows 8.1 Enterprise' }
        @{ os = 'Windows Server 2003' }
        @{ os = "Windows Server$([char]0x00AE) 2008 Standard" }
        @{ os = 'Windows Server 2008 R2 Enterprise' }
        @{ os = 'Windows Server 2012 Datacenter' }
        @{ os = 'Windows Server 2012 R2 Standard' }
    ) {
        $result = Invoke-Check Test-EolOperatingSystem (New-FakeData -Computers @(New-FakeComputer -Name 'legacy' -OperatingSystem $os))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be $os
        $result[0].Severity | Should -Be 'High'
    }
    It 'does not flag <os>' -ForEach @(
        @{ os = 'Windows 10 Enterprise' }
        @{ os = 'Windows 11 Pro' }
        @{ os = 'Windows Server 2016 Standard' }
        @{ os = 'Windows Server 2019 Datacenter' }
        @{ os = 'Windows Server 2022 Standard' }
        @{ os = 'Windows Server 2025 Datacenter' }
        @{ os = '' }
    ) {
        (Invoke-Check Test-EolOperatingSystem (New-FakeData -Computers @(New-FakeComputer -OperatingSystem $os))).Count | Should -Be 0
    }
    It 'ignores disabled computers' {
        (Invoke-Check Test-EolOperatingSystem (New-FakeData -Computers @(New-FakeComputer -Enabled $false -OperatingSystem 'Windows 7 Enterprise'))).Count | Should -Be 0
    }
}
