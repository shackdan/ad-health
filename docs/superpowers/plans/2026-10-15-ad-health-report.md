# AD Health Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a PowerShell module, `ADHealth`, whose single command `Invoke-ADHealthReport` reads Active Directory (read-only), runs 12 object-hygiene checks, and reports findings to the console, a self-contained HTML file, and optional CSVs.

**Architecture:** One collector (`Get-ADHealthData`) makes a single pass over AD and returns a normalized data object. Each check is a pure function `Test-<Id> -Data -Config` that returns finding objects; checks self-register via `Register-ADHealthCheck` when their file is loaded. A runner applies Include/Exclude and Skipped logic, and three renderers (console, HTML, CSV) consume the results.

**Tech Stack:** PowerShell (Windows PowerShell 5.1 and PowerShell 7), RSAT `ActiveDirectory` module (runtime only), Pester 5.5+ (tests only).

**Spec:** `docs/superpowers/specs/2026-10-15-ad-health-report-design.md`

## Global Constraints

- Read-only: module code calls only `Get-AD*` cmdlets; never `Set-AD*`, `New-AD*`, `Remove-AD*`, `Move-AD*`, etc.
- No dependency on the GroupPolicy (GPMC) module.
- Runtime dependency: RSAT `ActiveDirectory` module. Test dependency: Pester 5.5+. No other dependencies.
- Code must run on Windows PowerShell 5.1 and PowerShell 7: no `??`, `?:`, `&&`/`||`, `ForEach-Object -Parallel` in module code. *(Plan assumption — not stated in spec.)*
- All source files are ASCII only (Windows PowerShell 5.1 reads BOM-less files as ANSI). Use `...` not `…`.
- Default thresholds: `StaleDays = 90`, `NeverLoggedOnGraceDays = 30`, `PasswordAgeDays = 365`.
- "Days ago" = `($Data.CollectedAt - <date>).Days`. Threshold comparisons are strictly greater than: an object exactly at the threshold is **not** flagged.
- Checks compare against `$Data.CollectedAt`, never `Get-Date`.
- Severity values: `High` | `Medium` | `Low` | `Info`.
- All user checks exclude built-in accounts with RIDs 501, 502, 503, 504 relative to the domain SID.
- HTML file name: `ADHealth_<domain>_<yyyyMMdd-HHmm>.html`. CSV file name: `ADHealth_<domain>_<yyyyMMdd-HHmm>_<CheckId>.csv`, only for checks with findings.
- HTML is a single self-contained file (inline CSS, no JavaScript, no external resources); every interpolated value passes through `[System.Net.WebUtility]::HtmlEncode`.
- Commits end with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Distinguished names containing escaped commas** (`CN=Smith\, John,OU=Staff,...`): object names and parent OUs must parse correctly; an OU holding such an object must not be reported empty. Tests: Task 2 (DN helpers), Task 7 (EmptyOU).
2. **`-SearchBase` narrower than the domain**: GPOs linked to OUs outside the search base must still count as linked (no false "unlinked" findings). Test: Task 9 (collector queries gPLink from the domain root, not the search base).
3. **FILETIME values of `0` or `Int64.MaxValue`** in `lastLogonTimestamp` / `pwdLastSet` mean "never" and must become `$null`, not year 1601 or 30828. Tests: Task 2 (converter), Task 9 (collector).
4. **Case differences between DNs / GUIDs** (e.g. a group's `member` DN or a `gPLink` GUID in different case from the object): matching must be case-insensitive. Tests: Task 6 (GroupOnlyDisabledMembers), Task 7 (UnlinkedGpo, EmptyOU).
5. **Output folder that does not exist or cannot be written**: a missing folder is created; an unwritable one fails with a clear error *before* AD is queried. Tests: Task 13.

---

## File Structure

```
ad-health/
  .gitignore                              # Task 13: ignores reports/
  README.md                               # Task 13
  ADHealth/
    ADHealth.psd1                         # Task 1: manifest
    ADHealth.psm1                         # Task 1: registry init + loader
    Public/
      Invoke-ADHealthReport.ps1           # Task 13
    Private/
      Register-ADHealthCheck.ps1          # Task 1
      Get-ADHealthCheck.ps1               # Task 1
      New-ADHealthFinding.ps1             # Task 1
      DistinguishedName.ps1               # Task 2: Get-ADHealthDnName, Get-ADHealthDnParent
      ConvertFrom-ADHealthFileTime.ps1    # Task 2
      ConvertFrom-ADHealthGpLink.ps1      # Task 2
      CheckHelpers.ps1                    # Task 2: Get-ADHealthAge, Get-ADHealthRid, Test-ADHealthBuiltinAccount, Select-ADHealthUser
      EolOperatingSystems.ps1             # Task 5: $script:EolOperatingSystemPatterns
      Invoke-ADHealthCheck.ps1            # Task 8: Resolve-ADHealthCheckSelection, Invoke-ADHealthCheck
      ConvertTo-ADHealthObject.ps1        # Task 9: AD object -> normalized object
      Get-ADHealthData.ps1                # Task 9
      Prerequisites.ps1                   # Task 13: Assert-ADHealthPrerequisite, Resolve-ADHealthOutputPath
      Checks/
        Test-StaleUser.ps1                # Task 3
        Test-NeverLoggedOnUser.ps1        # Task 3
        Test-PasswordNeverExpires.ps1     # Task 3
        Test-PasswordNotRequired.ps1      # Task 4
        Test-OldPassword.ps1              # Task 4
        Test-DisabledUserInGroups.ps1     # Task 4
        Test-StaleComputer.ps1            # Task 5
        Test-EolOperatingSystem.ps1       # Task 5
        Test-EmptyGroup.ps1               # Task 6
        Test-GroupOnlyDisabledMembers.ps1 # Task 6
        Test-UnlinkedGpo.ps1              # Task 7
        Test-EmptyOU.ps1                  # Task 7
      Render/
        Format-ADHealthSummary.ps1        # Task 10: Sort-ADHealthResult, Format-ADHealthSummary, Get-ADHealthCountText
        Write-ADHealthConsole.ps1         # Task 10
        Export-ADHealthHtml.ps1           # Task 11
        Export-ADHealthCsv.ps1            # Task 12
  Tests/
    Invoke-Tests.ps1                      # Task 1: Pester 5 runner
    Fixtures/
      Fixtures.ps1                        # Task 1 (extended in Task 10)
    Module.Tests.ps1                      # Task 1
    Helpers.Tests.ps1                     # Task 2
    Checks.Users.Tests.ps1                # Tasks 3-4
    Checks.Computers.Tests.ps1            # Task 5
    Checks.Groups.Tests.ps1               # Task 6
    Checks.GpoOu.Tests.ps1                # Task 7
    Runner.Tests.ps1                      # Task 8
    Collector.Tests.ps1                   # Task 9
    Render.Console.Tests.ps1              # Task 10
    Render.Html.Tests.ps1                 # Task 11
    Render.Csv.Tests.ps1                  # Task 12
    Invoke-ADHealthReport.Tests.ps1       # Task 13
```

## Shared Contracts

These shapes are used across tasks. Every task's implementer must use these exact names.

**Data object** (returned by `Get-ADHealthData`, built by `New-FakeData` in tests):

| Property | Type | Notes |
|---|---|---|
| `Domain` | pscustomobject | `DnsRoot` (string), `DistinguishedName` (string), `DomainSid` (string, e.g. `S-1-5-21-1000-2000-3000`) |
| `Server` | string | DC that was queried |
| `SearchBase` | string | effective search base |
| `Users` | object[] or `$null` | normalized users (below) |
| `Computers` | object[] or `$null` | normalized computers |
| `Groups` | object[] or `$null` | normalized groups |
| `OUs` | object[] or `$null` | `Name`, `DistinguishedName` |
| `AllObjectDNs` | string[] or `$null` | DN of every object under the search base |
| `Gpos` | object[] or `$null` | `Guid` (uppercase, no braces), `DisplayName`, `DistinguishedName` |
| `GpLinks` | string[] or `$null` | uppercase GPO GUIDs (no braces) linked anywhere |
| `CollectedAt` | datetime | |
| `Errors` | hashtable | property name -> error message |

**Normalized user:** `Name`, `SamAccountName`, `DistinguishedName`, `Enabled` (bool), `LastLogon` (datetime or `$null`), `PasswordLastSet` (datetime or `$null`), `WhenCreated` (datetime), `UserAccountControl` (int), `PasswordNeverExpires` (bool), `MemberOf` (string[]), `PrimaryGroupId` (int), `Sid` (string).

**Normalized computer:** `Name`, `DistinguishedName`, `Enabled` (bool), `LastLogon`, `PasswordLastSet`, `WhenCreated`, `OperatingSystem` (string, `''` if unset), `OperatingSystemVersion` (string), `PrimaryGroupId` (int).

**Normalized group:** `Name`, `DistinguishedName`, `Members` (string[] of DNs), `Sid` (string), `IsCriticalSystemObject` (bool).

**Check definition** (hashtable): `Id`, `Name`, `Category`, `Severity`, `Requires` (string[] of Data property names).

**Finding** (pscustomobject, type name `ADHealth.Finding`): `CheckId`, `CheckName`, `Category`, `Severity`, `ObjectName`, `DistinguishedName`, `Detail`.

**Check result** (pscustomobject, type name `ADHealth.CheckResult`): `CheckId`, `CheckName`, `Category`, `Severity`, `Status` (`Ran` | `Skipped`), `Reason` (string), `Findings` (object[]).

**Config** (hashtable): `StaleDays`, `NeverLoggedOnGraceDays`, `PasswordAgeDays` (ints).

**Check table:**

| Id | Name | Category | Severity | Requires |
|---|---|---|---|---|
| StaleUser | Stale enabled users | Users | Medium | Users |
| NeverLoggedOnUser | Never-logged-on users | Users | Medium | Users |
| PasswordNeverExpires | Password never expires | Users | Medium | Users |
| PasswordNotRequired | Password not required | Users | High | Users |
| OldPassword | Old passwords | Users | Low | Users |
| DisabledUserInGroups | Disabled users in groups | Users | Low | Users |
| StaleComputer | Stale enabled computers | Computers | Medium | Computers |
| EolOperatingSystem | End-of-life operating systems | Computers | High | Computers |
| EmptyGroup | Empty groups | Groups | Info | Groups, Users, Computers |
| GroupOnlyDisabledMembers | Groups with only disabled members | Groups | Low | Groups, Users, Computers |
| UnlinkedGpo | Unlinked GPOs | GPOs | Low | Gpos, GpLinks |
| EmptyOU | Empty OUs | OUs | Info | OUs, AllObjectDNs |

## Running Tests

All commands run from the repo root (`C:\Users\dan.THENEWTONLAB\Documents\code\ad-health`) in PowerShell 7:

```powershell
pwsh -NoProfile -File Tests/Invoke-Tests.ps1                                 # everything
pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Helpers.Tests.ps1   # one file
```

Tests never touch AD: `Tests/Fixtures/Fixtures.ps1` defines global stub functions for every `Get-AD*` cmdlet the module uses (functions take precedence over cmdlets, so the real module is never auto-loaded), and tests `Mock` those stubs.

---

### Task 1: Module skeleton, test harness, check registry, finding factory

**Files:**
- Create: `ADHealth/ADHealth.psd1`
- Create: `ADHealth/ADHealth.psm1`
- Create: `ADHealth/Private/Register-ADHealthCheck.ps1`
- Create: `ADHealth/Private/Get-ADHealthCheck.ps1`
- Create: `ADHealth/Private/New-ADHealthFinding.ps1`
- Create: `Tests/Invoke-Tests.ps1`
- Create: `Tests/Fixtures/Fixtures.ps1`
- Test: `Tests/Module.Tests.ps1`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Register-ADHealthCheck [-Definition] <hashtable>` — validates keys `Id, Name, Category, Severity, Requires`; severity in `High|Medium|Low|Info`; throws `"Check '<Id>' is already registered."` on duplicates.
  - `Get-ADHealthCheck [-Id <string>]` — no Id: all definitions in registration order; with Id: that definition or throws `"No check registered with Id '<Id>'."`.
  - `New-ADHealthFinding -Check <hashtable> -ObjectName <string> [-DistinguishedName <string>] -Detail <string>` -> Finding.
  - Test helpers (in `Fixtures.ps1`): `Invoke-InModule [-Command] <string> [[-Arguments] <hashtable>]`, `Get-FixtureNow`, `Get-FixtureDomainSid`, `New-FakeUser`, `New-FakeComputer`, `New-FakeGroup`, `New-FakeOU`, `New-FakeGpo`, `New-FakeData`, `New-FakeConfig`, plus global `Get-AD*` stubs.

- [ ] **Step 1: Install Pester 5**

Windows ships Pester 3.4, which is incompatible. Run:

```powershell
pwsh -NoProfile -Command "Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck; Get-Module -ListAvailable Pester | Select-Object Name, Version"
```

Expected: a Pester version `5.5.0` or later is listed.

- [ ] **Step 2: Create the test runner**

`Tests/Invoke-Tests.ps1`:

```powershell
param(
    [string]$Path = $PSScriptRoot
)

Import-Module Pester -MinimumVersion 5.5.0 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $config
```

- [ ] **Step 3: Create the fixtures**

`Tests/Fixtures/Fixtures.ps1`:

```powershell
# Shared test fixtures. Dot-source from each test file's BeforeAll.

# Global stubs for the AD cmdlets the module calls. Functions take precedence
# over cmdlets, so the real ActiveDirectory module is never loaded by tests.
# Tests replace these with Mock -ModuleName ADHealth.
foreach ($stubName in 'Get-ADDomain', 'Get-ADDomainController', 'Get-ADRootDSE', 'Get-ADUser',
    'Get-ADComputer', 'Get-ADGroup', 'Get-ADOrganizationalUnit', 'Get-ADObject') {
    Set-Item -Path "function:global:$stubName" -Value {
        [CmdletBinding()]
        param($Filter, $LDAPFilter, $Properties, $SearchBase, $SearchScope, $Server, $Credential, $Identity, [switch]$Discover)
        throw "AD stub '$($MyInvocation.MyCommand.Name)' was called without a Mock."
    }
}

function Invoke-InModule {
    # Runs a private ADHealth function with named arguments.
    param(
        [Parameter(Mandatory, Position = 0)][string]$Command,
        [Parameter(Position = 1)][hashtable]$Arguments = @{}
    )
    InModuleScope ADHealth -Parameters @{ Command = $Command; Arguments = $Arguments } {
        param($Command, $Arguments)
        & $Command @Arguments
    }
}

function Get-FixtureNow { [datetime]'2026-10-15T12:00:00' }

function Get-FixtureDomainSid { 'S-1-5-21-1000-2000-3000' }

function Get-FixtureDate {
    param([Nullable[int]]$DaysAgo)
    if ($null -eq $DaysAgo) { return $null }
    (Get-FixtureNow).AddDays(-$DaysAgo)
}

function New-FakeUser {
    param(
        [string]$Name = 'user1',
        [bool]$Enabled = $true,
        [Nullable[int]]$LastLogonDaysAgo = 1,
        [Nullable[int]]$PasswordLastSetDaysAgo = 1,
        [int]$CreatedDaysAgo = 400,
        [int]$UserAccountControl = 512,
        [bool]$PasswordNeverExpires = $false,
        [string[]]$MemberOf = @(),
        [int]$PrimaryGroupId = 513,
        [int]$Rid = 1105,
        [string]$DistinguishedName
    )
    if (-not $DistinguishedName) { $DistinguishedName = "CN=$Name,OU=Staff,DC=lab,DC=local" }
    [pscustomobject]@{
        Name                 = $Name
        SamAccountName       = $Name
        DistinguishedName    = $DistinguishedName
        Enabled              = $Enabled
        LastLogon            = (Get-FixtureDate -DaysAgo $LastLogonDaysAgo)
        PasswordLastSet      = (Get-FixtureDate -DaysAgo $PasswordLastSetDaysAgo)
        WhenCreated          = (Get-FixtureDate -DaysAgo $CreatedDaysAgo)
        UserAccountControl   = $UserAccountControl
        PasswordNeverExpires = $PasswordNeverExpires
        MemberOf             = $MemberOf
        PrimaryGroupId       = $PrimaryGroupId
        Sid                  = "$(Get-FixtureDomainSid)-$Rid"
    }
}

function New-FakeComputer {
    param(
        [string]$Name = 'pc1',
        [bool]$Enabled = $true,
        [Nullable[int]]$LastLogonDaysAgo = 1,
        [Nullable[int]]$PasswordLastSetDaysAgo = 1,
        [int]$CreatedDaysAgo = 400,
        [string]$OperatingSystem = 'Windows 11 Enterprise',
        [string]$OperatingSystemVersion = '10.0 (22631)',
        [int]$PrimaryGroupId = 515,
        [string]$DistinguishedName
    )
    if (-not $DistinguishedName) { $DistinguishedName = "CN=$Name,OU=Workstations,DC=lab,DC=local" }
    [pscustomobject]@{
        Name                   = $Name
        DistinguishedName      = $DistinguishedName
        Enabled                = $Enabled
        LastLogon              = (Get-FixtureDate -DaysAgo $LastLogonDaysAgo)
        PasswordLastSet        = (Get-FixtureDate -DaysAgo $PasswordLastSetDaysAgo)
        WhenCreated            = (Get-FixtureDate -DaysAgo $CreatedDaysAgo)
        OperatingSystem        = $OperatingSystem
        OperatingSystemVersion = $OperatingSystemVersion
        PrimaryGroupId         = $PrimaryGroupId
    }
}

function New-FakeGroup {
    param(
        [string]$Name = 'group1',
        [string[]]$Members = @(),
        [int]$Rid = 3000,
        [bool]$IsCriticalSystemObject = $false,
        [string]$DistinguishedName
    )
    if (-not $DistinguishedName) { $DistinguishedName = "CN=$Name,OU=Groups,DC=lab,DC=local" }
    [pscustomobject]@{
        Name                   = $Name
        DistinguishedName      = $DistinguishedName
        Members                = $Members
        Sid                    = "$(Get-FixtureDomainSid)-$Rid"
        IsCriticalSystemObject = $IsCriticalSystemObject
    }
}

function New-FakeOU {
    param(
        [string]$Name = 'ou1',
        [string]$DistinguishedName
    )
    if (-not $DistinguishedName) { $DistinguishedName = "OU=$Name,DC=lab,DC=local" }
    [pscustomobject]@{ Name = $Name; DistinguishedName = $DistinguishedName }
}

function New-FakeGpo {
    param(
        [string]$DisplayName = 'gpo1',
        [string]$Guid = '11111111-1111-1111-1111-111111111111'
    )
    [pscustomobject]@{
        Guid              = $Guid.ToUpperInvariant()
        DisplayName       = $DisplayName
        DistinguishedName = "CN={$Guid},CN=Policies,CN=System,DC=lab,DC=local"
    }
}

function New-FakeData {
    param(
        [object[]]$Users = @(),
        [object[]]$Computers = @(),
        [object[]]$Groups = @(),
        [object[]]$OUs = @(),
        [string[]]$AllObjectDNs = @(),
        [object[]]$Gpos = @(),
        [string[]]$GpLinks = @(),
        [hashtable]$Errors = @{}
    )
    [pscustomobject]@{
        Domain       = [pscustomobject]@{
            DnsRoot           = 'lab.local'
            DistinguishedName = 'DC=lab,DC=local'
            DomainSid         = (Get-FixtureDomainSid)
        }
        Server       = 'dc01.lab.local'
        SearchBase   = 'DC=lab,DC=local'
        Users        = $Users
        Computers    = $Computers
        Groups       = $Groups
        OUs          = $OUs
        AllObjectDNs = $AllObjectDNs
        Gpos         = $Gpos
        GpLinks      = $GpLinks
        CollectedAt  = (Get-FixtureNow)
        Errors       = $Errors
    }
}

function New-FakeConfig {
    param([hashtable]$Override = @{})
    $config = @{ StaleDays = 90; NeverLoggedOnGraceDays = 30; PasswordAgeDays = 365 }
    foreach ($key in $Override.Keys) { $config[$key] = $Override[$key] }
    $config
}
```

- [ ] **Step 4: Write the failing tests**

`Tests/Module.Tests.ps1`:

```powershell
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
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Module.Tests.ps1`
Expected: FAIL — `Import-Module` cannot find `ADHealth.psd1`.

- [ ] **Step 6: Create the manifest and loader**

`ADHealth/ADHealth.psd1`:

```powershell
@{
    RootModule           = 'ADHealth.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '6f1d2c8e-4b7a-4e0f-9a43-2c5d7e8b9f10'
    Author               = 'Dan Newton'
    Description          = 'Read-only Active Directory object hygiene report.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Invoke-ADHealthReport')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
```

`ADHealth/ADHealth.psm1`:

```powershell
# Checks register themselves into this list when their file is dot-sourced.
$script:CheckRegistry = New-Object 'System.Collections.Generic.List[hashtable]'

# Private first: Checks/ call Register-ADHealthCheck at load time.
foreach ($folder in 'Private', 'Private/Checks', 'Private/Render', 'Public') {
    $path = Join-Path $PSScriptRoot $folder
    if (-not (Test-Path -LiteralPath $path)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $path -Filter '*.ps1' -File | Sort-Object Name) {
        . $file.FullName
    }
}

Export-ModuleMember -Function 'Invoke-ADHealthReport'
```

- [ ] **Step 7: Implement the registry and finding factory**

`ADHealth/Private/Register-ADHealthCheck.ps1`:

```powershell
function Register-ADHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][hashtable]$Definition
    )
    foreach ($key in 'Id', 'Name', 'Category', 'Severity', 'Requires') {
        if (-not $Definition.ContainsKey($key)) {
            throw "Check definition is missing required key '$key'."
        }
    }
    if ($Definition.Severity -notin 'High', 'Medium', 'Low', 'Info') {
        throw "Check '$($Definition.Id)' has invalid severity '$($Definition.Severity)'."
    }
    foreach ($existing in $script:CheckRegistry) {
        if ($existing.Id -eq $Definition.Id) {
            throw "Check '$($Definition.Id)' is already registered."
        }
    }
    $script:CheckRegistry.Add($Definition)
}
```

`ADHealth/Private/Get-ADHealthCheck.ps1`:

```powershell
function Get-ADHealthCheck {
    [CmdletBinding()]
    param(
        [string]$Id
    )
    if (-not $Id) {
        return $script:CheckRegistry.ToArray()
    }
    foreach ($check in $script:CheckRegistry) {
        if ($check.Id -eq $Id) { return $check }
    }
    throw "No check registered with Id '$Id'."
}
```

`ADHealth/Private/New-ADHealthFinding.ps1`:

```powershell
function New-ADHealthFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Check,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ObjectName,
        [AllowEmptyString()][string]$DistinguishedName = '',
        [Parameter(Mandatory)][string]$Detail
    )
    [pscustomobject]@{
        PSTypeName        = 'ADHealth.Finding'
        CheckId           = $Check.Id
        CheckName         = $Check.Name
        Category          = $Check.Category
        Severity          = $Check.Severity
        ObjectName        = $ObjectName
        DistinguishedName = $DistinguishedName
        Detail            = $Detail
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Module.Tests.ps1`
Expected: PASS (8 tests).

- [ ] **Step 9: Commit**

```powershell
git add ADHealth Tests
git commit -m "Add ADHealth module skeleton, check registry and test harness" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Shared helpers (DNs, FILETIME, gPLink, ages, built-in accounts)

**Files:**
- Create: `ADHealth/Private/DistinguishedName.ps1`
- Create: `ADHealth/Private/ConvertFrom-ADHealthFileTime.ps1`
- Create: `ADHealth/Private/ConvertFrom-ADHealthGpLink.ps1`
- Create: `ADHealth/Private/CheckHelpers.ps1`
- Test: `Tests/Helpers.Tests.ps1`

**Interfaces:**
- Consumes: fixtures from Task 1.
- Produces:
  - `Get-ADHealthDnName -DistinguishedName <string>` -> string (first RDN value, unescaped).
  - `Get-ADHealthDnParent -DistinguishedName <string>` -> string (DN minus first RDN; `''` if none).
  - `ConvertFrom-ADHealthFileTime -Value <object>` -> datetime or `$null` (`$null`, `0`, negative, `Int64.MaxValue` -> `$null`; a `[datetime]` passes through).
  - `ConvertFrom-ADHealthGpLink -GpLink <string>` -> zero or more uppercase GUID strings without braces.
  - `Get-ADHealthAge -Date <Nullable[datetime]> -Reference <datetime>` -> int days or `$null`.
  - `Get-ADHealthRid -Sid <string>` -> int.
  - `Test-ADHealthBuiltinAccount -Sid <string> -DomainSid <string>` -> bool.
  - `Select-ADHealthUser -Data <Data> [-Disabled]` -> users (enabled by default, disabled with `-Disabled`), built-ins excluded.

- [ ] **Step 1: Write the failing tests**

`Tests/Helpers.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Helpers.Tests.ps1`
Expected: FAIL — `The term 'Get-ADHealthDnName' is not recognized` (and similar).

- [ ] **Step 3: Implement the helpers**

`ADHealth/Private/DistinguishedName.ps1`:

```powershell
# An RDN value is a run of escaped characters (\x) or anything except , and \.

function Get-ADHealthDnName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DistinguishedName
    )
    $null = $DistinguishedName -match '^(?:[A-Za-z0-9-]+=)?((?:\\.|[^,\\])*)'
    $Matches[1] -replace '\\(.)', '$1'
}

function Get-ADHealthDnParent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DistinguishedName
    )
    if ($DistinguishedName -match '^(?:\\.|[^,\\])*,(.*)$') {
        return $Matches[1]
    }
    ''
}
```

`ADHealth/Private/ConvertFrom-ADHealthFileTime.ps1`:

```powershell
function ConvertFrom-ADHealthFileTime {
    # lastLogonTimestamp / pwdLastSet: 0 and Int64.MaxValue both mean "never".
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    $ticks = [int64]$Value
    if ($ticks -le 0 -or $ticks -eq [int64]::MaxValue) { return $null }
    [datetime]::FromFileTime($ticks)
}
```

`ADHealth/Private/ConvertFrom-ADHealthGpLink.ps1`:

```powershell
function ConvertFrom-ADHealthGpLink {
    # gPLink format: [LDAP://cn={GUID},cn=policies,cn=system,DC=...;options][...]
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$GpLink
    )
    if (-not $GpLink) { return }
    $pattern = 'cn=\{([0-9a-f-]{36})\}'
    foreach ($match in [regex]::Matches($GpLink, $pattern, 'IgnoreCase')) {
        $match.Groups[1].Value.ToUpperInvariant()
    }
}
```

`ADHealth/Private/CheckHelpers.ps1`:

```powershell
function Get-ADHealthAge {
    [CmdletBinding()]
    param(
        [AllowNull()][Nullable[datetime]]$Date,
        [Parameter(Mandatory)][datetime]$Reference
    )
    if ($null -eq $Date) { return $null }
    ($Reference - $Date).Days
}

function Get-ADHealthRid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Sid
    )
    [int]($Sid.Split('-')[-1])
}

function Test-ADHealthBuiltinAccount {
    # Guest (501), krbtgt (502), DefaultAccount (503), WDAGUtilityAccount (504).
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Sid,
        [Parameter(Mandatory)][string]$DomainSid
    )
    if (-not $Sid) { return $false }
    foreach ($rid in 501, 502, 503, 504) {
        if ($Sid -eq "$DomainSid-$rid") { return $true }
    }
    $false
}

function Select-ADHealthUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [switch]$Disabled
    )
    foreach ($user in $Data.Users) {
        if ([bool]$user.Enabled -eq [bool]$Disabled) { continue }
        if (Test-ADHealthBuiltinAccount -Sid $user.Sid -DomainSid $Data.Domain.DomainSid) { continue }
        $user
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Helpers.Tests.ps1`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private Tests/Helpers.Tests.ps1
git commit -m "Add DN, FILETIME, gPLink, age and built-in account helpers" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: User checks - StaleUser, NeverLoggedOnUser, PasswordNeverExpires

**Files:**
- Create: `ADHealth/Private/Checks/Test-StaleUser.ps1`
- Create: `ADHealth/Private/Checks/Test-NeverLoggedOnUser.ps1`
- Create: `ADHealth/Private/Checks/Test-PasswordNeverExpires.ps1`
- Test: `Tests/Checks.Users.Tests.ps1`

**Interfaces:**
- Consumes: `Register-ADHealthCheck`, `Get-ADHealthCheck`, `New-ADHealthFinding` (Task 1); `Select-ADHealthUser`, `Get-ADHealthAge` (Task 2).
- Produces: `Test-StaleUser`, `Test-NeverLoggedOnUser`, `Test-PasswordNeverExpires`, each `-Data <Data> -Config <hashtable>` -> findings. Registered with the Id/Name/Category/Severity/Requires from the Check table.

- [ ] **Step 1: Write the failing tests**

`Tests/Checks.Users.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force

    function Invoke-Check {
        param([string]$Name, $Data, [hashtable]$Config = (New-FakeConfig))
        @(Invoke-InModule $Name @{ Data = $Data; Config = $Config })
    }
}

Describe 'Test-StaleUser' {
    It 'flags an enabled user whose last logon is older than StaleDays' {
        $result = Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -Name 'old' -LastLogonDaysAgo 91))
        $result.Count | Should -Be 1
        $result[0].ObjectName | Should -Be 'old'
        $result[0].DistinguishedName | Should -Be 'CN=old,OU=Staff,DC=lab,DC=local'
        $result[0].Detail | Should -Be 'Last logon 91 days ago'
        $result[0].Severity | Should -Be 'Medium'
        $result[0].CheckId | Should -Be 'StaleUser'
    }
    It 'does not flag a user exactly at the threshold' {
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo 90))).Count | Should -Be 0
    }
    It 'ignores disabled users' {
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -Enabled $false -LastLogonDaysAgo 200))).Count | Should -Be 0
    }
    It 'ignores users that never logged on' {
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo $null))).Count | Should -Be 0
    }
    It 'ignores built-in accounts' {
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -Name 'krbtgt' -Rid 502 -LastLogonDaysAgo 400))).Count | Should -Be 0
    }
    It 'honours a custom StaleDays' {
        $config = New-FakeConfig -Override @{ StaleDays = 30 }
        (Invoke-Check Test-StaleUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo 31)) $config).Count | Should -Be 1
    }
}

Describe 'Test-NeverLoggedOnUser' {
    It 'flags an enabled user with no logon created longer ago than the grace period' {
        $result = Invoke-Check Test-NeverLoggedOnUser (New-FakeData -Users @(New-FakeUser -Name 'new' -LastLogonDaysAgo $null -CreatedDaysAgo 31))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Never logged on; created 31 days ago'
        $result[0].Severity | Should -Be 'Medium'
    }
    It 'does not flag a user created exactly at the grace period' {
        (Invoke-Check Test-NeverLoggedOnUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo $null -CreatedDaysAgo 30))).Count | Should -Be 0
    }
    It 'does not flag a user that has logged on' {
        (Invoke-Check Test-NeverLoggedOnUser (New-FakeData -Users @(New-FakeUser -LastLogonDaysAgo 5 -CreatedDaysAgo 400))).Count | Should -Be 0
    }
    It 'ignores disabled and built-in users' {
        $users = @(
            New-FakeUser -Enabled $false -LastLogonDaysAgo $null -CreatedDaysAgo 400
            New-FakeUser -Name 'Guest' -Rid 501 -LastLogonDaysAgo $null -CreatedDaysAgo 400
        )
        (Invoke-Check Test-NeverLoggedOnUser (New-FakeData -Users $users)).Count | Should -Be 0
    }
}

Describe 'Test-PasswordNeverExpires' {
    It 'flags an enabled user with PasswordNeverExpires' {
        $result = Invoke-Check Test-PasswordNeverExpires (New-FakeData -Users @(New-FakeUser -Name 'svc' -PasswordNeverExpires $true))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Password set to never expire'
        $result[0].Severity | Should -Be 'Medium'
    }
    It 'does not flag users without the flag' {
        (Invoke-Check Test-PasswordNeverExpires (New-FakeData -Users @(New-FakeUser))).Count | Should -Be 0
    }
    It 'ignores disabled and built-in users' {
        $users = @(
            New-FakeUser -Enabled $false -PasswordNeverExpires $true
            New-FakeUser -Name 'krbtgt' -Rid 502 -PasswordNeverExpires $true
        )
        (Invoke-Check Test-PasswordNeverExpires (New-FakeData -Users $users)).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.Users.Tests.ps1`
Expected: FAIL — `The term 'Test-StaleUser' is not recognized`.

- [ ] **Step 3: Implement the checks**

`ADHealth/Private/Checks/Test-StaleUser.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'StaleUser'; Name = 'Stale enabled users'; Category = 'Users'; Severity = 'Medium'; Requires = @('Users') }

function Test-StaleUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'StaleUser'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        $age = Get-ADHealthAge -Date $user.LastLogon -Reference $Data.CollectedAt
        if ($null -ne $age -and $age -gt $Config.StaleDays) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail "Last logon $age days ago"
        }
    }
}
```

`ADHealth/Private/Checks/Test-NeverLoggedOnUser.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'NeverLoggedOnUser'; Name = 'Never-logged-on users'; Category = 'Users'; Severity = 'Medium'; Requires = @('Users') }

function Test-NeverLoggedOnUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'NeverLoggedOnUser'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        if ($null -ne $user.LastLogon) { continue }
        $age = Get-ADHealthAge -Date $user.WhenCreated -Reference $Data.CollectedAt
        if ($null -ne $age -and $age -gt $Config.NeverLoggedOnGraceDays) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail "Never logged on; created $age days ago"
        }
    }
}
```

`ADHealth/Private/Checks/Test-PasswordNeverExpires.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'PasswordNeverExpires'; Name = 'Password never expires'; Category = 'Users'; Severity = 'Medium'; Requires = @('Users') }

function Test-PasswordNeverExpires {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'PasswordNeverExpires'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        if ($user.PasswordNeverExpires) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail 'Password set to never expire'
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.Users.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private/Checks Tests/Checks.Users.Tests.ps1
git commit -m "Add stale, never-logged-on and password-never-expires user checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: User checks - PasswordNotRequired, OldPassword, DisabledUserInGroups

**Files:**
- Create: `ADHealth/Private/Checks/Test-PasswordNotRequired.ps1`
- Create: `ADHealth/Private/Checks/Test-OldPassword.ps1`
- Create: `ADHealth/Private/Checks/Test-DisabledUserInGroups.ps1`
- Modify: `Tests/Checks.Users.Tests.ps1` (append Describe blocks at end of file)

**Interfaces:**
- Consumes: Task 1 registry/finding; Task 2 `Select-ADHealthUser`, `Get-ADHealthAge`, `Get-ADHealthDnName`.
- Produces: `Test-PasswordNotRequired`, `Test-OldPassword`, `Test-DisabledUserInGroups` (`-Data -Config` -> findings).

- [ ] **Step 1: Append the failing tests**

Append to `Tests/Checks.Users.Tests.ps1`:

```powershell
Describe 'Test-PasswordNotRequired' {
    It 'flags an enabled user with PASSWD_NOTREQD (0x20) set' {
        $result = Invoke-Check Test-PasswordNotRequired (New-FakeData -Users @(New-FakeUser -Name 'np' -UserAccountControl (512 -bor 0x20)))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Password not required flag set'
        $result[0].Severity | Should -Be 'High'
    }
    It 'does not flag a normal account (UAC 512)' {
        (Invoke-Check Test-PasswordNotRequired (New-FakeData -Users @(New-FakeUser -UserAccountControl 512))).Count | Should -Be 0
    }
    It 'ignores disabled and built-in users' {
        $users = @(
            New-FakeUser -Enabled $false -UserAccountControl (514 -bor 0x20)
            New-FakeUser -Name 'Guest' -Rid 501 -UserAccountControl (512 -bor 0x20)
        )
        (Invoke-Check Test-PasswordNotRequired (New-FakeData -Users $users)).Count | Should -Be 0
    }
}

Describe 'Test-OldPassword' {
    It 'flags an enabled user whose password is older than PasswordAgeDays' {
        $result = Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -Name 'old' -PasswordLastSetDaysAgo 366))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Password last set 366 days ago'
        $result[0].Severity | Should -Be 'Low'
    }
    It 'does not flag a password exactly at the threshold' {
        (Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -PasswordLastSetDaysAgo 365))).Count | Should -Be 0
    }
    It 'skips never-expiring passwords (covered by PasswordNeverExpires)' {
        (Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -PasswordLastSetDaysAgo 900 -PasswordNeverExpires $true))).Count | Should -Be 0
    }
    It 'skips users with no pwdLastSet (must change at next logon)' {
        (Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -PasswordLastSetDaysAgo $null))).Count | Should -Be 0
    }
    It 'honours a custom PasswordAgeDays' {
        $config = New-FakeConfig -Override @{ PasswordAgeDays = 180 }
        (Invoke-Check Test-OldPassword (New-FakeData -Users @(New-FakeUser -PasswordLastSetDaysAgo 181)) $config).Count | Should -Be 1
    }
}

