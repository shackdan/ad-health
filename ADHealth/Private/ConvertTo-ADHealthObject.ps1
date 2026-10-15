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
