BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force
}

Describe 'Export-ADHealthHtml' {
    BeforeAll {
        $data = New-FakeData -Users @(New-FakeUser) -Gpos $null -Errors @{ Gpos = 'Access denied' }
        $evil = New-FakeFinding -CheckId 'PasswordNotRequired' -CheckName 'Password not required' -Severity 'High' `
            -ObjectName '<script>alert(1)</script>' -Detail 'Password not required flag set'
        $results = @(
            New-FakeResult -Id 'PasswordNotRequired' -Name 'Password not required' -Severity 'High' -Findings @($evil)
            New-FakeResult -Id 'StaleUser' -Name 'Stale enabled users' -Severity 'Medium'
            New-FakeResult -Id 'UnlinkedGpo' -Name 'Unlinked GPOs' -Severity 'Low' -Status 'Skipped' -Reason 'Data not collected: Gpos'
        )
        $path = Join-Path $TestDrive 'report.html'
        Invoke-InModule Export-ADHealthHtml @{ Data = $data; Results = $results; Config = (New-FakeConfig); Path = $path }
        $html = Get-Content -LiteralPath $path -Raw
    }

    It 'writes a complete, self-contained HTML document' {
        $html | Should -Match '^<!DOCTYPE html>'
        $html | Should -Match '</html>\s*$'
        $html | Should -Match '<style>'
        $html | Should -Not -Match 'https?://'
        $html | Should -Not -Match '<script'
        $html | Should -Not -Match '<link'
    }

    It 'writes UTF-8 without a BOM' {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Be ([byte][char]'<')
    }

    It 'shows the domain and DC in the header' {
        $html | Should -Match '<title>AD Health - lab\.local</title>'
        $html | Should -Match 'dc01\.lab\.local'
    }

    It 'shows a finding count tile per severity' {
        $html | Should -Match '<div class="n sev-High">1</div>'
        $html | Should -Match '<div class="n sev-Medium">0</div>'
        $html | Should -Match '<div class="n sev-Low">0</div>'
        $html | Should -Match '<div class="n sev-Info">0</div>'
    }

    It 'includes a summary row linking to each check section' {
        $html | Should -Match '<a href="#check-PasswordNotRequired">Password not required</a>'
        $html | Should -Match '<a href="#check-UnlinkedGpo">Unlinked GPOs</a>'
    }

    It 'opens High sections that have findings and leaves others closed' {
        $html | Should -Match '<details id="check-PasswordNotRequired" open>'
        $html | Should -Match '<details id="check-StaleUser">'
    }

    It 'renders empty and skipped sections with an explanation' {
        $html | Should -Match 'No findings\.'
        $html | Should -Match 'Data not collected: Gpos'
    }

    It 'HTML-encodes object values' {
        $html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
    }

    It 'lists thresholds, the replication caveat and collection errors in the footer' {
        $html | Should -Match 'Stale after 90 days'
        $html | Should -Match 'never-logged-on grace 30 days'
        $html | Should -Match 'password age 365 days'
        $html | Should -Match '14-day'
        $html | Should -Match 'Gpos: Access denied'
    }
}
