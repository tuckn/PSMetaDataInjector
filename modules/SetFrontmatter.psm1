Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function New-FrontmatterNoteId {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string] $ExistingNoteId
    )

    if (-not [string]::IsNullOrWhiteSpace($ExistingNoteId)) {
        return $ExistingNoteId.Trim()
    }

    return ([guid]::NewGuid().ToString())
}

function ConvertTo-YamlQuoted {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Value
    )

    $result = if ($null -eq $Value) { '' } else { $Value }
    return ('"{0}"' -f ($result -replace '"', '\"'))
}

function ConvertTo-YamlTagArray {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]] $Tags
    )

    if (-not $Tags -or $Tags.Count -eq 0) {
        return '[]'
    }

    $encoded = $Tags | ForEach-Object { ('"{0}"' -f ($_ -replace '"', '\"')) }
    return ('[{0}]' -f ($encoded -join ', '))
}

function ConvertTo-YamlFilesBlock {
    [OutputType([string[]])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]] $Files
    )

    if (-not $Files -or $Files.Count -eq 0) {
        return @('files: []')
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('files:') | Out-Null
    foreach ($file in $Files) {
        $lines.Add(("  - {0}" -f (ConvertTo-YamlQuoted -Value $file))) | Out-Null
    }

    return $lines.ToArray()
}

function ConvertFrom-YamlQuoted {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $trimmed = $Value.Trim()
    if ($trimmed.Length -eq 0) {
        return ''
    }

    if ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"') -and $trimmed.Length -ge 2) {
        $inner = $trimmed.Substring(1, $trimmed.Length - 2)
        return ($inner -replace '\"', '"')
    }

    return $trimmed
}

function ConvertFrom-InlineYamlArray {
    [OutputType([string[]])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    $trimmed = $Value.Trim()
    if ($trimmed -eq '[]') {
        return @()
    }

    try {
        $parsed = ConvertFrom-Json -InputObject $trimmed -ErrorAction Stop
        return [string[]]$parsed
    }
    catch {
        $inner = if ($trimmed.Length -gt 2) { $trimmed.Substring(1, $trimmed.Length - 2) } else { '' }
        if ([string]::IsNullOrWhiteSpace($inner)) {
            return @()
        }

        $parts = $inner -split ','
        $results = New-Object 'System.Collections.Generic.List[string]'
        foreach ($part in $parts) {
            if ($null -eq $part) {
                continue
            }

            $candidate = $part.Trim()
            if ($candidate.StartsWith('"') -and $candidate.EndsWith('"') -and $candidate.Length -ge 2) {
                $candidate = $candidate.Substring(1, $candidate.Length - 2)
            }

            $results.Add(($candidate -replace '\"', '"')) | Out-Null
        }

        return $results.ToArray()
    }
}

function Normalize-MetadataArray {
    [OutputType([string[]])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string[]] $Values
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return @()
    }

    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $Values) {
        if ($null -eq $entry) {
            continue
        }

        $trimmed = $entry.Trim()
        if ($trimmed.Length -eq 0) {
            continue
        }

        $list.Add($trimmed) | Out-Null
    }

    return $list.ToArray()
}

function Select-LineEnding {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Content
    )

    if ($Content -match "`r`n") {
        return "`r`n"
    }

    if ($Content -match "`n") {
        return "`n"
    }

    return [System.Environment]::NewLine
}

function Remove-LeadingNewlines {
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ($Value -replace '^[\r\n]+', '')
}

