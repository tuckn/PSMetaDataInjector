
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Invoke-PSMetaDataInjectorExifTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ExecutablePath,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    & $ExecutablePath @Arguments
    return $LASTEXITCODE
}

function Get-DateFromFileName {
    [OutputType([Nullable[datetime]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FileName
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $nameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    if (-not $nameWithoutExtension) {
        return $null
    }

    $patterns = @(
        @{
            Regex  = [regex]::new('(?<year>\d{4})(?<month>\d{2})(?<day>\d{2})T(?<hour>\d{2})(?<minute>\d{2})(?<second>\d{2})(?<offset>[+-]\d{4})?', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
            Format = 'yyyyMMddHHmmss'
            Custom = { param($match) "{0}{1}{2}{3}{4}{5}" -f $match.Groups['year'].Value, $match.Groups['month'].Value, $match.Groups['day'].Value, $match.Groups['hour'].Value, $match.Groups['minute'].Value, $match.Groups['second'].Value }
        }
        @{
            Regex  = [regex]::new('(?<year>\d{4})(?<month>\d{2})(?<day>\d{2})(?<hour>\d{2})(?<minute>\d{2})(?<second>\d{2})', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
            Format = 'yyyyMMddHHmmss'
        }
        @{
            Regex  = [regex]::new('(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})[ _-](?<time>\d{6})', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
            Format = 'yyyy-MM-dd HHmmss'
            Custom = { param($match) "{0}-{1}-{2} {3}" -f $match.Groups['year'].Value, $match.Groups['month'].Value, $match.Groups['day'].Value, $match.Groups['time'].Value }
        }
        @{
            Regex  = [regex]::new('(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})[ _-](?<hour>\d{2})[-_ ](?<minute>\d{2})[-_ ](?<second>\d{2})', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
            Format = 'yyyy-MM-dd HHmmss'
            Custom = { param($match) "{0}-{1}-{2} {3}{4}{5}" -f $match.Groups['year'].Value, $match.Groups['month'].Value, $match.Groups['day'].Value, $match.Groups['hour'].Value, $match.Groups['minute'].Value, $match.Groups['second'].Value }
        }
        @{
            Regex  = [regex]::new('(?<day>\d{2})_(?<month>\d{2})_(?<year>\d{4})_(?<hour>\d{2})_(?<minute>\d{2})_(?<second>\d{2})', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
            Format = 'yyyy-MM-dd HHmmss'
            Custom = { param($match) "{0}-{1}-{2} {3}{4}{5}" -f $match.Groups['year'].Value, $match.Groups['month'].Value, $match.Groups['day'].Value, $match.Groups['hour'].Value, $match.Groups['minute'].Value, $match.Groups['second'].Value }
        }
    )

    foreach ($pattern in $patterns) {
        $match = $pattern.Regex.Match($nameWithoutExtension)
        if ($match.Success) {
            try {
                $value = if ($pattern.ContainsKey('Custom')) { & $pattern.Custom $match } else { $match.Value }
                return [datetime]::ParseExact($value, $pattern.Format, $culture)
            }
            catch {
                Write-Verbose ("Failed to parse '{0}' with pattern '{1}': {2}" -f $nameWithoutExtension, $pattern.Regex.ToString(), $_.Exception.Message)
            }
        }
    }

    return $null
}

function Get-DateMetadataArguments {
<#
.SYNOPSIS
Builds exiftool arguments for updating capture date metadata.

.PARAMETER Timestamp
Specifies the timestamp string (formatted as yyyy-MM-ddTHH:mm:ss) to assign to XMP date fields.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Timestamp
    )

    return @(
        ("-XMP-exif:DateTimeOriginal={0}" -f $Timestamp),
        ("-XMP-photoshop:DateCreated={0}" -f $Timestamp),
        ("-XMP-xmp:CreateDate={0}" -f $Timestamp)
    )
}

function Get-TitleMetadataArguments {
<#
.SYNOPSIS
Builds exiftool arguments for updating XMP title metadata.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Title
    )

    $trimmed = $Title.Trim()
    if ([string]::IsNullOrEmpty($trimmed)) {
        return @()
    }

    return @(
        '-XMP-dc:Title=',
        ("-XMP-dc:Title-x-default={0}" -f $trimmed),
        ("-XMP-photoshop:Headline={0}" -f $trimmed)
    )
}

function Get-DescriptionMetadataArguments {
<#
.SYNOPSIS
Builds exiftool arguments for updating XMP description metadata.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [string] $Description
    )

    $value = if ($null -eq $Description) { '' } else { $Description }
    $trimmed = $value.Trim()
    return @(
        '-XMP-dc:Description=',
        ("-XMP-dc:Description-x-default={0}" -f $trimmed)
    )
}

function Get-KeywordMetadataArguments {
<#
.SYNOPSIS
Builds exiftool argument lists for keyword metadata (dc:subject, lr:weightedFlatSubject, lr:hierarchicalSubject).

.PARAMETER Keyword
One or more keywords. Use the Lightroom-style pipe character (|) to specify hierarchical keywords.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Keyword
    )

    $flatSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $flatList = New-Object 'System.Collections.Generic.List[string]'
    $weightedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $weightedList = New-Object 'System.Collections.Generic.List[string]'
    $hierarchicalSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $hierarchicalList = New-Object 'System.Collections.Generic.List[string]'

    function Add-UniqueValue {
        param(
            [string] $Value,
            [System.Collections.Generic.HashSet[string]] $Set,
            [System.Collections.Generic.List[string]] $List
        )

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return
        }

        $trimmed = $Value.Trim()
        if ($Set.Add($trimmed)) {
            $List.Add($trimmed) | Out-Null
        }
    }

    foreach ($rawKeyword in $Keyword) {
        if ([string]::IsNullOrWhiteSpace($rawKeyword)) {
            continue
        }

        $value = $rawKeyword.Trim()
        if ($value.Contains('|')) {
            if ($hierarchicalSet.Add($value)) {
                $hierarchicalList.Add($value) | Out-Null
            }

            $parts = $value -split '\|'
            foreach ($part in $parts) {
                Add-UniqueValue -Value $part -Set $flatSet -List $flatList
            }

            $leaf = $parts[-1]
            Add-UniqueValue -Value $leaf -Set $weightedSet -List $weightedList
        }
        else {
            Add-UniqueValue -Value $value -Set $flatSet -List $flatList
            Add-UniqueValue -Value $value -Set $weightedSet -List $weightedList
        }
    }

    $arguments = @()

    if ($flatList.Count -gt 0) {
        $arguments += '-XMP-dc:Subject='
        foreach ($entry in $flatList) {
            $arguments += ("-XMP-dc:Subject+={0}" -f $entry)
        }
    }

    if ($weightedList.Count -gt 0) {
        $arguments += '-XMP-lr:weightedFlatSubject='
        foreach ($entry in $weightedList) {
            $arguments += ("-XMP-lr:weightedFlatSubject+={0}" -f $entry)
        }
    }

    if ($hierarchicalList.Count -gt 0) {
        $arguments += '-XMP-lr:hierarchicalSubject='
        foreach ($entry in $hierarchicalList) {
            $arguments += ("-XMP-lr:hierarchicalSubject+={0}" -f $entry)
        }
    }

    return [pscustomobject]@{
        Arguments            = $arguments
        FlatKeywords         = [string[]]$flatList
        WeightedKeywords     = [string[]]$weightedList
        HierarchicalKeywords = [string[]]$hierarchicalList
    }
}

function Set-MediaMetadata {
<#
.SYNOPSIS
Adds metadata (capture date/time, descriptive fields, and keywords) to media files via exiftool.

.PARAMETER InputPath
Specifies the path to a single image file or a directory that contains image files. Wildcards are supported and the parameter accepts pipeline input.

.PARAMETER Recurse
When InputPath is a directory, include image files from all child directories.

.PARAMETER OutputDirectory
Specifies a directory where processed files are written. When provided, source files are copied to the directory (preserving relative structure for directory inputs) before metadata is updated. When omitted, files are updated in place.

.PARAMETER CreatedDate
Provides a fallback capture timestamp that is used when -InferCreatedDate is absent or fails.

.PARAMETER InferCreatedDate
When supplied, attempts to infer the capture timestamp from each file name using supported patterns.

.PARAMETER Title
Specifies the title text written to XMP-dc:Title and XMP-photoshop:Headline.

.PARAMETER Description
Specifies the XMP dc:description text (x-default locale) to write.

.PARAMETER Keywords
Supplies one or more keywords. Pipe characters (|) denote hierarchical keywords in Lightroom format.

.PARAMETER ExifToolPath
Provides the path to the exiftool executable. When omitted, the function searches for exiftool on the PATH.

.PARAMETER Passthru
Outputs an object describing each updated file to the pipeline.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string] $InputPath,

        [switch] $Recurse,

        [ValidateNotNullOrEmpty()]
        [string] $OutputDirectory,

        [Nullable[datetime]] $CreatedDate,

        [switch] $InferCreatedDate,

        [string] $Title,

        [AllowNull()]
        [string] $Description,

        [string[]] $Keywords,

        [ValidateNotNullOrEmpty()]
        [string] $ExifToolPath,

        [switch] $Passthru
    )

    begin {
        $supportedExtensions = @(
            '.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp', '.gif',
            '.heic', '.heif', '.webp', '.dng', '.nef', '.cr2', '.cr3', '.arw'
        )

        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $resolvedExifToolPath = $null
        $resolvedOutputDirectory = $null
        $createdDateProvided = ($PSBoundParameters.ContainsKey('CreatedDate') -and $null -ne $CreatedDate)
        $shouldInferDate = $InferCreatedDate.IsPresent
        $hasTitle = $PSBoundParameters.ContainsKey('Title') -and -not [string]::IsNullOrWhiteSpace($Title)
        $hasDescription = $PSBoundParameters.ContainsKey('Description')
        $hasKeywords = $PSBoundParameters.ContainsKey('Keywords') -and $Keywords -and $Keywords.Count -gt 0

        if ($PSBoundParameters.ContainsKey('ExifToolPath')) {
            try {
                $resolvedExifToolPath = (Resolve-Path -LiteralPath $ExifToolPath -ErrorAction Stop).ProviderPath
            }
            catch {
                throw ("The specified exiftool path '{0}' could not be resolved: {1}" -f $ExifToolPath, $_.Exception.Message)
            }
        }
        else {
            $command = Get-Command -Name 'exiftool' -ErrorAction SilentlyContinue
            if (-not $command) {
                $command = Get-Command -Name 'exiftool.exe' -ErrorAction SilentlyContinue
            }

            if (-not $command) {
                throw 'exiftool was not found on PATH. Provide -ExifToolPath or install exiftool.'
            }

            $resolvedExifToolPath = $command.Path
        }

        if ($PSBoundParameters.ContainsKey('OutputDirectory')) {
            try {
                $resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory -ErrorAction Stop).ProviderPath
            }
            catch {
                $resolvedOutputDirectory = $OutputDirectory
            }

            if (-not (Test-Path -LiteralPath $resolvedOutputDirectory)) {
                New-Item -ItemType Directory -Path $resolvedOutputDirectory -Force | Out-Null
            }

            $script:PSMetaDataInjector_OutputDirectory = $resolvedOutputDirectory
        }
        else {
            $script:PSMetaDataInjector_OutputDirectory = $null
        }

        $script:PSMetaDataInjector_ExifToolPath = $resolvedExifToolPath
        $script:PSMetaDataInjector_InputRoot = $null
        $script:PSMetaDataInjector_Title = if ($hasTitle) { $Title.Trim() } else { $null }
        $script:PSMetaDataInjector_Description = if ($hasDescription) { if ($null -eq $Description) { '' } else { $Description } } else { $null }
        $script:PSMetaDataInjector_Keywords = if ($hasKeywords) { $Keywords } else { $null }
        $script:PSMetaDataInjector_ShouldInferDate = $shouldInferDate
        $script:PSMetaDataInjector_CreatedDate = if ($createdDateProvided) { [datetime]$CreatedDate } else { $null }
        $script:PSMetaDataInjector_Culture = $culture
        $script:PSMetaDataInjector_HasTitle = $hasTitle
        $script:PSMetaDataInjector_HasDescription = $hasDescription
        $script:PSMetaDataInjector_HasKeywords = $hasKeywords
    }

    process {
        $resolvedInput = @()
        try {
            $resolvedInput = @(Resolve-Path -Path $InputPath -ErrorAction Stop)
        }
        catch {
            Write-Error ("Input path '{0}' could not be resolved: {1}" -f $InputPath, $_.Exception.Message)
            return
        }

        foreach ($path in $resolvedInput) {
            $item = Get-Item -LiteralPath $path.ProviderPath -ErrorAction Stop
            if ($item.PSIsContainer) {
                $script:PSMetaDataInjector_InputRoot = $item.FullName
                $filesToProcess = @()
                try {
                    $gciParams = @{ LiteralPath = $item.FullName; File = $true; ErrorAction = 'Stop' }
                    if ($Recurse.IsPresent) { $gciParams.Recurse = $true }
                    $filesToProcess = Get-ChildItem @gciParams | Where-Object {
                        $supportedExtensions -contains ([System.IO.Path]::GetExtension($_.Name).ToLowerInvariant())
                    }
                }
                catch {
                    Write-Error ("Failed to enumerate files in '{0}': {1}" -f $item.FullName, $_.Exception.Message)
                    continue
                }

                if (-not $filesToProcess) {
                    Write-Verbose ("No supported image files were found in '{0}'." -f $item.FullName)
                    continue
                }
            }
            else {
                if (-not $script:PSMetaDataInjector_InputRoot) {
                    $script:PSMetaDataInjector_InputRoot = [System.IO.Path]::GetDirectoryName($item.FullName)
                }

                $extension = [System.IO.Path]::GetExtension($item.Name).ToLowerInvariant()
                if ($supportedExtensions -contains $extension) {
                    $filesToProcess = @($item)
                }
                else {
                    Write-Verbose ("Skipping '{0}' because extension '{1}' is not supported." -f $item.FullName, $extension)
                    continue
                }
            }

            foreach ($file in $filesToProcess) {
                Write-Verbose ("Processing file '{0}'." -f $file.FullName)

                $timestampValue = $null
                if ($script:PSMetaDataInjector_ShouldInferDate) {
                    $inferred = Get-DateFromFileName -FileName $file.Name
                    if ($inferred) {
                        $timestampValue = $inferred.ToString("yyyy-MM-dd'T'HH:mm:ss", $script:PSMetaDataInjector_Culture)
                    }
                }

                if (-not $timestampValue -and $script:PSMetaDataInjector_CreatedDate) {
                    $timestampValue = $script:PSMetaDataInjector_CreatedDate.ToString("yyyy-MM-dd'T'HH:mm:ss", $script:PSMetaDataInjector_Culture)
                }

                $titleMetadata = $null
                if ($script:PSMetaDataInjector_HasTitle) {
                    $titleMetadata = Get-TitleMetadataArguments -Title $script:PSMetaDataInjector_Title
                }

                $descriptionMetadata = $null
                if ($script:PSMetaDataInjector_HasDescription) {
                    $descriptionMetadata = Get-DescriptionMetadataArguments -Description $script:PSMetaDataInjector_Description
                }

                $keywordMetadata = $null
                if ($script:PSMetaDataInjector_HasKeywords) {
                    $keywordMetadata = Get-KeywordMetadataArguments -Keyword $script:PSMetaDataInjector_Keywords
                }

                if (-not $timestampValue -and -not $titleMetadata -and -not $descriptionMetadata -and -not ($keywordMetadata -and $keywordMetadata.Arguments)) {
                    Write-Warning ("Skipping '{0}' because no metadata updates were requested or available." -f $file.FullName)
                    continue
                }

                $sourcePath = $file.FullName
                $targetPath = $sourcePath

                if ($script:PSMetaDataInjector_OutputDirectory) {
                    $relativePath = $file.Name
                    if ($script:PSMetaDataInjector_InputRoot) {
                        try {
                            $sourceUri = New-Object System.Uri $sourcePath
                            $rootUri = New-Object System.Uri (([System.IO.Path]::GetFullPath($script:PSMetaDataInjector_InputRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar))) + [System.IO.Path]::DirectorySeparatorChar)
                            $relativeUri = $rootUri.MakeRelativeUri($sourceUri)
                            $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
                        }
                        catch {
                            $relativePath = $file.Name
                        }
                    }

                    if ([string]::IsNullOrEmpty($relativePath)) {
                        $relativePath = $file.Name
                    }

                    $targetPath = [System.IO.Path]::Combine($script:PSMetaDataInjector_OutputDirectory, $relativePath)
                }

                $metadataArguments = @()
                if ($timestampValue) {
                    $metadataArguments += Get-DateMetadataArguments -Timestamp $timestampValue
                }

                if ($titleMetadata) {
                    $metadataArguments += $titleMetadata
                }

                if ($descriptionMetadata) {
                    $metadataArguments += $descriptionMetadata
                }

                if ($keywordMetadata -and $keywordMetadata.Arguments) {
                    $metadataArguments += $keywordMetadata.Arguments
                }

                if (-not $metadataArguments) {
                    Write-Warning ("Skipping '{0}' because no metadata arguments were produced." -f $file.FullName)
                    continue
                }

                $operationDescription = 'Update media metadata'
                if ($timestampValue -and $script:PSMetaDataInjector_HasTitle) {
                    $operationDescription = "Update capture date and title metadata"
                }
                elseif ($timestampValue) {
                    $operationDescription = "Set XMP dates to $timestampValue"
                }

                if ($PSCmdlet.ShouldProcess($targetPath, $operationDescription)) {
                    if ($script:PSMetaDataInjector_OutputDirectory -and ($targetPath -ne $sourcePath)) {
                        $targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
                        if ($targetDirectory -and -not (Test-Path -LiteralPath $targetDirectory)) {
                            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
                        }

                        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
                    }

                    $arguments = @('-overwrite_original', '-P', '-q', '-q') + $metadataArguments + $targetPath
                    $exitCode = Invoke-PSMetaDataInjectorExifTool -ExecutablePath $script:PSMetaDataInjector_ExifToolPath -Arguments $arguments

                    if ($exitCode -ne 0) {
                        throw ("exiftool exited with code {0} while processing '{1}'." -f $exitCode, $targetPath)
                    }

                    if ($Passthru.IsPresent) {
                        $keywordSummary = if ($keywordMetadata) { $keywordMetadata.FlatKeywords } else { @() }
                        $hierSummary = if ($keywordMetadata) { $keywordMetadata.HierarchicalKeywords } else { @() }

                        [pscustomobject]@{
                            SourcePath           = $sourcePath
                            FilePath             = $targetPath
                            Timestamp            = $timestampValue
                            ExifTool             = $script:PSMetaDataInjector_ExifToolPath
                            OutputDirectory      = $script:PSMetaDataInjector_OutputDirectory
                            Title                = $script:PSMetaDataInjector_Title
                            Description          = $script:PSMetaDataInjector_Description
                            Keywords             = $keywordSummary
                            HierarchicalKeywords = $hierSummary
                        }
                    }
                }
            }
        }
    }
}

Export-ModuleMember -Function Set-MediaMetadata
