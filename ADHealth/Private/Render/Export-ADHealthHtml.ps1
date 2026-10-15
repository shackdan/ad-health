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
