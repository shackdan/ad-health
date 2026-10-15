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
