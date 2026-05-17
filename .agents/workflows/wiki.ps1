param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('wiki_add', 'wiki_ingest', 'wiki_query', 'wiki_lint', 'wiki_list', 'wiki_read', 'wiki_delete', 'wiki_refresh')]
    [string] $Operation,

    [Alias('input')]
    [string] $InputJson = '{}',

    [switch] $Json,

    [string] $Root = ''
)

$ErrorActionPreference = 'Stop'

$Categories = @('architecture', 'decision', 'pattern', 'debugging', 'environment', 'session-log', 'reference', 'convention')
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    # Some hosts do not expose mutable console encodings.
}

function Resolve-WikiRoot {
    $current = (Resolve-Path $PSScriptRoot).Path

    while ($current) {
        if ((Test-Path (Join-Path $current '.git')) -or (Test-Path (Join-Path $current 'AGENTS.md'))) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current) {
            break
        }
        $current = $parent
    }

    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Resolve-WikiRoot
}

function ConvertFrom-InputJson {
    param([string] $Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return [pscustomobject]@{} }
    return $Value | ConvertFrom-Json
}

function Get-Windows1252Encoding {
    try {
        $providerType = [type]'System.Text.CodePagesEncodingProvider'
        if ($providerType) {
            [System.Text.Encoding]::RegisterProvider($providerType::Instance)
        }
    }
    catch {
    }

    return [System.Text.Encoding]::GetEncoding(1252)
}

