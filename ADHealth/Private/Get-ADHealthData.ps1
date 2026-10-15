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