Describe 'Test-DisabledUserInGroups' {
    It 'flags a disabled user that is still a group member, naming up to three groups' {
        $groups = @(
            'CN=Sales,OU=Groups,DC=lab,DC=local'
            'CN=VPN Users,OU=Groups,DC=lab,DC=local'
            'CN=Smith\, Team,OU=Groups,DC=lab,DC=local'
            'CN=Extra,OU=Groups,DC=lab,DC=local'
        )
        $result = Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @(New-FakeUser -Name 'gone' -Enabled $false -MemberOf $groups))
        $result.Count | Should -Be 1
        $result[0].Detail | Should -Be 'Member of 4 group(s): Sales, VPN Users, Smith, Team...'
        $result[0].Severity | Should -Be 'Low'
    }
    It 'does not add an ellipsis for three or fewer groups' {
        $result = Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @(New-FakeUser -Enabled $false -MemberOf @('CN=Sales,OU=Groups,DC=lab,DC=local')))
        $result[0].Detail | Should -Be 'Member of 1 group(s): Sales'
    }
    It 'does not flag a disabled user with no group memberships' {
        (Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @(New-FakeUser -Enabled $false))).Count | Should -Be 0
    }
    It 'does not flag enabled users' {
        (Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @(New-FakeUser -MemberOf @('CN=Sales,OU=Groups,DC=lab,DC=local')))).Count | Should -Be 0
    }
    It 'ignores the built-in Guest account' {
        $guest = New-FakeUser -Name 'Guest' -Rid 501 -Enabled $false -MemberOf @('CN=Guests,CN=Builtin,DC=lab,DC=local')
        (Invoke-Check Test-DisabledUserInGroups (New-FakeData -Users @($guest))).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.Users.Tests.ps1`
Expected: FAIL — `The term 'Test-PasswordNotRequired' is not recognized` (Task 3 tests still pass).

- [ ] **Step 3: Implement the checks**

`ADHealth/Private/Checks/Test-PasswordNotRequired.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'PasswordNotRequired'; Name = 'Password not required'; Category = 'Users'; Severity = 'High'; Requires = @('Users') }

