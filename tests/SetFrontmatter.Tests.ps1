Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Remove-Module PSMetaDataInjector,SetMediaMetadata,SetFrontmatter -ErrorAction SilentlyContinue
$modulePath = Join-Path $PSScriptRoot '..\PSMetaDataInjector.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'Set-MarkdownFrontmatter' {
    BeforeAll {
        $script:TempRoot = Join-Path $PSScriptRoot 'frontmatter-temp'
        if (Test-Path -LiteralPath $script:TempRoot) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:TempRoot | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:TempRoot) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
    }

    BeforeEach {
        if (-not (Test-Path -LiteralPath $script:TempRoot)) {
            New-Item -ItemType Directory -Path $script:TempRoot | Out-Null
        }
        Get-ChildItem -LiteralPath $script:TempRoot -Force | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }

    It 'inserts frontmatter when DateTitle is provided' {
        $file = Join-Path $script:TempRoot 'DateTitle.md'
        @'
# Heading
Body content
'@ | Set-Content -LiteralPath $file -Encoding utf8BOM

        Set-MarkdownFrontmatter -Path $file `
            -DateTitle '2018-05-06 GhostscriptでPDFサイズを圧縮する' `
            -Description '' `
            -Tags 'JavaScript','Git','WinMerge' `
            -Files 'ss:/20190102T070750+0900.png','ss:/20190102T070816+0900.png' `
            -WhatIf:$false -Confirm:$false

        $content = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
        $content | Should -Match '^---'
        $content | Should -Match 'noteId: "[0-9a-fA-F-]{36}"'
        $content | Should -Match 'title: "GhostscriptでPDFサイズを圧縮する"'
        $content | Should -Match 'date: 2018-05-06'
        $content | Should -Match 'tags: \["JavaScript", "Git", "WinMerge"\]'
        $content | Should -Match 'files:\s*\r?\n  - "ss:/20190102T070750\+0900\.png"\s*\r?\n  - "ss:/20190102T070816\+0900\.png"'
        $content | Should -Match '---\s*\r?\n\s*\r?\n# Heading'
    }

    It 'parses compact DateTitle format and emits metadata via Passthru' {
        $file = Join-Path $script:TempRoot 'CompactDateTitle.md'
        'Initial body' | Set-Content -LiteralPath $file -Encoding utf8BOM

        $result = Set-MarkdownFrontmatter -Path $file -DateTitle '20180506T073031 Compact Title' -Passthru -WhatIf:$false -Confirm:$false

        $result | Should -Not -BeNullOrEmpty
        $result.Title | Should -Be 'Compact Title'
        $result.Date | Should -Be '2018-05-06'
        $result.NoteId | Should -Not -BeNullOrEmpty

        $updated = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
        $updated | Should -Match 'date: 2018-05-06'
        $updated | Should -Match 'title: "Compact Title"'
    }

    It 'preserves existing noteId and custom metadata when updating other fields' {
        $file = Join-Path $script:TempRoot 'ExistingFrontmatter.md'
        @'
---
noteId: "1234"
title: "Original Title"
description: "Original description"
date: 2024-01-01
tags: ["alpha"]
customFlag: true
---
Body
'@ | Set-Content -LiteralPath $file -Encoding utf8BOM

        Set-MarkdownFrontmatter -Path $file -Title 'Updated Title' -Description 'Updated description' -Date (Get-Date '2024-11-09') -Tags 'beta' -WhatIf:$false -Confirm:$false

        $content = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
        $content | Should -Match 'noteId: "1234"'
        $content | Should -Match 'title: "Updated Title"'
        $content | Should -Match 'description: "Updated description"'
        $content | Should -Match 'date: 2024-11-09'
        $content | Should -Match 'tags: \["beta"\]'
        $content | Should -Match 'customFlag: true'
    }

    It 'adds a missing noteId without altering other values' {
        $file = Join-Path $script:TempRoot 'MissingNoteId.md'
        @'
---
title: "Existing Title"
description: ""
date: 2024-02-01
tags: ["existing"]
files:
  - "ss:/example.png"
---
Body
'@ | Set-Content -LiteralPath $file -Encoding utf8BOM

        Set-MarkdownFrontmatter -Path $file -WhatIf:$false -Confirm:$false

        $content = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
        $content | Should -Match 'noteId: "[0-9a-fA-F-]{36}"'
        $content | Should -Match 'title: "Existing Title"'
        $content | Should -Match 'files:\s*\r?\n  - "ss:/example\.png"'
    }

    It 'preserves UTF-16 encoding when writing frontmatter' {
        $file = Join-Path $script:TempRoot 'UnicodeEncoding.md'
        'Body only' | Set-Content -LiteralPath $file -Encoding Unicode

        Set-MarkdownFrontmatter -Path $file -Title 'Unicode Note' -Date (Get-Date '2024-11-11') -Description '' -Tags 'unicode' -WhatIf:$false -Confirm:$false

        $bytes = [System.IO.File]::ReadAllBytes($file)
        $bytes.Length | Should -BeGreaterThan 2
        $bytes[0] | Should -Be 0xFF
        $bytes[1] | Should -Be 0xFE
    }

    It 'keeps UTF-8 without BOM when updating existing frontmatter' {
        $file = Join-Path $script:TempRoot 'Utf8NoBom.md'
        $initial = @'
---
noteId: "abcd"
title: "Initial"
description: ""
date: 2024-01-01
tags: ["tag"]
---
Body
'@
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($file, $initial, $utf8NoBom)

        Set-MarkdownFrontmatter -Path $file -Description 'Updated' -WhatIf:$false -Confirm:$false

        $bytes = [System.IO.File]::ReadAllBytes($file)
        $bytes.Length | Should -BeGreaterThan 3
        $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasBom | Should -BeFalse
    }
}
