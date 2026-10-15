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
