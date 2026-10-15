BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force
}

Describe 'Module surface' {
    It 'exports only Invoke-ADHealthReport' {
        @((Get-Module ADHealth).ExportedFunctions.Keys) | Should -Be @('Invoke-ADHealthReport')
    }
}

Describe 'Assert-ADHealthPrerequisite' {
    It 'throws an RSAT hint when the ActiveDirectory module is unavailable' {
        Mock -ModuleName ADHealth Get-Module { }
        { Invoke-InModule Assert-ADHealthPrerequisite } | Should -Throw '*ActiveDirectory*RSAT*'
    }
    It 'does nothing when the module is already loaded' {
        Mock -ModuleName ADHealth Get-Module { [pscustomobject]@{ Name = 'ActiveDirectory' } }
        Mock -ModuleName ADHealth Import-Module { }
        Invoke-InModule Assert-ADHealthPrerequisite
        Should -Invoke Import-Module -ModuleName ADHealth -Times 0 -Exactly
    }
}

Describe 'Resolve-ADHealthOutputPath' {
    It 'creates a missing folder and returns its full path' {
        $target = Join-Path $TestDrive 'new\nested'
        $result = Invoke-InModule Resolve-ADHealthOutputPath @{ Path = $target }
        $result | Should -Be $target
        Test-Path -LiteralPath $target -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $target -Force).Count | Should -Be 0
    }
    It 'throws when the path cannot be created' {
        $blocker = Join-Path $TestDrive 'blocker.txt'
        Set-Content -LiteralPath $blocker -Value 'x'
        { Invoke-InModule Resolve-ADHealthOutputPath @{ Path = (Join-Path $blocker 'sub') } } | Should -Throw '*is not writable*'
    }
}

Describe 'Invoke-ADHealthReport' {
    BeforeEach {
        $outDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock -ModuleName ADHealth Assert-ADHealthPrerequisite { }
        Mock -ModuleName ADHealth Write-Host { }
        Mock -ModuleName ADHealth Get-ADHealthData {
            New-FakeData -Users @(
                New-FakeUser -Name 'old' -LastLogonDaysAgo 45
                New-FakeUser -Name 'svc' -PasswordNeverExpires $true
            )
        }
    }

    It 'writes the HTML report with the expected name and returns findings with -PassThru' {
        $findings = @(Invoke-ADHealthReport -OutputPath $outDir -PassThru)
        Test-Path -LiteralPath (Join-Path $outDir 'ADHealth_lab.local_20261015-1200.html') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $outDir).Count | Should -Be 1
        @($findings | ForEach-Object { $_.CheckId }) | Should -Be @('PasswordNeverExpires')
    }

    It 'writes nothing to the pipeline without -PassThru' {
        @(Invoke-ADHealthReport -OutputPath $outDir).Count | Should -Be 0
    }

    It 'passes thresholds through to the checks' {
        $findings = @(Invoke-ADHealthReport -OutputPath $outDir -StaleDays 30 -PassThru)
        @($findings | ForEach-Object { $_.CheckId } | Sort-Object) | Should -Be @('PasswordNeverExpires', 'StaleUser')
    }

    It 'writes CSVs with -Csv and skips HTML with -NoHtml' {
        $null = Invoke-ADHealthReport -OutputPath $outDir -Csv -NoHtml
        @(Get-ChildItem -LiteralPath $outDir | ForEach-Object { $_.Name }) | Should -Be @('ADHealth_lab.local_20261015-1200_PasswordNeverExpires.csv')
    }

    It 'honours -Include' {
        $findings = @(Invoke-ADHealthReport -OutputPath $outDir -NoHtml -StaleDays 30 -Include StaleUser -PassThru)
        @($findings | ForEach-Object { $_.CheckId }) | Should -Be @('StaleUser')
    }

    It 'passes connection parameters to the collector' {
        $null = Invoke-ADHealthReport -OutputPath $outDir -NoHtml -Server 'dc02.lab.local' -SearchBase 'OU=Staff,DC=lab,DC=local'
        Should -Invoke Get-ADHealthData -ModuleName ADHealth -Times 1 -Exactly -ParameterFilter {
            $Server -eq 'dc02.lab.local' -and $SearchBase -eq 'OU=Staff,DC=lab,DC=local'
        }
    }

    It 'rejects an unknown check Id before querying AD' {
        { Invoke-ADHealthReport -OutputPath $outDir -Include 'Nope' } | Should -Throw "*Unknown check Id 'Nope'*"
        Should -Invoke Get-ADHealthData -ModuleName ADHealth -Times 0 -Exactly
    }

    It 'creates a missing output folder' {
        $nested = Join-Path $outDir 'a\b'
        $null = Invoke-ADHealthReport -OutputPath $nested
        Test-Path -LiteralPath (Join-Path $nested 'ADHealth_lab.local_20261015-1200.html') | Should -BeTrue
    }

    It 'fails before querying AD when the output path is unwritable' {
        $blocker = Join-Path $TestDrive "blocker-$([guid]::NewGuid().ToString('N')).txt"
        Set-Content -LiteralPath $blocker -Value 'x'
        { Invoke-ADHealthReport -OutputPath (Join-Path $blocker 'sub') } | Should -Throw '*is not writable*'
        Should -Invoke Get-ADHealthData -ModuleName ADHealth -Times 0 -Exactly
    }

    It 'does not touch the output path when no files are requested' {
        $null = Invoke-ADHealthReport -OutputPath $outDir -NoHtml
        Test-Path -LiteralPath $outDir | Should -BeFalse
    }

    It 'rejects a non-positive threshold' {
        { Invoke-ADHealthReport -OutputPath $outDir -StaleDays 0 } | Should -Throw
    }
}
