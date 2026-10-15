BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force
}

Describe 'Export-ADHealthCsv' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dir
    }

    It 'writes one CSV per check with findings and returns the paths' {
        $results = @(
            New-FakeResult -Id 'StaleUser' -Findings @((New-FakeFinding -ObjectName 'alice'), (New-FakeFinding -ObjectName 'bob'))
            New-FakeResult -Id 'EmptyOU' -Name 'Empty OUs' -Severity 'Info'
            New-FakeResult -Id 'UnlinkedGpo' -Name 'Unlinked GPOs' -Severity 'Low' -Status 'Skipped' -Reason 'x'
        )
        $paths = @(Invoke-InModule Export-ADHealthCsv @{ Results = $results; Directory = $dir; Prefix = 'ADHealth_lab.local_20261015-1200' })
        $paths.Count | Should -Be 1
        $paths[0] | Should -Be (Join-Path $dir 'ADHealth_lab.local_20261015-1200_StaleUser.csv')
        @(Get-ChildItem -LiteralPath $dir).Count | Should -Be 1
    }

    It 'writes the finding columns in a stable order' {
        $results = @(New-FakeResult -Id 'StaleUser' -Findings @(New-FakeFinding -ObjectName 'alice'))
        $path = Invoke-InModule Export-ADHealthCsv @{ Results = $results; Directory = $dir; Prefix = 'p' }
        $rows = @(Import-Csv -LiteralPath $path)
        $rows.Count | Should -Be 1
        $rows[0].PSObject.Properties.Name | Should -Be @('CheckId', 'CheckName', 'Category', 'Severity', 'ObjectName', 'DistinguishedName', 'Detail')
        $rows[0].ObjectName | Should -Be 'alice'
        $rows[0].DistinguishedName | Should -Be 'CN=alice,OU=Staff,DC=lab,DC=local'
    }

    It 'writes nothing when there are no findings' {
        $results = @(New-FakeResult -Id 'StaleUser')
        @(Invoke-InModule Export-ADHealthCsv @{ Results = $results; Directory = $dir; Prefix = 'p' }).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $dir).Count | Should -Be 0
    }
}