function Test-PasswordNotRequired {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $passwdNotReqd = 0x20
    $check = Get-ADHealthCheck -Id 'PasswordNotRequired'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        if ($user.UserAccountControl -band $passwdNotReqd) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail 'Password not required flag set'
        }
    }
}
```

`ADHealth/Private/Checks/Test-OldPassword.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'OldPassword'; Name = 'Old passwords'; Category = 'Users'; Severity = 'Low'; Requires = @('Users') }

function Test-OldPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'OldPassword'
    foreach ($user in (Select-ADHealthUser -Data $Data)) {
        if ($user.PasswordNeverExpires) { continue }
        $age = Get-ADHealthAge -Date $user.PasswordLastSet -Reference $Data.CollectedAt
        if ($null -ne $age -and $age -gt $Config.PasswordAgeDays) {
            New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName `
                -Detail "Password last set $age days ago"
        }
    }
}
```

`ADHealth/Private/Checks/Test-DisabledUserInGroups.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'DisabledUserInGroups'; Name = 'Disabled users in groups'; Category = 'Users'; Severity = 'Low'; Requires = @('Users') }

function Test-DisabledUserInGroups {
    # MemberOf never includes the primary group, so it is ignored naturally.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'DisabledUserInGroups'
    foreach ($user in (Select-ADHealthUser -Data $Data -Disabled)) {
        $groups = @($user.MemberOf | Where-Object { $_ })
        if ($groups.Count -eq 0) { continue }
        $names = @($groups | Select-Object -First 3 | ForEach-Object { Get-ADHealthDnName -DistinguishedName $_ })
        $detail = "Member of $($groups.Count) group(s): $($names -join ', ')"
        if ($groups.Count -gt 3) { $detail += '...' }
        New-ADHealthFinding -Check $check -ObjectName $user.SamAccountName -DistinguishedName $user.DistinguishedName -Detail $detail
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.Users.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private/Checks Tests/Checks.Users.Tests.ps1
git commit -m "Add password-not-required, old-password and disabled-in-groups user checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Computer checks - StaleComputer, EolOperatingSystem

**Files:**
- Create: `ADHealth/Private/EolOperatingSystems.ps1`
- Create: `ADHealth/Private/Checks/Test-StaleComputer.ps1`
- Create: `ADHealth/Private/Checks/Test-EolOperatingSystem.ps1`
- Test: `Tests/Checks.Computers.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 registry/finding; Task 2 `Get-ADHealthAge`.
- Produces: `$script:EolOperatingSystemPatterns` (string[] of `-like` patterns); `Test-StaleComputer`, `Test-EolOperatingSystem` (`-Data -Config` -> findings).

- [ ] **Step 1: Write the failing tests**

`Tests/Checks.Computers.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.Computers.Tests.ps1`
Expected: FAIL — `The term 'Test-StaleComputer' is not recognized`.

- [ ] **Step 3: Implement the EOL list and checks**

`ADHealth/Private/EolOperatingSystems.ps1`:

```powershell
# -like patterns matched against a computer's operatingSystem attribute.
# 'Windows Server*2008*' also covers 'Windows Server(R) 2008' (trademark symbol).
$script:EolOperatingSystemPatterns = @(
    'Windows XP*'
    'Windows Vista*'
    'Windows 7*'
    'Windows 8*'
    'Windows Server*2003*'
    'Windows Server*2008*'
    'Windows Server*2012*'
)
```

`ADHealth/Private/Checks/Test-StaleComputer.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'StaleComputer'; Name = 'Stale enabled computers'; Category = 'Computers'; Severity = 'Medium'; Requires = @('Computers') }

function Test-StaleComputer {
    # Stale = logon AND machine password both older than StaleDays. A missing
    # date counts as stale only if the object was created more than StaleDays ago.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'StaleComputer'
    foreach ($computer in $Data.Computers) {
        if (-not $computer.Enabled) { continue }
        $createdAge = Get-ADHealthAge -Date $computer.WhenCreated -Reference $Data.CollectedAt
        $createdStale = $null -ne $createdAge -and $createdAge -gt $Config.StaleDays

        $logonAge = Get-ADHealthAge -Date $computer.LastLogon -Reference $Data.CollectedAt
        if ($null -ne $logonAge) { $logonStale = $logonAge -gt $Config.StaleDays } else { $logonStale = $createdStale }

        $passwordAge = Get-ADHealthAge -Date $computer.PasswordLastSet -Reference $Data.CollectedAt
        if ($null -ne $passwordAge) { $passwordStale = $passwordAge -gt $Config.StaleDays } else { $passwordStale = $createdStale }

        if (-not ($logonStale -and $passwordStale)) { continue }

        if ($null -ne $logonAge) { $logonText = "$logonAge days ago" } else { $logonText = 'never' }
        if ($null -ne $passwordAge) { $passwordText = "set $passwordAge days ago" } else { $passwordText = 'never set' }
        New-ADHealthFinding -Check $check -ObjectName $computer.Name -DistinguishedName $computer.DistinguishedName `
            -Detail "Last logon $logonText; password $passwordText"
    }
}
```

`ADHealth/Private/Checks/Test-EolOperatingSystem.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'EolOperatingSystem'; Name = 'End-of-life operating systems'; Category = 'Computers'; Severity = 'High'; Requires = @('Computers') }

