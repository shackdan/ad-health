# AD Health Report — Design

**Date:** 2026-10-15
**Status:** Approved in brainstorming, pending spec review

## Purpose

A personal, on-demand admin tool that queries Active Directory objects and reports hygiene problems (stale accounts, risky password flags, empty groups, unlinked GPOs, etc.) so the admin can clean them up.

**Success:** one command run on a domain-joined machine produces an accurate, readable list of cleanup items — a console summary plus an HTML report — without modifying AD.

### In scope (v1)
- PowerShell module using the RSAT `ActiveDirectory` module.
- Read-only LDAP queries with the running user's normal domain-user rights (optional `-Credential`).
- 12 object-hygiene checks (below) with configurable thresholds.
- Console summary, self-contained HTML report, optional CSV export.

### Out of scope (v1)
- Any write/remediation action against AD.
- Infrastructure health (replication, FSMO, DNS, SYSVOL, time sync).
- Security checks (privileged groups, SPNs, delegation, AdminCount) — candidate for v2.
- History / trend tracking across runs, scheduling, emailing.
- Config files (thresholds are parameters only).
- Dependence on the GroupPolicy (GPMC) module.

## Architecture

Approach: **collect once, pure-function checks.** A single collector pulls all needed data from AD; each check is a pure function over that data returning standard finding objects; renderers consume findings.

```
ad-health/
  ADHealth/
    ADHealth.psd1                  # module manifest
    ADHealth.psm1                  # loader: dot-sources Private/, Checks/, Render/, Public/
    Public/
      Invoke-ADHealthReport.ps1    # the only exported command
    Private/
      Get-ADHealthData.ps1         # collector: single pass over AD
      New-ADHealthFinding.ps1      # builds a finding object
      Register-ADHealthCheck.ps1   # adds a check's metadata to the module-scoped registry
      Get-ADHealthCheck.ps1        # returns registered checks
      EolOperatingSystems.ps1      # data table of EOL OS name patterns
      Checks/
        Test-StaleUser.ps1 ... (one file per check, 12 total)
      Render/
        Write-ADHealthConsole.ps1
        Export-ADHealthHtml.ps1
        Export-ADHealthCsv.ps1
  Tests/                           # Pester 5
    Fixtures/                      # fake AD object builders
  docs/
```

### Data flow
1. `Invoke-ADHealthReport` verifies the `ActiveDirectory` module is available; if not, throws a clear error telling the user to install RSAT.
2. Builds `$Config` hashtable from parameters.
3. Calls `Get-ADHealthData` → returns one data object.
4. Discovers checks, filters by `-Include` / `-Exclude`, runs each as `Test-X -Data $data -Config $config`.
5. Passes combined findings + check status to renderers.
6. With `-PassThru`, emits finding objects to the pipeline.

### Check registration
Each file in `Checks/` defines one function `Test-<Id>` with a metadata block exposed via a companion hashtable registered at load time:

```powershell
Register-ADHealthCheck @{ Id = 'StaleUser'; Name = 'Stale enabled users'; Category = 'Users'; Severity = 'Medium'; Requires = @('Users') }
```

`Requires` lists data-object properties the check depends on; if any of them failed to collect, the check is reported as **Skipped** rather than run. Adding a check = adding one file; no central list to edit.

### Finding object
`[pscustomobject]` with: `CheckId`, `CheckName`, `Category`, `Severity` (`High` | `Medium` | `Low` | `Info`), `ObjectName`, `DistinguishedName`, `Detail` (human-readable, e.g. "Last logon 214 days ago").

### Determinism
Checks compare dates against `$Data.CollectedAt`, never `Get-Date`, so tests are deterministic.

## Command interface

```powershell
Invoke-ADHealthReport
    [-Server <string>]                 # target DC; default: discovered DC for current domain
    [-SearchBase <string>]             # limit user/computer/group/OU scope; default: domain root
    [-Credential <pscredential>]
    [-OutputPath <string>]             # default: current directory
    [-Csv]                             # also export one CSV per check that has findings
    [-NoHtml]                          # skip HTML report
    [-StaleDays <int> = 90]
    [-NeverLoggedOnGraceDays <int> = 30]
    [-PasswordAgeDays <int> = 365]
    [-Include <string[]>]              # check Ids to run (default: all)
    [-Exclude <string[]>]              # check Ids to skip
    [-PassThru]
```