function Read-YamlSequenceValues {
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [string] $InitialValue,

        [AllowNull()]
        [string[]] $Lines,

        [int] $StartIndex = 0
    )

    $lineArray = if ($null -eq $Lines) { @() } else { @($Lines) }
    $currentIndex = if ($StartIndex -lt 0) { 0 } else { $StartIndex }
    $trimmed = if ($null -eq $InitialValue) { '' } else { $InitialValue.Trim() }

    if ($trimmed -match '^\[.*\]$') {
        return [pscustomobject]@{
            Values   = ConvertFrom-InlineYamlArray -Value $trimmed
            NextIndex = $currentIndex + 1
        }
    }

    if ($trimmed -and $trimmed -ne '[]') {
        return [pscustomobject]@{
            Values   = @(ConvertFrom-YamlQuoted -Value $InitialValue)
            NextIndex = $currentIndex + 1
        }
    }

    $collected = New-Object 'System.Collections.Generic.List[string]'
    $currentIndex++
    while ($currentIndex -lt $lineArray.Length) {
        $line = $lineArray[$currentIndex]
        $match = [regex]::Match($line, '^\s{2,}-\s*(?<item>.*)$')
        if (-not $match.Success) {
            break
        }

        $collected.Add((ConvertFrom-YamlQuoted -Value $match.Groups['item'].Value)) | Out-Null
        $currentIndex++
    }

    return [pscustomobject]@{
        Values   = $collected.ToArray()
        NextIndex = $currentIndex
    }
}

function Get-FrontmatterFileEncoding {
    [OutputType([System.Text.Encoding])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $defaultEncoding = New-Object System.Text.UTF8Encoding($false)

    $fileStream = $null
    try {
        $fileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $bom = New-Object byte[] 4
        $bytesRead = $fileStream.Read($bom, 0, 4)
    }
    catch {
        return $defaultEncoding
    }
    finally {
        if ($null -ne $fileStream) {
            $fileStream.Dispose()
        }
    }

    if ($bytesRead -ge 4 -and $bom[0] -eq 0x00 -and $bom[1] -eq 0x00 -and $bom[2] -eq 0xFE -and $bom[3] -eq 0xFF) {
        return (New-Object System.Text.UTF32Encoding($true, $true))
    }

    if ($bytesRead -ge 4 -and $bom[0] -eq 0xFF -and $bom[1] -eq 0xFE -and $bom[2] -eq 0x00 -and $bom[3] -eq 0x00) {
        return (New-Object System.Text.UTF32Encoding($false, $true))
    }

    if ($bytesRead -ge 3 -and $bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) {
        return (New-Object System.Text.UTF8Encoding($true))
    }

    if ($bytesRead -ge 2 -and $bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode
    }

    if ($bytesRead -ge 2 -and $bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode
    }

    return $defaultEncoding
}

function Write-FrontmatterContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowNull()]
        [string] $Content,

        [System.Text.Encoding] $Encoding
    )

    $targetEncoding = if ($null -ne $Encoding) { $Encoding } else { New-Object System.Text.UTF8Encoding($false) }
    [System.IO.File]::WriteAllText($Path, $Content, $targetEncoding)
}

function Get-FrontmatterAnalysis {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $FrontmatterBlock
    )

    $values = @{
        noteId      = $null
        title       = $null
        description = ''
        date        = $null
        tags        = @()
        files       = @()
    }

    $preserved = New-Object 'System.Collections.Generic.List[string]'

    if ([string]::IsNullOrWhiteSpace($FrontmatterBlock)) {
        return [pscustomobject]@{
            Values        = $values
            PreservedLines = $preserved.ToArray()
        }
    }

    $managedKeys = @('noteId','title','description','date','tags','files')
    $lines = $FrontmatterBlock -split '\r?\n'
    $lineIndex = 0

    while ($lineIndex -lt $lines.Length) {
        $line = $lines[$lineIndex]

        if ($line -match '^\s*---\s*$') {
            $lineIndex++
            continue
        }

        $match = [regex]::Match($line, '^(?<key>[A-Za-z0-9_-]+):\s*(?<value>.*)$')
        if ($match.Success -and $managedKeys -contains $match.Groups['key'].Value) {
            $key = $match.Groups['key'].Value
            $rawValue = $match.Groups['value'].Value

            switch ($key) {
                'tags' {
                    $sequence = Read-YamlSequenceValues -InitialValue $rawValue -Lines $lines -StartIndex $lineIndex
                    $values[$key] = [string[]]$sequence.Values
                    $lineIndex = $sequence.NextIndex
                }
                'files' {
                    $sequence = Read-YamlSequenceValues -InitialValue $rawValue -Lines $lines -StartIndex $lineIndex
                    $values[$key] = [string[]]$sequence.Values
                    $lineIndex = $sequence.NextIndex
                }
                default {
                    $values[$key] = ConvertFrom-YamlQuoted -Value $rawValue
                    $lineIndex++
                }
            }

            continue
        }

        $preserved.Add($line) | Out-Null
        $lineIndex++
    }

    return [pscustomobject]@{
        Values        = $values
        PreservedLines = $preserved.ToArray()
    }
}