function Test-EolOperatingSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'EolOperatingSystem'
    foreach ($computer in $Data.Computers) {
        if (-not $computer.Enabled -or -not $computer.OperatingSystem) { continue }
        foreach ($pattern in $script:EolOperatingSystemPatterns) {
            if ($computer.OperatingSystem -like $pattern) {
                New-ADHealthFinding -Check $check -ObjectName $computer.Name -DistinguishedName $computer.DistinguishedName `
                    -Detail $computer.OperatingSystem
                break
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.Computers.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private Tests/Checks.Computers.Tests.ps1
git commit -m "Add stale computer and end-of-life OS checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Group checks - EmptyGroup, GroupOnlyDisabledMembers

**Files:**
- Create: `ADHealth/Private/Checks/Test-EmptyGroup.ps1`
- Create: `ADHealth/Private/Checks/Test-GroupOnlyDisabledMembers.ps1`
- Test: `Tests/Checks.Groups.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 registry/finding; Task 2 `Get-ADHealthRid`.
- Produces: `Test-EmptyGroup`, `Test-GroupOnlyDisabledMembers` (`-Data -Config` -> findings).

- [ ] **Step 1: Write the failing tests**

`Tests/Checks.Groups.Tests.ps1`:

```powershell
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
    It 'matches member DNs case-insensitively' {
        $group = New-FakeGroup -Members @($onUser.DistinguishedName.ToLowerInvariant(), $offUser.DistinguishedName.ToUpperInvariant())
        (Invoke-Check Test-GroupOnlyDisabledMembers (New-FakeData -Groups @($group) -Users @($offUser, $onUser))).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.Groups.Tests.ps1`
Expected: FAIL — `The term 'Test-EmptyGroup' is not recognized`.

- [ ] **Step 3: Implement the checks**

`ADHealth/Private/Checks/Test-EmptyGroup.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'EmptyGroup'; Name = 'Empty groups'; Category = 'Groups'; Severity = 'Info'; Requires = @('Groups', 'Users', 'Computers') }

function Test-EmptyGroup {
    # A group's 'member' attribute omits objects that use it as their primary
    # group, so groups referenced by any primaryGroupID are not reported.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'EmptyGroup'
    $primaryGroupRids = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($object in @($Data.Users) + @($Data.Computers)) {
        if ($object) { [void]$primaryGroupRids.Add([int]$object.PrimaryGroupId) }
    }
    foreach ($group in $Data.Groups) {
        if (@($group.Members | Where-Object { $_ }).Count -gt 0) { continue }
        if ($group.IsCriticalSystemObject) { continue }
        if ($group.DistinguishedName -match '(^|,)CN=Builtin,') { continue }
        if ($group.Sid -and $primaryGroupRids.Contains((Get-ADHealthRid -Sid $group.Sid))) { continue }
        New-ADHealthFinding -Check $check -ObjectName $group.Name -DistinguishedName $group.DistinguishedName `
            -Detail 'Group has no members'
    }
}
```

`ADHealth/Private/Checks/Test-GroupOnlyDisabledMembers.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'GroupOnlyDisabledMembers'; Name = 'Groups with only disabled members'; Category = 'Groups'; Severity = 'Low'; Requires = @('Groups', 'Users', 'Computers') }