function Get-MojibakeScore {
    param([string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }

    $suspicious = @(
        0x00C2, 0x00C3, 0x00E2, 0x20AC, 0x00ED, 0x00EC,
        0x00EA, 0x00EB, 0x0153, 0x00AA, 0x00A9, 0x00A7,
        0x00A8, 0x201E, 0xFFFD
    )
    $score = 0
    foreach ($char in $Text.ToCharArray()) {
        if ([int][char]$char -in $suspicious) {
            $score += 1
        }
    }
    return $score
}

function Repair-TextEncoding {
    param([AllowNull()][string] $Text)
    if ($null -eq $Text -or $Text -eq '') { return $Text }

    $originalScore = Get-MojibakeScore $Text
    if ($originalScore -eq 0) { return $Text }

    try {
        $bytes = (Get-Windows1252Encoding).GetBytes($Text)
        $candidate = [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
        return $Text
    }

    if ($candidate -eq $Text -or $candidate.Contains([char]0xFFFD)) {
        return $Text
    }

    $candidateScore = Get-MojibakeScore $candidate
    $originalHasHangul = $Text -match '\p{IsHangulSyllables}|\p{IsHangulJamo}|\p{IsHangulCompatibilityJamo}'
    $candidateHasHangul = $candidate -match '\p{IsHangulSyllables}|\p{IsHangulJamo}|\p{IsHangulCompatibilityJamo}'

    if (($candidateHasHangul -and -not $originalHasHangul) -or $candidateScore -lt $originalScore) {
        return $candidate
    }

    return $Text
}

function Test-TextEncodingHealth {
    param([AllowNull()][string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return @() }

    $issues = @()
    if ($Text.Contains([char]0xFFFD)) {
        $issues += 'contains Unicode replacement character'
    }
    $koreanReplacementMojibake = [string]::Concat([char]0x5360, [char]0xC3D9, [char]0xC639)
    if ($Text.Contains($koreanReplacementMojibake)) {
        $issues += 'contains common Korean replacement mojibake'
    }
    if ((Get-MojibakeScore $Text) -ge 2) {
        $issues += 'contains likely UTF-8 mojibake'
    }
    return @($issues)
}

function Assert-HealthyTextEncoding {
    param(
        [string] $Field,
        [AllowNull()][string] $Text
    )

    $issues = @(Test-TextEncodingHealth $Text)
    if ($issues.Count -gt 0) {
        throw "encoding validation failed for ${Field}: $($issues -join '; ')"
    }
}

function ConvertTo-Slug {
    param([string] $Title)
    $slug = $Title.Trim().ToLowerInvariant()
    $slug = [regex]::Replace($slug, '[^\p{L}\p{Nd}]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "page-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    }
    return $slug
}

function Get-WikiPath {
    param([string] $Name)
    return Join-Path (Join-Path $Root '.wiki') $Name
}

function Ensure-Wiki {
    $wikiDir = Get-WikiPath ''
    if (-not (Test-Path $wikiDir)) {
        New-Item -ItemType Directory -Path $wikiDir | Out-Null
    }
}

function ConvertTo-Array {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [array]) {
        return @($Value | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    }
    return @("$Value".Trim()) | Where-Object { $_ }
}

function Get-PageFiles {
    $canonicalDir = Get-WikiPath ''

    if (Test-Path $canonicalDir) {
        return @(Get-ChildItem -Path $canonicalDir -Filter '*.md' -File |
            Where-Object { $_.Name -notin @('index.md', 'log.md') })
    }

    return @()
}

function Read-WikiPage {
    param([System.IO.FileInfo] $File)

    $text = Get-Content -Raw -LiteralPath $File.FullName -Encoding UTF8
    $metadata = [ordered]@{
        title = [IO.Path]::GetFileNameWithoutExtension($File.Name)
        slug = [IO.Path]::GetFileNameWithoutExtension($File.Name)
        category = ''
        tags = @()
        created = ''
        updated = ''
    }
    $content = $text

    if ($text -match '(?s)^---\r?\n(.*?)\r?\n---\r?\n?(.*)$') {
        $frontMatter = $Matches[1] -split '\r?\n'
        $content = $Matches[2]
        $currentListKey = $null

        foreach ($line in $frontMatter) {
            if ($line -match '^([A-Za-z0-9_-]+):\s*(.*)$') {
                $key = $Matches[1]
                $value = $Matches[2].Trim()
                $currentListKey = $null

                if ($value -eq '') {
                    if ($key -eq 'tags') {
                        $metadata[$key] = @()
                        $currentListKey = $key
                    }
                }
                elseif ($key -eq 'tags') {
                    $metadata[$key] = @($value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }
                else {
                    $metadata[$key] = $value
                }
            }
            elseif ($currentListKey -and $line -match '^\s*-\s*(.+)$') {
                $metadata[$currentListKey] = @($metadata[$currentListKey]) + $Matches[1].Trim()
            }
        }
    }

    [pscustomobject]@{
        title = $metadata.title
        slug = $metadata.slug
        category = $metadata.category
        tags = @($metadata.tags)
        created = $metadata.created
        updated = $metadata.updated
        content = $content.Trim()
        path = $File.FullName
    }
}

function Add-WikiLog {
    param([string] $Message)
    Ensure-Wiki
    Add-Content -LiteralPath (Get-WikiPath 'log.md') -Value "- $((Get-Date).ToUniversalTime().ToString('o')) $Message" -Encoding utf8
}

function Update-WikiIndex {
    Ensure-Wiki
    $pages = @(Get-PageFiles | ForEach-Object { Read-WikiPage $_ } | Sort-Object category, title)
    $lines = @('# Wiki Index', '')

    foreach ($category in $Categories) {
        $group = @($pages | Where-Object { $_.category -eq $category })
        if ($group.Count -eq 0) { continue }
        $lines += "## $category"
        $lines += ''
        foreach ($page in $group) {
            $tagText = if ($page.tags.Count -gt 0) { " [$($page.tags -join ', ')]" } else { '' }
            $lines += "- [[$($page.slug)]] - $($page.title)$tagText"
        }
        $lines += ''
    }

    Set-Content -LiteralPath (Get-WikiPath 'index.md') -Value ($lines -join [Environment]::NewLine) -Encoding utf8
    return $pages
}

function Write-WikiPage {
    param(
        [string] $Title,
        [string] $Content,
        [string[]] $Tags,
        [string] $Category,
        [string] $Slug
    )

    Ensure-Wiki
    $Title = Repair-TextEncoding $Title
    $Content = Repair-TextEncoding $Content
    $Tags = @($Tags | ForEach-Object { Repair-TextEncoding "$_" })
    $Category = Repair-TextEncoding $Category
    $Slug = Repair-TextEncoding $Slug

    if ([string]::IsNullOrWhiteSpace($Title)) { throw 'title is required' }
    if ([string]::IsNullOrWhiteSpace($Content)) { throw 'content is required' }
    if ([string]::IsNullOrWhiteSpace($Category)) { $Category = 'reference' }
    if ($Category -notin $Categories) { throw "invalid category '$Category'. Allowed: $($Categories -join ', ')" }
    if ([string]::IsNullOrWhiteSpace($Slug)) { $Slug = ConvertTo-Slug $Title }

    Assert-HealthyTextEncoding -Field 'title' -Text $Title
    Assert-HealthyTextEncoding -Field 'content' -Text $Content
    foreach ($tag in $Tags) {
        Assert-HealthyTextEncoding -Field 'tag' -Text $tag
    }

    $path = Get-WikiPath "$Slug.md"
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $created = $now
    if (Test-Path $path) {
        $existing = Read-WikiPage (Get-Item $path)
        if ($existing.created) { $created = $existing.created }
    }

    $tagBlock = if ($Tags.Count -gt 0) { ($Tags | ForEach-Object { "  - $_" }) -join [Environment]::NewLine } else { '' }
    $page = @(
        '---',
        "title: $Title",
        "slug: $Slug",
        "category: $Category",
        'tags:',
        $tagBlock,
        "created: $created",
        "updated: $now",
        '---',
        '',
        $Content.Trim(),
        ''
    ) -join [Environment]::NewLine

    Set-Content -LiteralPath $path -Value $page -Encoding utf8
    Add-WikiLog "upsert $Slug"
    Update-WikiIndex | Out-Null
    return Read-WikiPage (Get-Item $path)
}

function Find-WikiPage {
    param([string] $Page)
    $slug = ConvertTo-Slug $Page
    $match = @(Get-PageFiles) | Where-Object {
        [IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $Page -or
        [IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $slug
    } | Select-Object -First 1
    if (-not $match) { throw "page not found: $Page" }
    return Read-WikiPage $match
}

function Query-Wiki {
    param($Input)
    $query = if ($Input.PSObject.Properties.Name -contains 'query') { "$($Input.query)" } else { '' }
    $requiredTags = ConvertTo-Array $Input.tags
    $category = if ($Input.PSObject.Properties.Name -contains 'category') { "$($Input.category)" } else { '' }
    $terms = @($query.ToLowerInvariant() -split '\s+' | Where-Object { $_ })

    $results = foreach ($page in @(Get-PageFiles | ForEach-Object { Read-WikiPage $_ })) {
        if ($category -and $page.category -ne $category) { continue }

        $missingTag = $false
        foreach ($tag in $requiredTags) {
            if ($tag -notin $page.tags) {
                $missingTag = $true
                break
            }
        }
        if ($missingTag) { continue }

        $haystack = "$($page.title) $($page.slug) $($page.category) $($page.tags -join ' ') $($page.content)".ToLowerInvariant()
        $score = 0
        foreach ($term in $terms) {
            if ($haystack.Contains($term)) { $score += 1 }
        }
        $score += $requiredTags.Count * 2
        if ($category) { $score += 1 }

        if ($terms.Count -eq 0 -or $score -gt 0) {
            [pscustomobject]@{
                title = $page.title
                slug = $page.slug
                category = $page.category
                tags = $page.tags
                score = $score
                excerpt = if ($page.content.Length -gt 180) { $page.content.Substring(0, 180) } else { $page.content }
            }
        }
    }

    return @($results | Sort-Object score, title -Descending)
}

function Test-Wiki {
    $issues = @()
    $slugs = @{}
    $pages = @(Get-PageFiles | ForEach-Object { Read-WikiPage $_ })

    foreach ($file in @(Get-PageFiles)) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            [void]$Utf8Strict.GetString($bytes)
        }
        catch {
            $issues += [pscustomobject]@{ page = [IO.Path]::GetFileNameWithoutExtension($file.Name); severity = 'error'; message = 'file is not valid UTF-8' }
        }
    }

    foreach ($page in $pages) {
        if ([string]::IsNullOrWhiteSpace($page.title)) {
            $issues += [pscustomobject]@{ page = $page.slug; severity = 'error'; message = 'missing title' }
        }
        foreach ($encodingIssue in @(Test-TextEncodingHealth $page.title)) {
            $issues += [pscustomobject]@{ page = $page.slug; severity = 'error'; message = "title encoding issue: $encodingIssue" }
        }
        foreach ($encodingIssue in @(Test-TextEncodingHealth $page.content)) {
            $issues += [pscustomobject]@{ page = $page.slug; severity = 'error'; message = "content encoding issue: $encodingIssue" }
        }
        foreach ($tag in @($page.tags)) {
            foreach ($encodingIssue in @(Test-TextEncodingHealth $tag)) {
                $issues += [pscustomobject]@{ page = $page.slug; severity = 'error'; message = "tag encoding issue: $encodingIssue" }
            }
        }
        if ($page.category -and $page.category -notin $Categories) {
            $issues += [pscustomobject]@{ page = $page.slug; severity = 'error'; message = "invalid category '$($page.category)'" }
        }
        if ($slugs.ContainsKey($page.slug)) {
            $issues += [pscustomobject]@{ page = $page.slug; severity = 'error'; message = 'duplicate slug' }
        }
        $slugs[$page.slug] = $true
    }

    foreach ($page in $pages) {
        foreach ($match in [regex]::Matches($page.content, '\[\[([^\]]+)\]\]')) {
            $target = ConvertTo-Slug $match.Groups[1].Value
            if (-not $slugs.ContainsKey($target)) {
                $issues += [pscustomobject]@{ page = $page.slug; severity = 'warning'; message = "broken wiki link '$($match.Groups[1].Value)'" }
            }
        }
    }

    [pscustomobject]@{
        ok = -not (@($issues | Where-Object { $_.severity -eq 'error' }).Count)
        issue_count = $issues.Count
        issues = @($issues)
    }
}

$inputObject = ConvertFrom-InputJson $InputJson

switch ($Operation) {
    'wiki_add' {
        $result = Write-WikiPage -Title $inputObject.title -Content $inputObject.content -Tags (ConvertTo-Array $inputObject.tags) -Category $inputObject.category -Slug $inputObject.slug
    }
    'wiki_ingest' {
        $result = Write-WikiPage -Title $inputObject.title -Content $inputObject.content -Tags (ConvertTo-Array $inputObject.tags) -Category $inputObject.category -Slug $inputObject.slug
    }
    'wiki_query' {
        $result = Query-Wiki $inputObject
    }
    'wiki_lint' {
        $result = Test-Wiki
    }
    'wiki_list' {
        $result = @(Get-PageFiles | ForEach-Object { Read-WikiPage $_ } | Sort-Object category, title | ForEach-Object {
            [pscustomobject]@{
                title = $_.title
                slug = $_.slug
                category = $_.category
                tags = $_.tags
                updated = $_.updated
            }
        })
    }
    'wiki_read' {
        $result = Find-WikiPage $inputObject.page
    }
    'wiki_delete' {
        $page = Find-WikiPage $inputObject.page
        $canonicalDir = (Get-WikiPath '').TrimEnd('\', '/')
        $pageDir = (Split-Path -Parent $page.path).TrimEnd('\', '/')
        if ($pageDir -ne $canonicalDir) {
            throw 'refusing to delete page outside .wiki'
        }
        Remove-Item -LiteralPath $page.path
        Add-WikiLog "delete $($page.slug)"
        Update-WikiIndex | Out-Null
        $result = [pscustomobject]@{ deleted = $page.slug }
    }
    'wiki_refresh' {
        $pages = Update-WikiIndex
        Add-WikiLog 'refresh index'
        $result = [pscustomobject]@{ refreshed = $true; page_count = @($pages).Count }
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
}
else {
    $result | Format-List | Out-String
}
