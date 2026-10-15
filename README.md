# ADHealth

Read-only Active Directory object hygiene report. Finds stale and never-used
accounts, risky password flags, empty or abandoned groups, unlinked GPOs,
empty OUs and end-of-life operating systems.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on a domain-joined machine
- RSAT ActiveDirectory module
  - Windows 10/11: `Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`
  - Windows Server: `Install-WindowsFeature RSAT-AD-PowerShell`
- Normal domain-user read rights (nothing in AD is changed)

## Usage

```powershell
Import-Module .\ADHealth\ADHealth.psd1
Invoke-ADHealthReport -OutputPath .\reports            # console summary + HTML
Invoke-ADHealthReport -OutputPath .\reports -Csv       # plus one CSV per check
Invoke-ADHealthReport -SearchBase 'OU=Staff,DC=lab,DC=local' -StaleDays 60
Invoke-ADHealthReport -Include StaleUser, StaleComputer -NoHtml -PassThru
Get-Help Invoke-ADHealthReport -Full
```

Check Ids: StaleUser, NeverLoggedOnUser, PasswordNeverExpires, PasswordNotRequired,
OldPassword, DisabledUserInGroups, StaleComputer, EolOperatingSystem, EmptyGroup,
GroupOnlyDisabledMembers, UnlinkedGpo, EmptyOU.

## Tests

Requires Pester 5.5+ (`Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -SkipPublisherCheck`).
Tests do not need AD.

```powershell
pwsh -NoProfile -File Tests/Invoke-Tests.ps1
```

## Adding a check

Drop a file in `ADHealth/Private/Checks/` that calls `Register-ADHealthCheck`
and defines `Test-<Id> -Data -Config` returning `New-ADHealthFinding` objects.