function Test-GroupOnlyDisabledMembers {
    # Members that are not collected users/computers (nested groups, contacts,
    # objects outside the search base) are ignored.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'GroupOnlyDisabledMembers'
    $enabledByDn = @{}  # PowerShell hashtables are case-insensitive
    foreach ($object in @($Data.Users) + @($Data.Computers)) {
        if ($object) { $enabledByDn[$object.DistinguishedName] = [bool]$object.Enabled }
    }
    foreach ($group in $Data.Groups) {
        $resolved = @(
            foreach ($memberDn in @($group.Members | Where-Object { $_ })) {
                if ($enabledByDn.ContainsKey($memberDn)) { $enabledByDn[$memberDn] }
            }
        )
        if ($resolved.Count -eq 0) { continue }
        if ($resolved -contains $true) { continue }
        New-ADHealthFinding -Check $check -ObjectName $group.Name -DistinguishedName $group.DistinguishedName `
            -Detail "All $($resolved.Count) user/computer member(s) disabled"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.Groups.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private/Checks Tests/Checks.Groups.Tests.ps1
git commit -m "Add empty group and disabled-only group checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: GPO and OU checks - UnlinkedGpo, EmptyOU

**Files:**
- Create: `ADHealth/Private/Checks/Test-UnlinkedGpo.ps1`
- Create: `ADHealth/Private/Checks/Test-EmptyOU.ps1`
- Test: `Tests/Checks.GpoOu.Tests.ps1`

**Interfaces:**
- Consumes: Task 1 registry/finding; Task 2 `Get-ADHealthDnParent`.
- Produces: `Test-UnlinkedGpo`, `Test-EmptyOU` (`-Data -Config` -> findings).

- [ ] **Step 1: Write the failing tests**

`Tests/Checks.GpoOu.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.GpoOu.Tests.ps1`
Expected: FAIL — `The term 'Test-UnlinkedGpo' is not recognized`.

- [ ] **Step 3: Implement the checks**

`ADHealth/Private/Checks/Test-UnlinkedGpo.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'UnlinkedGpo'; Name = 'Unlinked GPOs'; Category = 'GPOs'; Severity = 'Low'; Requires = @('Gpos', 'GpLinks') }

function Test-UnlinkedGpo {
    # A disabled link still counts as linked.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'UnlinkedGpo'
    $linked = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($guid in $Data.GpLinks) { [void]$linked.Add($guid) }
    foreach ($gpo in $Data.Gpos) {
        if ($linked.Contains($gpo.Guid)) { continue }
        if ($gpo.DisplayName) { $name = $gpo.DisplayName } else { $name = $gpo.Guid }
        New-ADHealthFinding -Check $check -ObjectName $name -DistinguishedName $gpo.DistinguishedName `
            -Detail "GPO '$name' is not linked anywhere"
    }
}
```

`ADHealth/Private/Checks/Test-EmptyOU.ps1`:

```powershell
Register-ADHealthCheck @{ Id = 'EmptyOU'; Name = 'Empty OUs'; Category = 'OUs'; Severity = 'Info'; Requires = @('OUs', 'AllObjectDNs') }

function Test-EmptyOU {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    $check = Get-ADHealthCheck -Id 'EmptyOU'
    $parents = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dn in $Data.AllObjectDNs) {
        $parent = Get-ADHealthDnParent -DistinguishedName $dn
        if ($parent) { [void]$parents.Add($parent) }
    }
    foreach ($ou in $Data.OUs) {
        if ($parents.Contains($ou.DistinguishedName)) { continue }
        New-ADHealthFinding -Check $check -ObjectName $ou.Name -DistinguishedName $ou.DistinguishedName `
            -Detail 'OU contains no objects'
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Checks.GpoOu.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private/Checks Tests/Checks.GpoOu.Tests.ps1
git commit -m "Add unlinked GPO and empty OU checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Check selection and runner

**Files:**
- Create: `ADHealth/Private/Invoke-ADHealthCheck.ps1`
- Test: `Tests/Runner.Tests.ps1`

**Interfaces:**
- Consumes: `Get-ADHealthCheck` (Task 1); all 12 registered checks (Tasks 3-7).
- Produces:
  - `Resolve-ADHealthCheckSelection [-Include <string[]>] [-Exclude <string[]>]` -> check definitions (registration order). Throws `"Unknown check Id '<id>'. Valid Ids: <comma list>"`. Id matching is case-insensitive.
  - `Invoke-ADHealthCheck -Checks <hashtable[]> -Data <Data> -Config <hashtable>` -> one Check result per check. Status `Skipped` with Reason `"Data not collected: <names>"` when a `Requires` property is `$null` or in `Data.Errors`; Status `Skipped` with Reason `"Check failed: <message>"` when the check throws.

- [ ] **Step 1: Write the failing tests**

`Tests/Runner.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force

    function Get-Ids { param($Checks) @($Checks | ForEach-Object { $_.Id } | Sort-Object) }
}

Describe 'Resolve-ADHealthCheckSelection' {
    It 'returns all 12 checks by default' {
        $ids = Get-Ids (Invoke-InModule Resolve-ADHealthCheckSelection)
        $ids | Should -Be @(
            'DisabledUserInGroups', 'EmptyGroup', 'EmptyOU', 'EolOperatingSystem', 'GroupOnlyDisabledMembers', 'NeverLoggedOnUser',
            'OldPassword', 'PasswordNeverExpires', 'PasswordNotRequired', 'StaleComputer', 'StaleUser', 'UnlinkedGpo'
        )
    }
    It 'keeps only included checks' {
        Get-Ids (Invoke-InModule Resolve-ADHealthCheckSelection @{ Include = @('StaleUser', 'EmptyGroup') }) | Should -Be @('EmptyGroup', 'StaleUser')
    }
    It 'drops excluded checks' {
        $ids = Get-Ids (Invoke-InModule Resolve-ADHealthCheckSelection @{ Exclude = @('StaleUser') })
        $ids.Count | Should -Be 11
        $ids | Should -Not -Contain 'StaleUser'
    }
    It 'matches Ids case-insensitively' {
        Get-Ids (Invoke-InModule Resolve-ADHealthCheckSelection @{ Include = @('staleuser') }) | Should -Be @('StaleUser')
    }
    It 'throws for an unknown Id and lists the valid ones' {
        { Invoke-InModule Resolve-ADHealthCheckSelection @{ Include = @('Nope') } } | Should -Throw "*Unknown check Id 'Nope'. Valid Ids:*StaleUser*"
        { Invoke-InModule Resolve-ADHealthCheckSelection @{ Exclude = @('Nope') } } | Should -Throw "*Unknown check Id 'Nope'*"
    }
}

Describe 'Invoke-ADHealthCheck' {
    BeforeAll {
        $staleUser = Invoke-InModule Get-ADHealthCheck @{ Id = 'StaleUser' }
        $neverExpires = Invoke-InModule Get-ADHealthCheck @{ Id = 'PasswordNeverExpires' }
        $emptyGroup = Invoke-InModule Get-ADHealthCheck @{ Id = 'EmptyGroup' }
    }

    It 'runs a check and returns its findings' {
        $data = New-FakeData -Users @(New-FakeUser -Name 'old' -LastLogonDaysAgo 200)
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($staleUser); Data = $data; Config = (New-FakeConfig) })
        $results.Count | Should -Be 1
        $results[0].CheckId | Should -Be 'StaleUser'
        $results[0].CheckName | Should -Be 'Stale enabled users'
        $results[0].Category | Should -Be 'Users'
        $results[0].Severity | Should -Be 'Medium'
        $results[0].Status | Should -Be 'Ran'
        @($results[0].Findings).Count | Should -Be 1
    }

    It 'reports Ran with no findings when nothing matches' {
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($staleUser); Data = (New-FakeData); Config = (New-FakeConfig) })
        $results[0].Status | Should -Be 'Ran'
        @($results[0].Findings).Count | Should -Be 0
    }

    It 'skips a check whose required data failed to collect' {
        $data = New-FakeData -Users $null -Errors @{ Users = 'Access denied' }
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($staleUser); Data = $data; Config = (New-FakeConfig) })
        $results[0].Status | Should -Be 'Skipped'
        $results[0].Reason | Should -Be 'Data not collected: Users'
    }

    It 'lists every missing data set in the reason' {
        $data = New-FakeData -Users $null -Computers $null
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($emptyGroup); Data = $data; Config = (New-FakeConfig) })
        $results[0].Reason | Should -Be 'Data not collected: Users, Computers'
    }

    It 'isolates a check that throws and keeps running the rest' {
        Mock -ModuleName ADHealth Test-StaleUser { throw 'boom' }
        $data = New-FakeData -Users @(New-FakeUser -Name 'svc' -PasswordNeverExpires $true)
        $results = @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @($staleUser, $neverExpires); Data = $data; Config = (New-FakeConfig) })
        $results[0].Status | Should -Be 'Skipped'
        $results[0].Reason | Should -Be 'Check failed: boom'
        @($results[0].Findings).Count | Should -Be 0
        $results[1].Status | Should -Be 'Ran'
        @($results[1].Findings).Count | Should -Be 1
    }

    It 'accepts an empty check list' {
        @(Invoke-InModule Invoke-ADHealthCheck @{ Checks = @(); Data = (New-FakeData); Config = (New-FakeConfig) }).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Runner.Tests.ps1`
Expected: FAIL — `The term 'Resolve-ADHealthCheckSelection' is not recognized`.

- [ ] **Step 3: Implement the runner**

`ADHealth/Private/Invoke-ADHealthCheck.ps1`:

```powershell
function Resolve-ADHealthCheckSelection {
    [CmdletBinding()]
    param(
        [string[]]$Include,
        [string[]]$Exclude
    )
    $all = @(Get-ADHealthCheck)
    $validIds = @($all | ForEach-Object { $_.Id })
    foreach ($id in @($Include) + @($Exclude)) {
        if ($id -and $validIds -notcontains $id) {
            throw "Unknown check Id '$id'. Valid Ids: $(($validIds | Sort-Object) -join ', ')"
        }
    }
    foreach ($check in $all) {
        if ($Include -and $Include -notcontains $check.Id) { continue }
        if ($Exclude -and $Exclude -contains $check.Id) { continue }
        $check
    }
}

function Invoke-ADHealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable[]]$Checks,
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][hashtable]$Config
    )
    foreach ($check in $Checks) {
        $status = 'Ran'
        $reason = ''
        $findings = @()
        $missing = @($check.Requires | Where-Object { $null -eq $Data.$_ -or $Data.Errors.ContainsKey($_) })
        if ($missing.Count -gt 0) {
            $status = 'Skipped'
            $reason = "Data not collected: $($missing -join ', ')"
        }
        else {
            try {
                $findings = @(& "Test-$($check.Id)" -Data $Data -Config $Config)
            }
            catch {
                $status = 'Skipped'
                $reason = "Check failed: $($_.Exception.Message)"
                $findings = @()
            }
        }
        [pscustomobject]@{
            PSTypeName = 'ADHealth.CheckResult'
            CheckId    = $check.Id
            CheckName  = $check.Name
            Category   = $check.Category
            Severity   = $check.Severity
            Status     = $status
            Reason     = $reason
            Findings   = $findings
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Runner.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private/Invoke-ADHealthCheck.ps1 Tests/Runner.Tests.ps1
git commit -m "Add check selection and runner with skip handling" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Collector

**Files:**
- Create: `ADHealth/Private/ConvertTo-ADHealthObject.ps1`
- Create: `ADHealth/Private/Get-ADHealthData.ps1`
- Test: `Tests/Collector.Tests.ps1`

**Interfaces:**
- Consumes: Task 2 `ConvertFrom-ADHealthFileTime`, `ConvertFrom-ADHealthGpLink`.
- Produces:
  - `ConvertTo-ADHealthUser|Computer|Group|OU|Gpo -InputObject <AD object>` -> normalized objects (Shared Contracts).
  - `Get-ADHealthData [-Server <string>] [-SearchBase <string>] [-Credential <pscredential>]` -> Data object. Throws `"Cannot contact a domain controller: <message>"` if DC discovery or `Get-ADDomain` fails. Other failures are recorded in `Errors` under the Data property name, and that property stays `$null`.

Note vs. spec: OUs are fetched without `gPLink` because GPO links are gathered by one `(gPLink=*)` query from the domain root (which covers the root and every OU regardless of `-SearchBase`) plus one under `CN=Sites` in the configuration partition.

- [ ] **Step 1: Write the failing tests**

`Tests/Collector.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Collector.Tests.ps1`
Expected: FAIL — `The term 'Get-ADHealthData' is not recognized`.

- [ ] **Step 3: Implement the normalizers**

`ADHealth/Private/ConvertTo-ADHealthObject.ps1`:

```powershell
# Convert AD module objects into the plain shapes the checks consume.

function ConvertTo-ADHealthUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)
    [pscustomobject]@{
        Name                 = [string]$InputObject.Name
        SamAccountName       = [string]$InputObject.SamAccountName
        DistinguishedName    = [string]$InputObject.DistinguishedName
        Enabled              = [bool]$InputObject.Enabled
        LastLogon            = (ConvertFrom-ADHealthFileTime -Value $InputObject.lastLogonTimestamp)
        PasswordLastSet      = (ConvertFrom-ADHealthFileTime -Value $InputObject.pwdLastSet)
        WhenCreated          = $InputObject.whenCreated
        UserAccountControl   = [int]$InputObject.userAccountControl
        PasswordNeverExpires = [bool]$InputObject.PasswordNeverExpires
        MemberOf             = @($InputObject.MemberOf | Where-Object { $_ })
        PrimaryGroupId       = [int]$InputObject.primaryGroupID
        Sid                  = [string]$InputObject.SID
    }
}

function ConvertTo-ADHealthComputer {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)
    [pscustomobject]@{
        Name                   = [string]$InputObject.Name
        DistinguishedName      = [string]$InputObject.DistinguishedName
        Enabled                = [bool]$InputObject.Enabled
        LastLogon              = (ConvertFrom-ADHealthFileTime -Value $InputObject.lastLogonTimestamp)
        PasswordLastSet        = (ConvertFrom-ADHealthFileTime -Value $InputObject.pwdLastSet)
        WhenCreated            = $InputObject.whenCreated
        OperatingSystem        = [string]$InputObject.operatingSystem
        OperatingSystemVersion = [string]$InputObject.operatingSystemVersion
        PrimaryGroupId         = [int]$InputObject.primaryGroupID
    }
}