function Resolve-DateTitleComponents {
    [OutputType([pscustomobject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DateTitle
    )

    $trimmed = $DateTitle.Trim()
    if ([string]::IsNullOrEmpty($trimmed)) {
        throw 'DateTitle must not be empty.'
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $match = [regex]::Match($trimmed, '^(?<date>\d{4}-\d{2}-\d{2})(?<rest>.*)$')
    if ($match.Success) {
        try {
            $date = [datetime]::ParseExact($match.Groups['date'].Value, 'yyyy-MM-dd', $culture)
        }
        catch {
            throw ('Failed to parse DateTitle value "{0}" as yyyy-MM-dd: {1}' -f $DateTitle, $_.Exception.Message)
        }

        $titlePortion = $match.Groups['rest'].Value.TrimStart()
        if ($titlePortion.Length -eq 0) {
            $titlePortion = $null
        }

        return [pscustomobject]@{
            Date  = $date
            Title = $titlePortion
        }
    }

    $alternate = [regex]::Match($trimmed, '^(?<date>\d{8}T\d{6})(?<rest>.*)$')
    if ($alternate.Success) {
        try {
            $parsed = [datetime]::ParseExact($alternate.Groups['date'].Value, "yyyyMMdd\THHmmss", $culture)
        }
        catch {
            throw ('Failed to parse DateTitle value "{0}" as yyyyMMddThhmmss: {1}' -f $DateTitle, $_.Exception.Message)
        }

        $titlePortion = $alternate.Groups['rest'].Value.TrimStart()
        if ($titlePortion.Length -eq 0) {
            $titlePortion = $null
        }

        return [pscustomobject]@{
            Date  = $parsed
            Title = $titlePortion
        }
    }

    throw 'DateTitle must start with yyyy-MM-dd or yyyyMMddThhmmss.'
}

function Set-MarkdownFrontmatter {
<#$
.SYNOPSIS
Writes or updates a YAML frontmatter block for a Markdown file.

.DESCRIPTION
Set-MarkdownFrontmatter inserts (or refreshes) the YAML block at the top of a Markdown file so that noteId, title, description, date, tags, and files stay consistent. Existing frontmatter is parsed and only the managed keys are updated; any other metadata remains untouched in-place. When -DateTitle is supplied, the cmdlet parses the leading yyyy-MM-dd or yyyyMMddThhmmss prefix to set the date and uses the trailing text as the title. Specify -Passthru to emit the applied metadata object instead of only touching the file.

.PARAMETER Path
Specifies the Markdown file to update. The path is resolved with Resolve-Path and must refer to an existing file.

.PARAMETER Title
Defines the title stored inside the frontmatter. Empty or whitespace-only strings are rejected.

.PARAMETER DateTitle
Supplies a combined date/title string (for example "2024-11-09 Hiking in Kyoto" or "20241109T073031 Hiking in Kyoto"). The cmdlet separates the prefix into the date and uses the remainder as the title when -Title is not provided.

.PARAMETER Description
Sets the description text. When omitted the existing description is preserved; otherwise blank values are written as empty strings.

.PARAMETER Date
Sets the date field. Values are serialized as yyyy-MM-dd.

.PARAMETER Tags
Specifies one or more tags that are stored as a YAML array.

.PARAMETER Files
Provides the list of related files recorded in the frontmatter. The list is written as a YAML sequence under the files key.

.PARAMETER Passthru
Emits an object describing the applied metadata (NoteId, Title, Description, Date, Tags, Files).

.EXAMPLE
Set-MarkdownFrontmatter -Path .\notes\2024-11-09.md -DateTitle '2024-11-09 Hiking in Kyoto' -Tags 'travel','kyoto' -Files 'ss:/20241109T071200.png'

.EXAMPLE
Get-ChildItem .\notes -Filter '*.md' | Set-MarkdownFrontmatter -Title 'Placeholder' -Date (Get-Date) -Description ''
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('FullName')]
        [string] $Path,

        [AllowNull()]
        [string] $Title,

        [AllowNull()]
        [string] $DateTitle,

        [AllowNull()]
        [string] $Description,

        [Nullable[datetime]] $Date,

        [string[]] $Tags,

        [string[]] $Files,

        [switch] $Passthru
    )

    process {
        if ($PSBoundParameters.ContainsKey('Title') -and [string]::IsNullOrWhiteSpace($Title)) {
            throw 'Title must not be empty or whitespace.'
        }

        $dateTitleParts = $null
        if ($PSBoundParameters.ContainsKey('DateTitle')) {
            if ([string]::IsNullOrWhiteSpace($DateTitle)) {
                throw 'DateTitle must not be empty or whitespace.'
            }

            $dateTitleParts = Resolve-DateTitleComponents -DateTitle $DateTitle
        }

        $resolvedPath = $null
        try {
            $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        }
        catch {
            throw ("The Markdown file '{0}' could not be resolved: {1}" -f $Path, $_.Exception.Message)
        }

        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw ("The Markdown file '{0}' was not found." -f $resolvedPath)
        }

        $sourceEncoding = Get-FrontmatterFileEncoding -Path $resolvedPath
        try {
            $existingContent = [System.IO.File]::ReadAllText($resolvedPath, $sourceEncoding)
        }
        catch {
            throw ("Failed to read the Markdown file '{0}': {1}" -f $resolvedPath, $_.Exception.Message)
        }
        $lineEnding = Select-LineEnding -Content $existingContent
        $frontmatterRegex = [regex]'(?s)^(---\s*\r?\n.*?\r?\n---\s*\r?\n*)'
        $frontmatterMatch = $frontmatterRegex.Match($existingContent)

        $analysis = if ($frontmatterMatch.Success) {
            Get-FrontmatterAnalysis -FrontmatterBlock $frontmatterMatch.Value
        }
        else {
            Get-FrontmatterAnalysis -FrontmatterBlock $null
        }

        $existingValues = $analysis.Values
        $culture = [System.Globalization.CultureInfo]::InvariantCulture

        $resolvedTitle = $existingValues['title']
        if ($dateTitleParts -and $dateTitleParts.Title) {
            $resolvedTitle = $dateTitleParts.Title
        }
        if ($PSBoundParameters.ContainsKey('Title')) {
            $resolvedTitle = $Title.Trim()
        }
        if ($null -eq $resolvedTitle) {
            $resolvedTitle = ''
        }

        $resolvedDescription = $existingValues['description']
        if ($PSBoundParameters.ContainsKey('Description')) {
            $resolvedDescription = if ($null -eq $Description) { '' } else { $Description }
        }
        if ($null -eq $resolvedDescription) {
            $resolvedDescription = ''
        }

        $resolvedDate = $existingValues['date']
        if ($dateTitleParts -and $null -ne $dateTitleParts.Date) {
            $resolvedDate = $dateTitleParts.Date.ToString('yyyy-MM-dd', $culture)
        }
        if ($PSBoundParameters.ContainsKey('Date')) {
            if ($null -eq $Date) {
                $resolvedDate = ''
            }
            else {
                $resolvedDate = ([datetime]$Date).ToString('yyyy-MM-dd', $culture)
            }
        }
        if ($null -eq $resolvedDate) {
            $resolvedDate = ''
        }

        $resolvedTags = $existingValues['tags']
        if ($null -eq $resolvedTags) {
            $resolvedTags = @()
        }
        if ($PSBoundParameters.ContainsKey('Tags')) {
            $resolvedTags = Normalize-MetadataArray -Values $Tags
        }

        $resolvedFiles = $existingValues['files']
        if ($null -eq $resolvedFiles) {
            $resolvedFiles = @()
        }
        if ($PSBoundParameters.ContainsKey('Files')) {
            $resolvedFiles = Normalize-MetadataArray -Values $Files
        }

        if (-not $frontmatterMatch.Success) {
            if ([string]::IsNullOrWhiteSpace($resolvedTitle)) {
                throw 'Title (via -Title or -DateTitle) is required when creating a new frontmatter block.'
            }
            if ([string]::IsNullOrWhiteSpace($resolvedDate)) {
                throw 'Date (via -Date or -DateTitle) is required when creating a new frontmatter block.'
            }
        }

        $noteId = New-FrontmatterNoteId -ExistingNoteId $existingValues['noteId']
        $noteIdValue = ConvertTo-YamlQuoted -Value $noteId
        $titleValue = ConvertTo-YamlQuoted -Value $resolvedTitle
        $descriptionValue = ConvertTo-YamlQuoted -Value $resolvedDescription
        $dateValue = if ([string]::IsNullOrWhiteSpace($resolvedDate)) { '""' } else { $resolvedDate }
        $tagsValue = ConvertTo-YamlTagArray -Tags $resolvedTags
        $filesBlock = ConvertTo-YamlFilesBlock -Files $resolvedFiles

        $frontmatterLines = New-Object 'System.Collections.Generic.List[string]'
        $frontmatterLines.Add('---') | Out-Null
        $frontmatterLines.Add(("noteId: {0}" -f $noteIdValue)) | Out-Null
        $frontmatterLines.Add(("title: {0}" -f $titleValue)) | Out-Null
        $frontmatterLines.Add(("description: {0}" -f $descriptionValue)) | Out-Null
        $frontmatterLines.Add(("date: {0}" -f $dateValue)) | Out-Null
        $frontmatterLines.Add(("tags: {0}" -f $tagsValue)) | Out-Null
        foreach ($line in $filesBlock) {
            $frontmatterLines.Add($line) | Out-Null
        }

        if ($analysis.PreservedLines.Count -gt 0) {
            if ($frontmatterLines[$frontmatterLines.Count - 1] -ne '') {
                $frontmatterLines.Add('') | Out-Null
            }

            foreach ($line in $analysis.PreservedLines) {
                $frontmatterLines.Add($line) | Out-Null
            }
        }

        $frontmatterLines.Add('---') | Out-Null
        $frontmatterBlock = [string]::Join($lineEnding, $frontmatterLines)

        $body = if ($frontmatterMatch.Success) {
            $existingContent.Substring($frontmatterMatch.Length)
        }
        else {
            $existingContent
        }
        $bodyAfter = Remove-LeadingNewlines -Value $body

        $updatedContent = if ([string]::IsNullOrEmpty($bodyAfter)) {
            $frontmatterBlock + $lineEnding
        }
        else {
            $frontmatterBlock + $lineEnding + $lineEnding + $bodyAfter
        }

        $shouldWrite = $PSCmdlet.ShouldProcess($resolvedPath, 'Write Markdown frontmatter')
        if ($shouldWrite) {
            Write-FrontmatterContent -Path $resolvedPath -Content $updatedContent -Encoding $sourceEncoding
        }

        if ($Passthru.IsPresent) {
            [pscustomobject]@{
                SourcePath  = $resolvedPath
                NoteId      = $noteId
                Title       = $resolvedTitle
                Description = $resolvedDescription
                Date        = $resolvedDate
                Tags        = @($resolvedTags)
                Files       = @($resolvedFiles)
            }
        }
    }
}

Export-ModuleMember -Function Set-MarkdownFrontmatter
