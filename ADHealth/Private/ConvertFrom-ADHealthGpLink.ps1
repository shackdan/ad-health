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