function ConvertTo-ADHealthGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)
    [pscustomobject]@{
        Name                   = [string]$InputObject.Name
        DistinguishedName      = [string]$InputObject.DistinguishedName
        Members                = @($InputObject.member | Where-Object { $_ })
        Sid                    = [string]$InputObject.SID
        IsCriticalSystemObject = [bool]$InputObject.isCriticalSystemObject
    }
}

function ConvertTo-ADHealthOU {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)
    [pscustomobject]@{
        Name              = [string]$InputObject.Name
        DistinguishedName = [string]$InputObject.DistinguishedName
    }
}

function ConvertTo-ADHealthGpo {
    # A GPO container's name is its GUID in braces, e.g. {31B2F340-...}.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)
    [pscustomobject]@{
        Guid              = ([string]$InputObject.Name).Trim('{', '}').ToUpperInvariant()
        DisplayName       = [string]$InputObject.displayName
        DistinguishedName = [string]$InputObject.DistinguishedName
    }
}
```

- [ ] **Step 4: Implement the collector**

`ADHealth/Private/Get-ADHealthData.ps1`:

```powershell
function Get-ADHealthData {
    # Single read-only pass over AD. Each step after the domain lookup is
    # independent: a failure is recorded in Errors and the property stays $null.
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SearchBase,
        [pscredential]$Credential
    )
    $collectedAt = Get-Date
    $common = @{ ErrorAction = 'Stop' }
    if ($Credential) { $common.Credential = $Credential }

    try {
        if (-not $Server) {
            $dc = Get-ADDomainController -Discover -ErrorAction Stop
            $Server = @($dc.HostName)[0]
        }
        $common.Server = $Server
        $domain = Get-ADDomain @common
    }
    catch {
        throw "Cannot contact a domain controller: $($_.Exception.Message)"
    }

    $domainDn = [string]$domain.DistinguishedName
    if ($SearchBase) { $base = $SearchBase } else { $base = $domainDn }

    $data = [pscustomobject]@{
        Domain       = [pscustomobject]@{
            DnsRoot           = [string]$domain.DNSRoot
            DistinguishedName = $domainDn
            DomainSid         = [string]$domain.DomainSID
        }
        Server       = $Server
        SearchBase   = $base
        Users        = $null
        Computers    = $null
        Groups       = $null
        OUs          = $null
        AllObjectDNs = $null
        Gpos         = $null
        GpLinks      = $null
        CollectedAt  = $collectedAt
        Errors       = @{}
    }

    try {
        $properties = 'Enabled', 'lastLogonTimestamp', 'pwdLastSet', 'whenCreated', 'userAccountControl',
            'PasswordNeverExpires', 'PasswordNotRequired', 'MemberOf', 'primaryGroupID', 'SID'
        $data.Users = @(Get-ADUser -Filter '*' -SearchBase $base -Properties $properties @common |
            ForEach-Object { ConvertTo-ADHealthUser -InputObject $_ })
    }
    catch { $data.Errors['Users'] = $_.Exception.Message }

    try {
        $properties = 'Enabled', 'lastLogonTimestamp', 'pwdLastSet', 'whenCreated', 'operatingSystem',
            'operatingSystemVersion', 'primaryGroupID'
        $data.Computers = @(Get-ADComputer -Filter '*' -SearchBase $base -Properties $properties @common |
            ForEach-Object { ConvertTo-ADHealthComputer -InputObject $_ })
    }
    catch { $data.Errors['Computers'] = $_.Exception.Message }

    try {
        $data.Groups = @(Get-ADGroup -Filter '*' -SearchBase $base -Properties 'member', 'SID', 'isCriticalSystemObject' @common |
            ForEach-Object { ConvertTo-ADHealthGroup -InputObject $_ })
    }
    catch { $data.Errors['Groups'] = $_.Exception.Message }

    try {
        $data.OUs = @(Get-ADOrganizationalUnit -Filter '*' -SearchBase $base @common |
            ForEach-Object { ConvertTo-ADHealthOU -InputObject $_ })
    }
    catch { $data.Errors['OUs'] = $_.Exception.Message }

    try {
        $data.AllObjectDNs = @(Get-ADObject -Filter '*' -SearchBase $base @common |
            ForEach-Object { [string]$_.DistinguishedName })
    }
    catch { $data.Errors['AllObjectDNs'] = $_.Exception.Message }

    try {
        $data.Gpos = @(Get-ADObject -SearchBase "CN=Policies,CN=System,$domainDn" -SearchScope OneLevel `
                -LDAPFilter '(objectClass=groupPolicyContainer)' -Properties 'displayName' @common |
            ForEach-Object { ConvertTo-ADHealthGpo -InputObject $_ })
    }
    catch { $data.Errors['Gpos'] = $_.Exception.Message }

    # Links are read from the whole domain (not $base) so a narrow SearchBase
    # never makes a GPO look unlinked.
    try {
        $configNc = (Get-ADRootDSE @common).configurationNamingContext
        $linkHolders = @(Get-ADObject -SearchBase $domainDn -LDAPFilter '(gPLink=*)' -Properties 'gPLink' @common) +
            @(Get-ADObject -SearchBase "CN=Sites,$configNc" -LDAPFilter '(gPLink=*)' -Properties 'gPLink' @common)
        $data.GpLinks = @($linkHolders |
            ForEach-Object { ConvertFrom-ADHealthGpLink -GpLink $_.gPLink } |
            Sort-Object -Unique)
    }
    catch { $data.Errors['GpLinks'] = $_.Exception.Message }

    $data
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Collector.Tests.ps1`
Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add ADHealth/Private Tests/Collector.Tests.ps1
git commit -m "Add single-pass AD collector with per-step error capture" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Console renderer

**Files:**
- Create: `ADHealth/Private/Render/Format-ADHealthSummary.ps1`
- Create: `ADHealth/Private/Render/Write-ADHealthConsole.ps1`
- Modify: `Tests/Fixtures/Fixtures.ps1` (append `New-FakeFinding`, `New-FakeResult`)
- Test: `Tests/Render.Console.Tests.ps1`

**Interfaces:**
- Consumes: Check result and Data shapes (Shared Contracts).
- Produces:
  - `Sort-ADHealthResult -Results <object[]>` -> results ordered High, Medium, Low, Info, then by `CheckName`.
  - `Format-ADHealthSummary -Results <object[]>` -> rows `CheckId`, `Check`, `Category`, `Severity`, `Status`, `Count` (int or `$null` if skipped), `Display` (count as string, or `'Skipped'`), in sorted order.
  - `Get-ADHealthCountText -Items <object>` -> `'n/a'` if `$null`, else count as string.
  - `Write-ADHealthConsole -Data <Data> -Results <object[]> [-OutputFiles <string[]>]` -> writes to host only.
  - Fixtures: `New-FakeFinding [-CheckId] [-CheckName] [-Severity] [-ObjectName] [-Detail]`, `New-FakeResult [-Id] [-Name] [-Severity] [-Status] [-Reason] [-Findings]`.

- [ ] **Step 1: Add result fixtures**

Append to `Tests/Fixtures/Fixtures.ps1`:

```powershell
function New-FakeFinding {
    param(
        [string]$CheckId = 'StaleUser',
        [string]$CheckName = 'Stale enabled users',
        [string]$Severity = 'Medium',
        [string]$ObjectName = 'alice',
        [string]$Detail = 'Last logon 120 days ago'
    )
    [pscustomobject]@{
        CheckId           = $CheckId
        CheckName         = $CheckName
        Category          = 'Users'
        Severity          = $Severity
        ObjectName        = $ObjectName
        DistinguishedName = "CN=$ObjectName,OU=Staff,DC=lab,DC=local"
        Detail            = $Detail
    }
}

function New-FakeResult {
    param(
        [string]$Id = 'StaleUser',
        [string]$Name = 'Stale enabled users',
        [string]$Severity = 'Medium',
        [string]$Status = 'Ran',
        [string]$Reason = '',
        [object[]]$Findings = @()
    )
    [pscustomobject]@{
        CheckId   = $Id
        CheckName = $Name
        Category  = 'Users'
        Severity  = $Severity
        Status    = $Status
        Reason    = $Reason
        Findings  = $Findings
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/Render.Console.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot 'Fixtures/Fixtures.ps1')
    Import-Module (Join-Path $PSScriptRoot '../ADHealth/ADHealth.psd1') -Force
}

Describe 'Format-ADHealthSummary' {
    It 'orders rows by severity then name and labels skipped checks' {
        $results = @(
            New-FakeResult -Id 'EmptyOU' -Name 'Empty OUs' -Severity 'Info'
            New-FakeResult -Id 'OldPassword' -Name 'Old passwords' -Severity 'Low' -Status 'Skipped' -Reason 'Data not collected: Users'
            New-FakeResult -Id 'PasswordNotRequired' -Name 'Password not required' -Severity 'High' -Findings @((New-FakeFinding), (New-FakeFinding -ObjectName 'bob'))
            New-FakeResult -Id 'StaleUser' -Name 'Stale enabled users' -Severity 'Medium'
            New-FakeResult -Id 'EolOperatingSystem' -Name 'End-of-life operating systems' -Severity 'High'
        )
        $rows = @(Invoke-InModule Format-ADHealthSummary @{ Results = $results })
        @($rows | ForEach-Object { $_.Check }) | Should -Be @(
            'End-of-life operating systems', 'Password not required', 'Stale enabled users', 'Old passwords', 'Empty OUs'
        )
        $rows[0].Display | Should -Be '0'
        $rows[1].Count | Should -Be 2
        $rows[1].Display | Should -Be '2'
        $rows[3].Count | Should -BeNullOrEmpty
        $rows[3].Display | Should -Be 'Skipped'
    }
}

Describe 'Get-ADHealthCountText' {
    It 'returns n/a for null and the count otherwise' {
        Invoke-InModule Get-ADHealthCountText @{ Items = $null } | Should -Be 'n/a'
        Invoke-InModule Get-ADHealthCountText @{ Items = @() } | Should -Be '0'
        Invoke-InModule Get-ADHealthCountText @{ Items = @(1, 2, 3) } | Should -Be '3'
    }
}

Describe 'Write-ADHealthConsole' {
    BeforeEach {
        Mock -ModuleName ADHealth Write-Host { }
        $data = New-FakeData -Users @(New-FakeUser) -Gpos $null -Errors @{ Gpos = 'Access denied' }
        $results = @(
            New-FakeResult -Id 'PasswordNotRequired' -Name 'Password not required' -Severity 'High' -Findings @(New-FakeFinding)
            New-FakeResult -Id 'StaleUser' -Name 'Stale enabled users' -Severity 'Medium'
            New-FakeResult -Id 'UnlinkedGpo' -Name 'Unlinked GPOs' -Severity 'Low' -Status 'Skipped' -Reason 'Data not collected: Gpos'
        )
        Invoke-InModule Write-ADHealthConsole @{ Data = $data; Results = $results; OutputFiles = @('C:\reports\r.html') }
    }

    It 'prints a header with domain, DC and object counts' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*lab.local*' }
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*dc01.lab.local*2026-10-15 12:00*' }
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*1 users*n/a GPOs*' }
    }
    It 'colours rows by severity' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like 'Password not required*High*1' -and $ForegroundColor -eq 'Red' }
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like 'Stale enabled users*Medium*0' -and $ForegroundColor -eq 'Yellow' }
    }
    It 'greys out skipped checks and explains why' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like 'Unlinked GPOs*Skipped' -and $ForegroundColor -eq 'DarkGray' }
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*Unlinked GPOs: Data not collected: Gpos*' }
    }
    It 'lists collection errors in yellow' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*Gpos*Access denied*' -and $ForegroundColor -eq 'Yellow' }
    }
    It 'lists the files written' {
        Should -Invoke Write-Host -ModuleName ADHealth -ParameterFilter { "$Object" -like '*C:\reports\r.html*' }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Render.Console.Tests.ps1`
Expected: FAIL — `The term 'Format-ADHealthSummary' is not recognized`.

- [ ] **Step 4: Implement the summary helpers**

`ADHealth/Private/Render/Format-ADHealthSummary.ps1`:

```powershell
function Sort-ADHealthResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results
    )
    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $Results | Sort-Object @{ Expression = { $rank[$_.Severity] } }, @{ Expression = { $_.CheckName } }
}

function Format-ADHealthSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results
    )
    foreach ($result in (Sort-ADHealthResult -Results $Results)) {
        if ($result.Status -eq 'Ran') {
            $count = @($result.Findings).Count
            $display = [string]$count
        }
        else {
            $count = $null
            $display = 'Skipped'
        }
        [pscustomobject]@{
            CheckId  = $result.CheckId
            Check    = $result.CheckName
            Category = $result.Category
            Severity = $result.Severity
            Status   = $result.Status
            Count    = $count
            Display  = $display
        }
    }
}

function Get-ADHealthCountText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Items
    )
    if ($null -eq $Items) { return 'n/a' }
    [string]@($Items).Count
}
```

- [ ] **Step 5: Implement the console writer**

`ADHealth/Private/Render/Write-ADHealthConsole.ps1`:

```powershell
function Write-ADHealthConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [string[]]$OutputFiles = @()
    )
    $colors = @{ High = 'Red'; Medium = 'Yellow'; Low = 'Cyan'; Info = 'Gray' }
    $rowFormat = '{0,-34} {1,-8} {2,7}'

    Write-Host ''
    Write-Host "AD Health Report - $($Data.Domain.DnsRoot)" -ForegroundColor White
    Write-Host "DC: $($Data.Server)   Collected: $($Data.CollectedAt.ToString('yyyy-MM-dd HH:mm'))"
    Write-Host ('Objects: {0} users, {1} computers, {2} groups, {3} OUs, {4} GPOs' -f
        (Get-ADHealthCountText -Items $Data.Users), (Get-ADHealthCountText -Items $Data.Computers),
        (Get-ADHealthCountText -Items $Data.Groups), (Get-ADHealthCountText -Items $Data.OUs),
        (Get-ADHealthCountText -Items $Data.Gpos))
    Write-Host ''
    Write-Host ($rowFormat -f 'Check', 'Severity', 'Count')
    Write-Host ($rowFormat -f ('-' * 34), ('-' * 8), ('-' * 7))

    foreach ($row in (Format-ADHealthSummary -Results $Results)) {
        if ($row.Status -eq 'Skipped') { $color = 'DarkGray' } else { $color = $colors[$row.Severity] }
        Write-Host ($rowFormat -f $row.Check, $row.Severity, $row.Display) -ForegroundColor $color
    }

    $skipped = @($Results | Where-Object { $_.Status -eq 'Skipped' })
    if ($skipped.Count -gt 0) {
        Write-Host ''
        foreach ($result in $skipped) {
            Write-Host "Skipped $($result.CheckName): $($result.Reason)" -ForegroundColor DarkGray
        }
    }

    if ($Data.Errors.Count -gt 0) {
        Write-Host ''
        foreach ($key in ($Data.Errors.Keys | Sort-Object)) {
            Write-Host "Collection error ($key): $($Data.Errors[$key])" -ForegroundColor Yellow
        }
    }

    if ($OutputFiles.Count -gt 0) {
        Write-Host ''
        foreach ($file in $OutputFiles) {
            Write-Host "Written: $file" -ForegroundColor Green
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Render.Console.Tests.ps1`
Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add ADHealth/Private/Render Tests/Fixtures/Fixtures.ps1 Tests/Render.Console.Tests.ps1
git commit -m "Add console summary renderer" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: HTML renderer

**Files:**
- Create: `ADHealth/Private/Render/Export-ADHealthHtml.ps1`
- Test: `Tests/Render.Html.Tests.ps1`

**Interfaces:**
- Consumes: `Sort-ADHealthResult`, `Format-ADHealthSummary`, `Get-ADHealthCountText` (Task 10); Data, Check result, Config shapes.
- Produces: `ConvertTo-ADHealthHtmlText -Value <object>` -> HTML-encoded string; `Export-ADHealthHtml -Data <Data> -Results <object[]> -Config <hashtable> -Path <full path>` writes a UTF-8 (no BOM) file and returns nothing.

- [ ] **Step 1: Write the failing tests**

`Tests/Render.Html.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Render.Html.Tests.ps1`
Expected: FAIL — `The term 'Export-ADHealthHtml' is not recognized`.

- [ ] **Step 3: Implement the HTML renderer**

`ADHealth/Private/Render/Export-ADHealthHtml.ps1`:

```powershell
function ConvertTo-ADHealthHtmlText {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )
    [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Export-ADHealthHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$Path
    )
    $style = @'
:root { color-scheme: light dark; --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0; --card: #f6f8fa;
  --high: #cf222e; --medium: #9a6700; --low: #0969da; --info: #59636e; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0d1117; --fg: #e6edf3; --muted: #9198a1; --line: #3d444d; --card: #151b23;
    --high: #ff7b72; --medium: #d29922; --low: #58a6ff; --info: #9198a1; }
}
body { margin: 0; padding: 24px 16px; background: var(--bg); color: var(--fg); font: 14px/1.5 "Segoe UI", system-ui, sans-serif; }
main { max-width: 1100px; margin: 0 auto; }
h1 { margin: 0 0 4px; font-size: 24px; }
h2 { margin: 24px 0 8px; font-size: 18px; }
.meta { color: var(--muted); margin: 0; }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; margin: 16px 0; }
.tile { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 12px; }
.tile .n { font-size: 28px; font-weight: 600; }
.tile .l { color: var(--muted); }
.sev-High { color: var(--high); } .sev-Medium { color: var(--medium); } .sev-Low { color: var(--low); } .sev-Info { color: var(--info); }
.scroll { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { color: var(--muted); font-weight: 600; }
td.num { text-align: right; }
td.dn { color: var(--muted); font-size: 12px; word-break: break-all; }
a { color: var(--low); }
details { border: 1px solid var(--line); border-radius: 8px; margin: 8px 0; padding: 0 12px; }
summary { cursor: pointer; padding: 10px 0; font-weight: 600; }
.count { color: var(--muted); font-weight: 400; }
.note { color: var(--muted); }
footer { margin-top: 32px; color: var(--muted); font-size: 12px; }
'@

    $sorted = @(Sort-ADHealthResult -Results $Results)
    $totals = [ordered]@{ High = 0; Medium = 0; Low = 0; Info = 0 }
    foreach ($result in $sorted) {
        if ($result.Status -eq 'Ran') { $totals[$result.Severity] += @($result.Findings).Count }
    }
    $domainText = ConvertTo-ADHealthHtmlText $Data.Domain.DnsRoot

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine("<title>AD Health - $domainText</title>")
    [void]$sb.AppendLine("<style>$style</style></head><body><main>")

    [void]$sb.AppendLine("<h1>AD Health Report - $domainText</h1>")
    [void]$sb.AppendLine(('<p class="meta">DC {0} &middot; collected {1} &middot; search base {2}</p>' -f
        (ConvertTo-ADHealthHtmlText $Data.Server), $Data.CollectedAt.ToString('yyyy-MM-dd HH:mm'),
        (ConvertTo-ADHealthHtmlText $Data.SearchBase)))
    [void]$sb.AppendLine(('<p class="meta">{0} users &middot; {1} computers &middot; {2} groups &middot; {3} OUs &middot; {4} GPOs</p>' -f
        (Get-ADHealthCountText -Items $Data.Users), (Get-ADHealthCountText -Items $Data.Computers),
        (Get-ADHealthCountText -Items $Data.Groups), (Get-ADHealthCountText -Items $Data.OUs),
        (Get-ADHealthCountText -Items $Data.Gpos)))

    [void]$sb.AppendLine('<div class="tiles">')
    foreach ($severity in $totals.Keys) {
        [void]$sb.AppendLine("<div class=""tile""><div class=""n sev-$severity"">$($totals[$severity])</div><div class=""l"">$severity findings</div></div>")
    }
    [void]$sb.AppendLine('</div>')

    [void]$sb.AppendLine('<h2>Summary</h2><div class="scroll"><table><thead><tr><th>Check</th><th>Category</th><th>Severity</th><th>Count</th></tr></thead><tbody>')
    foreach ($row in (Format-ADHealthSummary -Results $sorted)) {
        [void]$sb.AppendLine(('<tr><td><a href="#check-{0}">{1}</a></td><td>{2}</td><td class="sev-{3}">{3}</td><td class="num">{4}</td></tr>' -f
            $row.CheckId, (ConvertTo-ADHealthHtmlText $row.Check), (ConvertTo-ADHealthHtmlText $row.Category), $row.Severity, $row.Display))
    }
    [void]$sb.AppendLine('</tbody></table></div>')

    [void]$sb.AppendLine('<h2>Details</h2>')
    foreach ($result in $sorted) {
        $findings = @($result.Findings)
        if ($result.Status -eq 'Ran') { $label = [string]$findings.Count } else { $label = 'Skipped' }
        if ($result.Status -eq 'Ran' -and $result.Severity -eq 'High' -and $findings.Count -gt 0) { $open = ' open' } else { $open = '' }
        [void]$sb.AppendLine("<details id=""check-$($result.CheckId)""$open>")
        [void]$sb.AppendLine(('<summary><span class="sev-{0}">{0}</span> {1} <span class="count">({2})</span></summary>' -f
            $result.Severity, (ConvertTo-ADHealthHtmlText $result.CheckName), $label))
        if ($result.Status -ne 'Ran') {
            [void]$sb.AppendLine("<p class=""note"">$(ConvertTo-ADHealthHtmlText $result.Reason)</p>")
        }
        elseif ($findings.Count -eq 0) {
            [void]$sb.AppendLine('<p class="note">No findings.</p>')
        }
        else {
            [void]$sb.AppendLine('<div class="scroll"><table><thead><tr><th>Object</th><th>Detail</th><th>Distinguished name</th></tr></thead><tbody>')
            foreach ($finding in $findings) {
                [void]$sb.AppendLine(('<tr><td>{0}</td><td>{1}</td><td class="dn">{2}</td></tr>' -f
                    (ConvertTo-ADHealthHtmlText $finding.ObjectName), (ConvertTo-ADHealthHtmlText $finding.Detail),
                    (ConvertTo-ADHealthHtmlText $finding.DistinguishedName)))
            }
            [void]$sb.AppendLine('</tbody></table></div>')
        }
        [void]$sb.AppendLine('</details>')
    }

    [void]$sb.AppendLine('<footer>')
    [void]$sb.AppendLine(('<p>Thresholds: Stale after {0} days; never-logged-on grace {1} days; password age {2} days.</p>' -f
        $Config.StaleDays, $Config.NeverLoggedOnGraceDays, $Config.PasswordAgeDays))
    [void]$sb.AppendLine('<p>Last-logon ages come from lastLogonTimestamp, which replicates with up to a 14-day lag, so they are approximate.</p>')
    if ($Data.Errors.Count -gt 0) {
        [void]$sb.AppendLine('<p>Collection errors:</p><ul>')
        foreach ($key in ($Data.Errors.Keys | Sort-Object)) {
            [void]$sb.AppendLine("<li>$(ConvertTo-ADHealthHtmlText $key): $(ConvertTo-ADHealthHtmlText $Data.Errors[$key])</li>")
        }
        [void]$sb.AppendLine('</ul>')
    }
    [void]$sb.AppendLine(('<p>Generated {0} from {1}. Read-only report; nothing in AD was changed.</p>' -f
        $Data.CollectedAt.ToString('yyyy-MM-dd HH:mm'), (ConvertTo-ADHealthHtmlText $Data.Server)))
    [void]$sb.AppendLine('</footer></main></body></html>')

    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Render.Html.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private/Render/Export-ADHealthHtml.ps1 Tests/Render.Html.Tests.ps1
git commit -m "Add self-contained HTML report renderer" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: CSV renderer

**Files:**
- Create: `ADHealth/Private/Render/Export-ADHealthCsv.ps1`
- Test: `Tests/Render.Csv.Tests.ps1`

**Interfaces:**
- Consumes: Check result and Finding shapes.
- Produces: `Export-ADHealthCsv -Results <object[]> -Directory <full path> -Prefix <string>` -> full paths of written files (one per `Ran` check with at least one finding, named `<Prefix>_<CheckId>.csv`).

- [ ] **Step 1: Write the failing tests**

`Tests/Render.Csv.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Render.Csv.Tests.ps1`
Expected: FAIL — `The term 'Export-ADHealthCsv' is not recognized`.

- [ ] **Step 3: Implement the CSV renderer**

`ADHealth/Private/Render/Export-ADHealthCsv.ps1`:

```powershell
function Export-ADHealthCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Prefix
    )
    foreach ($result in $Results) {
        $findings = @($result.Findings)
        if ($result.Status -ne 'Ran' -or $findings.Count -eq 0) { continue }
        $path = Join-Path $Directory "$($Prefix)_$($result.CheckId).csv"
        $findings |
            Select-Object CheckId, CheckName, Category, Severity, ObjectName, DistinguishedName, Detail |
            Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
        $path
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Render.Csv.Tests.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add ADHealth/Private/Render/Export-ADHealthCsv.ps1 Tests/Render.Csv.Tests.ps1
git commit -m "Add per-check CSV export" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Public command, prerequisites, README

**Files:**
- Create: `ADHealth/Private/Prerequisites.ps1`
- Create: `ADHealth/Public/Invoke-ADHealthReport.ps1`
- Create: `README.md`
- Create: `.gitignore`
- Test: `Tests/Invoke-ADHealthReport.Tests.ps1`

**Interfaces:**
- Consumes: everything above — `Resolve-ADHealthCheckSelection`, `Invoke-ADHealthCheck` (Task 8), `Get-ADHealthData` (Task 9), `Write-ADHealthConsole` (Task 10), `Export-ADHealthHtml` (Task 11), `Export-ADHealthCsv` (Task 12).
- Produces:
  - `Assert-ADHealthPrerequisite` — returns if `ActiveDirectory` is loaded; imports it if available; otherwise throws a message containing `RSAT`.
  - `Resolve-ADHealthOutputPath -Path <string>` -> full directory path; creates it if missing; throws `"Output path '<full>' is not writable: <message>"`.
  - `Invoke-ADHealthReport` (exported) with the spec's parameters.

- [ ] **Step 1: Write the failing tests**

`Tests/Invoke-ADHealthReport.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Invoke-ADHealthReport.Tests.ps1`
Expected: FAIL — `Module surface` finds no exported functions; the others fail with `Invoke-ADHealthReport is not recognized`.

- [ ] **Step 3: Implement the prerequisites**

`ADHealth/Private/Prerequisites.ps1`:

```powershell
function Assert-ADHealthPrerequisite {
    [CmdletBinding()]
    param()
    if (Get-Module -Name ActiveDirectory) { return }
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw ('The ActiveDirectory PowerShell module was not found. Install RSAT: on Windows 10/11 run ' +
            '"Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"; ' +
            'on Windows Server run "Install-WindowsFeature RSAT-AD-PowerShell".')
    }
    # Skip mounting the AD: drive; it slows import and is not needed.
    $env:ADPS_LoadDefaultDrive = 0
    Import-Module ActiveDirectory -ErrorAction Stop -Verbose:$false
}

function Resolve-ADHealthOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    try {
        if (-not (Test-Path -LiteralPath $full -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $full -Force -ErrorAction Stop
        }
        $probe = Join-Path $full ".adhealth-write-test-$([guid]::NewGuid().ToString('N')).tmp"
        [System.IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
    }
    catch {
        throw "Output path '$full' is not writable: $($_.Exception.Message)"
    }
    $full
}
```

- [ ] **Step 4: Implement the public command**

`ADHealth/Public/Invoke-ADHealthReport.ps1`:

```powershell
function Invoke-ADHealthReport {
    <#
    .SYNOPSIS
    Reports Active Directory object hygiene problems. Read-only.

    .DESCRIPTION
    Reads users, computers, groups, OUs and GPOs from AD in a single pass, runs
    12 hygiene checks, prints a summary to the console and writes an HTML
    report (and optionally one CSV per check with findings).

    .EXAMPLE
    Invoke-ADHealthReport -OutputPath .\reports

    .EXAMPLE
    Invoke-ADHealthReport -SearchBase 'OU=Staff,DC=lab,DC=local' -StaleDays 60 -Csv

    .EXAMPLE
    Invoke-ADHealthReport -Include StaleUser, StaleComputer -NoHtml -PassThru | Format-Table ObjectName, Detail
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SearchBase,
        [pscredential]$Credential,
        [string]$OutputPath = '.',
        [switch]$Csv,
        [switch]$NoHtml,
        [ValidateRange(1, 36500)][int]$StaleDays = 90,
        [ValidateRange(1, 36500)][int]$NeverLoggedOnGraceDays = 30,
        [ValidateRange(1, 36500)][int]$PasswordAgeDays = 365,
        [string[]]$Include,
        [string[]]$Exclude,
        [switch]$PassThru
    )
    Assert-ADHealthPrerequisite
    $checks = @(Resolve-ADHealthCheckSelection -Include $Include -Exclude $Exclude)
    if ($Csv -or -not $NoHtml) {
        $outputDirectory = Resolve-ADHealthOutputPath -Path $OutputPath
    }
    $config = @{
        StaleDays              = $StaleDays
        NeverLoggedOnGraceDays = $NeverLoggedOnGraceDays
        PasswordAgeDays        = $PasswordAgeDays
    }

    $data = Get-ADHealthData -Server $Server -SearchBase $SearchBase -Credential $Credential
    $results = @(Invoke-ADHealthCheck -Checks $checks -Data $data -Config $config)

    $prefix = 'ADHealth_{0}_{1}' -f $data.Domain.DnsRoot, $data.CollectedAt.ToString('yyyyMMdd-HHmm')
    $files = @()
    if (-not $NoHtml) {
        $htmlPath = Join-Path $outputDirectory "$prefix.html"
        Export-ADHealthHtml -Data $data -Results $results -Config $config -Path $htmlPath
        $files += $htmlPath
    }
    if ($Csv) {
        $files += @(Export-ADHealthCsv -Results $results -Directory $outputDirectory -Prefix $prefix)
    }

    Write-ADHealthConsole -Data $data -Results $results -OutputFiles $files

    if ($PassThru) {
        foreach ($result in $results) { $result.Findings }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1 -Path Tests/Invoke-ADHealthReport.Tests.ps1`
Expected: PASS.

- [ ] **Step 6: Add README and .gitignore**

`.gitignore`:

```
reports/
```

`README.md`:

````markdown
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
````

- [ ] **Step 7: Run the full suite**

Run: `pwsh -NoProfile -File Tests/Invoke-Tests.ps1`
Expected: PASS, 0 failed.

- [ ] **Step 8: Commit**

```powershell
git add ADHealth Tests/Invoke-ADHealthReport.Tests.ps1 README.md .gitignore
git commit -m "Add Invoke-ADHealthReport command, prerequisites and README" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Smoke test against the lab domain

**Files:** none created (reports go to the git-ignored `reports/`).

**Interfaces:**
- Consumes: the finished module.
- Produces: a verified run against THENEWTONLAB.

- [ ] **Step 1: Run on Windows PowerShell 5.1 and PowerShell 7**

```powershell
powershell.exe -NoProfile -Command "Import-Module .\ADHealth\ADHealth.psd1 -Force; Invoke-ADHealthReport -OutputPath .\reports -Csv"
pwsh -NoProfile -Command "Import-Module .\ADHealth\ADHealth.psd1 -Force; Invoke-ADHealthReport -OutputPath .\reports -Csv"
```

Expected: both print the header, a 12-row table, no collection errors, and `Written:` lines; the HTML and CSVs exist in `reports\`.

- [ ] **Step 2: Cross-check StaleUser against a built-in cmdlet**

In an interactive `pwsh` session at the repo root:

```powershell
Import-Module .\ADHealth\ADHealth.psd1 -Force
$ours = @(Invoke-ADHealthReport -Include StaleUser -NoHtml -PassThru)
$ref = @(Search-ADAccount -AccountInactive -UsersOnly -TimeSpan 90.00:00:00 | Where-Object { $_.Enabled -and $_.LastLogonDate })
'ours={0} reference={1}' -f $ours.Count, $ref.Count
Compare-Object ($ours | ForEach-Object ObjectName) ($ref | ForEach-Object SamAccountName)
```

Expected: the counts match or differ only by built-in accounts (`krbtgt`, `Guest`, etc.) or users exactly at 90 days. Investigate any other difference.

- [ ] **Step 3: Review the HTML**

Open the newest `reports\ADHealth_*.html` in a browser. Check that: the tiles add up to the summary counts; High sections with findings start open; light and dark mode are both readable; long DNs wrap rather than overflow on a narrow window.

- [ ] **Step 4: Record the outcome**

Report the result to the user (counts per check, any discrepancies and their explanation). No commit unless a defect was found and fixed, in which case add a regression test in the relevant test file first, fix it, rerun `pwsh -NoProfile -File Tests/Invoke-Tests.ps1`, and commit.