- HTML file: `ADHealth_<domain>_<yyyyMMdd-HHmm>.html` in `-OutputPath`; full path printed at the end.
- CSV files: `ADHealth_<domain>_<yyyyMMdd-HHmm>_<CheckId>.csv`, only for checks with findings.
- Unknown Ids in `-Include`/`-Exclude` produce a terminating error listing valid Ids.
- `-Server`, `-SearchBase`, `-Credential` are passed through to all `Get-AD*` calls (`-SearchBase` does not apply to GPO containers or Sites, which live outside the domain naming context's OU tree).

## Collector — `Get-ADHealthData`

Returns:

| Property | Source | Properties requested |
|---|---|---|
| `Domain` | `Get-ADDomain` | DNSRoot, DistinguishedName, DomainSID |
| `Users` | `Get-ADUser -Filter *` | Enabled, lastLogonTimestamp, pwdLastSet, whenCreated, userAccountControl, PasswordNeverExpires, PasswordNotRequired, MemberOf, primaryGroupID, SID |
| `Computers` | `Get-ADComputer -Filter *` | Enabled, lastLogonTimestamp, pwdLastSet, whenCreated, operatingSystem, operatingSystemVersion, primaryGroupID |
| `Groups` | `Get-ADGroup -Filter *` | member, SID, isCriticalSystemObject |
| `OUs` | `Get-ADOrganizationalUnit -Filter *` | gPLink |
| `AllObjectDNs` | `Get-ADObject -Filter * -Properties DistinguishedName` (scoped to SearchBase) | DN only — used to compute empty OUs |
| `Gpos` | `Get-ADObject -SearchBase "CN=Policies,CN=System,<domainDN>" -Filter "objectClass -eq 'groupPolicyContainer'"` | displayName, name (GUID) |
| `GpLinks` | `gPLink` from domain root object, all OUs, and `Get-ADObject` on site objects in `CN=Sites,CN=Configuration,<forestDN>` | gPLink (parsed into GUID list) |
| `CollectedAt` | `Get-Date` at start of collection | — |
| `Errors` | hashtable: property name → error message | — |

- Each row in the table is collected in its own `try/catch`; on failure the property is set to `$null` and the error recorded in `Errors`.
- `lastLogonTimestamp` and `pwdLastSet` are converted from FILETIME to `[datetime]` (0 / missing → `$null`) once in the collector.
- `gPLink` parsing: extract GUIDs from `[LDAP://cn={GUID},cn=policies,...;N]` segments, case-insensitive.

## Checks

All user checks exclude built-in accounts: `krbtgt`, `Guest`, `DefaultAccount`, `WDAGUtilityAccount` (matched by well-known RID 502, 501, 503, 504 relative to the domain SID). "Days ago" = `($Data.CollectedAt - <date>).Days`. Threshold comparisons are strictly greater than (an object exactly at the threshold is **not** flagged).

| # | Id | Category | Logic | Severity | Detail text |
|---|---|---|---|---|---|
| 1 | StaleUser | Users | Enabled; lastLogonTimestamp not null and older than StaleDays | Medium | "Last logon N days ago" |
| 2 | NeverLoggedOnUser | Users | Enabled; lastLogonTimestamp null; whenCreated older than NeverLoggedOnGraceDays | Medium | "Never logged on; created N days ago" |
| 3 | PasswordNeverExpires | Users | Enabled; PasswordNeverExpires true | Medium | "Password set to never expire" |
| 4 | PasswordNotRequired | Users | Enabled; PASSWD_NOTREQD (0x20) set in userAccountControl | High | "Password not required flag set" |
| 5 | OldPassword | Users | Enabled; PasswordNeverExpires false; pwdLastSet not null and older than PasswordAgeDays | Low | "Password last set N days ago" |
| 6 | DisabledUserInGroups | Users | Disabled; MemberOf non-empty (primary group is not in MemberOf, so it is naturally ignored) | Low | "Member of N group(s): <first 3 names>…" |
| 7 | StaleComputer | Computers | Enabled; lastLogonTimestamp (null treated as stale only if whenCreated older than StaleDays) **and** pwdLastSet both older than StaleDays | Medium | "Last logon N days ago; password set M days ago" |
| 8 | EolOperatingSystem | Computers | Enabled; operatingSystem matches a pattern in `EolOperatingSystems.ps1` | High | "<operatingSystem>" |
| 9 | EmptyGroup | Groups | member empty; not isCriticalSystemObject; not under `CN=Builtin`; SID RID not used as any user/computer primaryGroupID | Info | "Group has no members" |
| 10 | GroupOnlyDisabledMembers | Groups | member non-empty; at least one member resolves (by DN) to a collected user/computer; every resolved user/computer member is disabled; members that resolve to groups or unknown objects are ignored | Low | "All N user/computer member(s) disabled" |
| 11 | UnlinkedGpo | GPOs | GPO GUID not present in any parsed gPLink | Low | "GPO '<displayName>' is not linked anywhere" |
| 12 | EmptyOU | OUs | No DN in AllObjectDNs has this OU as its immediate parent | Info | "OU contains no objects" |

**EOL OS list (initial):** Windows XP, Windows Vista, Windows 7, Windows 8, Windows 8.1, Windows Server 2003, Windows Server 2008 (incl. R2), Windows Server 2012 (incl. R2). Stored as wildcard patterns in one array; updating it is a one-line change.

## Output

### Console (`Write-ADHealthConsole`)
- Header: domain, DC queried, collection time, object counts (users, computers, groups, OUs, GPOs).
- Table: Check · Severity · Count, sorted by severity (High → Info) then name. Severity coloured (High red, Medium yellow, Low cyan, Info gray). Skipped checks shown in dark gray with "Skipped" in place of count.
- Collection errors listed in yellow.
- Footer: HTML / CSV paths written.

### HTML (`Export-ADHealthHtml`)
- Single self-contained file: inline CSS, no JavaScript dependencies, no external resources.
- Summary tiles: count of findings per severity.
- Summary table (same as console).
- One `<details>` section per check (open by default if it has High findings), containing a table of ObjectName · DistinguishedName · Detail.
- Footer: thresholds used, `lastLogonTimestamp` replication caveat (~14-day lag), collection errors, generation time.
- Every interpolated value passes through `[System.Net.WebUtility]::HtmlEncode`.

### CSV (`Export-ADHealthCsv`)
- `Export-Csv -NoTypeInformation -Encoding utf8`, one file per check with findings, columns = finding object properties.

## Error handling
- Missing `ActiveDirectory` module → terminating error with RSAT install hint.
- Cannot reach a DC / `Get-ADDomain` fails → terminating error (nothing useful can run).
- Any other collection step fails → recorded in `Errors`; dependent checks Skipped; run continues.
- A check throws at runtime → caught, check reported as Skipped with the error message; other checks continue.
- Output path not writable → terminating error before collection starts.

## Testing
Pester 5, runnable without AD (`Invoke-Pester ./Tests`).

- **Fixtures:** builder functions (`New-FakeUser`, `New-FakeComputer`, `New-FakeGroup`, `New-FakeData`) producing objects shaped like collector output with sensible defaults and overridable properties.
- **Per check:** positive case, negative case, boundary at exactly the threshold (not flagged), null-date handling, and built-in exclusions where relevant.
- **Collector:** `Mock` `Get-ADUser`/`Get-ADComputer`/etc. to verify requested property lists, FILETIME conversion, gPLink parsing, and that a failing call populates `Errors` without throwing.
- **Runner:** Include/Exclude filtering, unknown Id error, Skipped when `Requires` data is missing, a throwing check is isolated.
- **Renderers:** HTML contains expected sections; an object name containing `<script>` is encoded; CSV written only for checks with findings.
- **Manual smoke test:** run against the THENEWTONLAB lab domain and sanity-check output.
