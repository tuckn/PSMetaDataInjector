Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Remove-Module PSMetaDataInjector,SetMediaMetadata,SetFrontmatter -ErrorAction SilentlyContinue
$modulePath = Join-Path $PSScriptRoot '..\PSMetaDataInjector.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'PSMetaDataInjector' {
    BeforeAll {
        try {
            $script:OriginalWhatIfPreference = Get-Variable -Name WhatIfPreference -Scope Global -ValueOnly
        }
        catch {
            $script:OriginalWhatIfPreference = $false
        }

        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
        $assetsRootCandidate = [System.IO.Path]::Combine($repoRoot, 'assets')
        if (-not (Test-Path -LiteralPath $assetsRootCandidate -PathType Container)) {
            throw "Assets directory was not found at '$assetsRootCandidate'."
        }
        $script:AssetsRoot = (Resolve-Path -LiteralPath $assetsRootCandidate).ProviderPath

        $testsRootCandidate = [System.IO.Path]::Combine($repoRoot, 'tests')
        if (-not (Test-Path -LiteralPath $testsRootCandidate -PathType Container)) {
            throw "tests directory was not found at '$testsRootCandidate'."
        }
        $script:TestsRoot = (Resolve-Path -LiteralPath $testsRootCandidate).ProviderPath

        $script:TestsDest = [System.IO.Path]::Combine($script:TestsRoot, 'dest')
        $script:OutputRoot = [System.IO.Path]::Combine($script:TestsRoot, 'out')

        foreach ($folder in @($script:TestsDest, $script:OutputRoot)) {
            if (Test-Path -LiteralPath $folder) {
                Remove-Item -LiteralPath $folder -Recurse -Force
            }
        }

        $excludePatterns = @([System.IO.Path]::Combine($script:TestsDest, '*'), [System.IO.Path]::Combine($script:OutputRoot, '*'))
        $script:SourceAssets = Get-ChildItem -LiteralPath $script:AssetsRoot -File -Recurse | Where-Object {
            foreach ($pattern in $excludePatterns) {
                if ($_.FullName -like $pattern) { return $false }
            }
            return $true
        }

        $preferredExifTool = [System.IO.Path]::Combine($repoRoot, 'bin', 'exiftool')
        if (-not (Test-Path -LiteralPath $preferredExifTool -PathType Leaf)) {
            $alternateExifTool = [System.IO.Path]::Combine($repoRoot, 'bin', 'exiftool.exe')
            if (Test-Path -LiteralPath $alternateExifTool -PathType Leaf) {
                $preferredExifTool = $alternateExifTool
            }
        }

        if (-not (Test-Path -LiteralPath $preferredExifTool -PathType Leaf)) {
            throw 'Test exiftool was not found. Ensure ./bin/exiftool (or exiftool.exe) exists before running tests.'
        }

        $script:TestExifToolPath = (Resolve-Path -LiteralPath $preferredExifTool).ProviderPath
    }

    BeforeEach {
        Set-Variable -Name WhatIfPreference -Value $false -Scope Global

        foreach ($folder in @($script:TestsDest, $script:OutputRoot)) {
            if (Test-Path -LiteralPath $folder) {
                Remove-Item -LiteralPath $folder -Recurse -Force
            }
            New-Item -ItemType Directory -Path $folder | Out-Null
        }

        foreach ($source in $script:SourceAssets) {
            $relative = $source.FullName.Substring($script:AssetsRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $target = [System.IO.Path]::Combine($script:TestsDest, $relative)
            $targetDir = [System.IO.Path]::GetDirectoryName($target)
            if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            Copy-Item -LiteralPath $source.FullName -Destination $target -Force
        }
    }

    AfterAll {
        Set-Variable -Name WhatIfPreference -Value $script:OriginalWhatIfPreference -Scope Global
    }

    Context 'Get-DateFromFileName' {
        It 'parses supported timestamp patterns' {
            InModuleScope SetMediaMetadata -ScriptBlock {
                $samples = @(
                    @{ File = '19990102T174300+0900.jpg'; Expected = '1999-01-02T17:43:00' },
                    @{ File = 'FP20090511182604_LED.jpg'; Expected = '2009-05-11T18:26:04' },
                    @{ File = 'Screenshot 2025-11-02 073031.png'; Expected = '2025-11-02T07:30:31' },
                    @{ File = '2015-07-02 12-16-05.jpg'; Expected = '2015-07-02T12:16:05' },
                    @{ File = 'screencapture-VirtualBox_Windows XP Mode_15_10_2016_07_49_43.png'; Expected = '2016-10-15T07:49:43' }
                )

                foreach ($sample in $samples) {
                    $result = Get-DateFromFileName -FileName $sample.File
                    $result | Should -Not -BeNull
                    $result.ToString("yyyy-MM-dd'T'HH:mm:ss") | Should -Be $sample.Expected
                }
            }
        }
    }

    Context 'Set-MediaMetadata' {
        It 'infers timestamps when requested' {
            $filePath = [System.IO.Path]::Combine($script:TestsDest, '19990102T174300+0900.jpg')
            $expectedExifToolPath = $script:TestExifToolPath

            InModuleScope SetMediaMetadata -ScriptBlock {
                param($fp, $toolPath)
                Mock Invoke-PSMetaDataInjectorExifTool { param($ExecutablePath, $Arguments) return 0 } -ModuleName SetMediaMetadata

                $result = Set-MediaMetadata -InputPath $fp -InferCreatedDate -Passthru -ExifToolPath $toolPath -WhatIf:$false -Confirm:$false

                Assert-MockCalled Invoke-PSMetaDataInjectorExifTool -Times 1 -ParameterFilter {
                    $ExecutablePath -eq $toolPath -and
                    $Arguments[-1] -eq $fp -and
                    $Arguments -contains '-overwrite_original' -and
                    $Arguments -contains "-XMP-exif:DateTimeOriginal=1999-01-02T17:43:00"
                }

                $result.Timestamp | Should -Be '1999-01-02T17:43:00'
            } -ArgumentList $filePath, $expectedExifToolPath
        }

        It 'falls back to CreatedDate when inference fails' {
            $filePath = [System.IO.Path]::Combine($script:TestsDest, '19990102T174300+0900.jpg')
            $toolPath = $script:TestExifToolPath
            $manualDate = Get-Date '2024-10-05T04:03:02'

            InModuleScope SetMediaMetadata -ScriptBlock {
                param($fp, $tp, $manual)
                Mock Invoke-PSMetaDataInjectorExifTool { param($ExecutablePath, $Arguments) return 0 } -ModuleName SetMediaMetadata
                Mock Get-DateFromFileName { return $null } -ModuleName SetMediaMetadata

                $result = Set-MediaMetadata -InputPath $fp -InferCreatedDate -CreatedDate $manual -Passthru -ExifToolPath $tp -WhatIf:$false -Confirm:$false

                Assert-MockCalled Invoke-PSMetaDataInjectorExifTool -Times 1 -ParameterFilter {
                    $Arguments -contains "-XMP-exif:DateTimeOriginal=2024-10-05T04:03:02"
                }

                $result.Timestamp | Should -Be '2024-10-05T04:03:02'
            } -ArgumentList $filePath, $toolPath, $manualDate
        }

        It 'applies title, description, and keywords when provided' {
            $filePath = [System.IO.Path]::Combine($script:TestsDest, '19990102T174300+0900.jpg')
            $toolPath = $script:TestExifToolPath
            $titleValue = 'Kyoto Sunrise'
            $descriptionValue = '意図して脳細胞を増やすことについての気づきを綴った内容'
            $keywords = @(
                'IT (information technology)|programming language|JavaScript',
                'IT (information technology)|software|application|WinMerge'
            )

            InModuleScope SetMediaMetadata -ScriptBlock {
                param($fp, $tp, $titleParam, $descParam, $keywordParam)
                Mock Invoke-PSMetaDataInjectorExifTool { param($ExecutablePath, $Arguments) return 0 } -ModuleName SetMediaMetadata

                $result = Set-MediaMetadata -InputPath $fp -InferCreatedDate -Title $titleParam -Description $descParam -Keywords $keywordParam -ExifToolPath $tp -Passthru -WhatIf:$false -Confirm:$false

                Assert-MockCalled Invoke-PSMetaDataInjectorExifTool -Times 1 -ParameterFilter {
                    ($Arguments -contains "-XMP-dc:Title-x-default=$titleParam") -and
                    ($Arguments -contains "-XMP-photoshop:Headline=$titleParam") -and
                    ($Arguments -contains "-XMP-dc:Description-x-default=$descParam") -and
                    ($Arguments -contains '-XMP-lr:hierarchicalSubject=') -and
                    ($Arguments | Where-Object { $_ -like '-XMP-lr:hierarchicalSubject+*' }).Count -eq 2
                }

                $result.Title | Should -Be $titleParam
                $result.Description | Should -Be $descParam
                $result.Keywords | Should -Contain 'JavaScript'
                $result.HierarchicalKeywords | Should -Contain 'IT (information technology)|software|application|WinMerge'
            } -ArgumentList $filePath, $toolPath, $titleValue, $descriptionValue, $keywords
        }

        It 'skips files when no metadata is available' {
            $filePath = [System.IO.Path]::Combine($script:TestsDest, '19990102T174300+0900.jpg')
            $toolPath = $script:TestExifToolPath

            InModuleScope SetMediaMetadata -ScriptBlock {
                param($fp, $tp)
                Mock Invoke-PSMetaDataInjectorExifTool { param($ExecutablePath, $Arguments) return 0 } -ModuleName SetMediaMetadata

                Set-MediaMetadata -InputPath $fp -ExifToolPath $tp -WhatIf:$false -Confirm:$false

                Assert-MockCalled Invoke-PSMetaDataInjectorExifTool -Times 0
            } -ArgumentList $filePath, $toolPath
        }

        It 'writes files to the designated output directory when specified' {
            $toolPath = $script:TestExifToolPath
            $testsDest = $script:TestsDest
            $outputRoot = $script:OutputRoot

            InModuleScope SetMediaMetadata -ScriptBlock {
                param($sourceRoot, $outRoot, $tp)
                Mock Invoke-PSMetaDataInjectorExifTool { param($ExecutablePath, $Arguments) return 0 } -ModuleName SetMediaMetadata

                $results = Set-MediaMetadata -InputPath $sourceRoot -Recurse -InferCreatedDate -Passthru -OutputDirectory $outRoot -ExifToolPath $tp -WhatIf:$false -Confirm:$false | Sort-Object FilePath

                Assert-MockCalled Invoke-PSMetaDataInjectorExifTool -Times 4 -ParameterFilter {
                    $ExecutablePath -eq $tp -and $Arguments[-1] -like ($outRoot + '*')
                }
                $results.Count | Should -Be 4
                (($results | Where-Object { $_.SourcePath -notlike ($sourceRoot + '*') }) | Measure-Object).Count | Should -Be 0
                (($results | Where-Object { $_.FilePath -notlike ($outRoot + '*') }) | Measure-Object).Count | Should -Be 0
                ($results | Where-Object { $_.FilePath -like '*Screenshot 2025-11-02 073031.png' }).FilePath | Should -Match 'Screenshot 2025-11-02 073031\.png'
            } -ArgumentList $testsDest, $outputRoot, $toolPath

            (Get-ChildItem -LiteralPath $script:OutputRoot -File -Recurse | Measure-Object).Count | Should -Be 4
        }

        It 'respects WhatIf mode' {
            $filePath = [System.IO.Path]::Combine($script:TestsDest, '19990102T174300+0900.jpg')
            $toolPath = $script:TestExifToolPath

            InModuleScope SetMediaMetadata -ScriptBlock {
                param($fp, $tp)
                Mock Invoke-PSMetaDataInjectorExifTool { param($ExecutablePath, $Arguments) return 0 } -ModuleName SetMediaMetadata

                Set-MediaMetadata -InputPath $fp -InferCreatedDate -WhatIf -ExifToolPath $tp -Confirm:$false

                Assert-MockCalled Invoke-PSMetaDataInjectorExifTool -Times 0
            } -ArgumentList $filePath, $toolPath
        }

        It 'resolves wildcard InputPath values' {
            $wildcardRoot = Join-Path $script:TestsDest 'wildcards'
            if (-not (Test-Path -LiteralPath $wildcardRoot)) {
                New-Item -ItemType Directory -Path $wildcardRoot | Out-Null
            }

            $sample = Get-ChildItem -LiteralPath $script:TestsDest -Filter '*.jpg' | Select-Object -First 1
            if (-not $sample) {
                throw 'No JPG sample was found to validate wildcard handling.'
            }

            $copied = Copy-Item -LiteralPath $sample.FullName -Destination $wildcardRoot -Force -PassThru
            $copiedPath = (Resolve-Path -LiteralPath $copied.FullName).ProviderPath
            $pattern = Join-Path $wildcardRoot '*.jpg'
            $toolPath = $script:TestExifToolPath
            $manualDate = Get-Date '2024-12-01T12:00:00'

            InModuleScope SetMediaMetadata -ScriptBlock {
                param($inputPattern, $expectedFile, $tp, $manual)
                Mock Invoke-PSMetaDataInjectorExifTool { param($ExecutablePath, $Arguments) return 0 } -ModuleName SetMediaMetadata

                $result = Set-MediaMetadata -InputPath $inputPattern -CreatedDate $manual -ExifToolPath $tp -Passthru -WhatIf:$false -Confirm:$false

                Assert-MockCalled Invoke-PSMetaDataInjectorExifTool -Times 1 -ParameterFilter {
                    $Arguments[-1] -eq $expectedFile
                }

                $result.FilePath | Should -Be $expectedFile
                $result.Timestamp | Should -Be '2024-12-01T12:00:00'
            } -ArgumentList $pattern, $copiedPath, $toolPath, $manualDate
        }
    }

    Context 'Set-MarkdownFrontmatter' {
        It 'writes new frontmatter with generated noteId and tags' {
            $tempFile = Join-Path $TestDrive 'frontmatter.md'
            Set-Content -LiteralPath $tempFile -Value "# Heading$([Environment]::NewLine)" -Encoding utf8

            InModuleScope SetFrontmatter -ScriptBlock {
                param($path)
                Set-MarkdownFrontmatter -Path $path -Title 'git.exeがcore.autocrlfを無視する' -Description '' -Date (Get-Date '2018-01-30') -Tags @('JavaScript', 'React', 'WinMerge')
            } -ArgumentList $tempFile

            $content = Get-Content -LiteralPath $tempFile -Raw
            $content | Should -Match '^---'
            $content | Should -Match 'noteId: "[0-9a-fA-F-]{36}"'
            $content | Should -Match 'title: "git\.exeがcore\.autocrlfを無視する"'
            $content | Should -Match 'tags: \["JavaScript", "React", "WinMerge"\]'
            $lines = $content -split [Environment]::NewLine
            $closingIndex = [Array]::LastIndexOf($lines, '---')
            $lines[$closingIndex + 1] | Should -Be ''
            $lines[$closingIndex + 2] | Should -Be '# Heading'
        }

        It 'preserves existing noteId when present and updates other fields' {
            $tempFile = Join-Path $TestDrive 'frontmatter-existing.md'
            $original = @(
                '---'
                'noteId: "d3f29c4e-8b6a-4f3e-9e3b-2c1f5e9a7c1a"'
                'title: "Old"'
                'description: "old"'
                'date: 2000-01-01'
                'tags: ["foo"]'
                '---'
                ''
                '# Heading'
            ) -join [Environment]::NewLine
            Set-Content -LiteralPath $tempFile -Value $original -Encoding utf8

            InModuleScope SetFrontmatter -ScriptBlock {
                param($path)
                Set-MarkdownFrontmatter -Path $path -Title 'New Title' -Description 'Updated' -Date (Get-Date '2024-10-05') -Tags @('JavaScript')
            } -ArgumentList $tempFile

            $content = Get-Content -LiteralPath $tempFile -Raw
            $content | Should -Match 'noteId: "d3f29c4e-8b6a-4f3e-9e3b-2c1f5e9a7c1a"'
            $content | Should -Match 'title: "New Title"'
            $content | Should -Match 'description: "Updated"'
            $content | Should -Match 'tags: \["JavaScript"\]'
        }

        It 'generates noteId when existing frontmatter lacks one' {
            $tempFile = Join-Path $TestDrive 'frontmatter-missing-noteid.md'
            $original = @(
                '---'
                'title: "Old"'
                'description: "old"'
                'date: 2000-01-01'
                '---'
                ''
                '# Heading'
            ) -join [Environment]::NewLine
            Set-Content -LiteralPath $tempFile -Value $original -Encoding utf8

            InModuleScope SetFrontmatter -ScriptBlock {
                param($path)
                Set-MarkdownFrontmatter -Path $path -Title 'Another Title' -Description 'Desc' -Date (Get-Date '2024-11-09') -Tags @()
            } -ArgumentList $tempFile

            $content = Get-Content -LiteralPath $tempFile -Raw
            $content | Should -Match 'noteId: "[0-9a-fA-F-]{36}"'
        }
    }
}
