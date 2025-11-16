# SetFrontmatter — Markdown Frontmatter Injector

Update YAML frontmatter at the top of Markdown notes.

- Status: Draft (tracking Set-MarkdownFrontmatter module work)
- Owner: @tuckn
- Links: modules/SetFrontmatter.psm1, scripts/SetFrontmatter.ps1, tests/SetFrontmatter.Tests.ps1

## 1. Summary (Introduction)

Markdownファイルの先頭に Frontmatter（YAMLブロック）を挿入し、`noteId`、`title`、`description`、`date`、`tags`、`files` を登録する。すでにFrontmatterが存在する場合、指定したキーのみを更新し、残りのキーは変更しない。モジュール関数（`./modules/SetFrontmatter.psm1`）とラッパースクリプト（`scripts/SetFrontmatter.ps1` / `scripts/cmd/SetFrontmatter.cmd`）の両方を提供する。

## 2. Intent (User Story / Goal)

As a note taker,
I want consistent frontmatter metadata (GUID, title, tags, date, files),
so that my Markdown vault stays searchable by static-site generators and note tools.

## 3. Scope

### In-Scope

- 指定されたMarkdownファイルの先頭にある `---` 区切り文字で区切られた YAMLブロックの管理。
- ファイルごとに `noteId` GUID を自動的に発行/保存。
- 引数で指定されたメタデータをFrontmatterとして更新する
- PowerShellモジュール（.psm1）とそれをラッパーするスクリプト（.ps1）の提供
- PowerShellスクリプト（.ps1）をラッパーするCMDスクリプト（.cmd）の提供

### Non-Goals

- Markdown本文のコンテンツ（見出し、リフローなど）の操作。
- Frontmatter外に保存されたメタデータ（HTML コメント、フッターなど）の管理。
- Frontmatter検出以降のMarkdownの構文解析（AST 処理なし）。

## 4. Contract (API / CLI / Data)

### 4.1 Module API (`Set-MarkdownFrontmatter`)

| Param       | Type            | Req | Default | Notes |
|-------------|-----------------|-----|---------|-------|
| `-Path`     | string          | ✓   | --      | File path; resolved via `Resolve-Path` |
| `-Title`    | string          | --   | --      | Empty/whitespace rejected |
| `-DateTitle`    | string          | --   | --      | Empty/whitespace rejected |
| `-Description` | string       | --   | `""`   | `null` treated as empty |
| `-Date`     | datetime        | --   | --       | Serialized as `yyyy-MM-dd` |
| `-Tags`     | string[]        | --   | `[]`    | Output as YAML array |
| `-Files`    | string[]        | --   | `[]`    | Output as YAML array |
| `-Passthru`      | switch        | —   | false   | Emits objects (SourcePath, Title, Description, etc.) |

### 4.2 Wrapper CLI

**`scripts/SetFrontmatter.ps1`**
- 受け取る引数は、Module APIと同等

**`scripts/cmd/SetFrontmatter.cmd`**
- 受け取ったすべての引数を.ps1スクリプトに渡す

### 4.3 Data Spec

#### Example: 新規作成例

```markdown
---
noteId: "d3f29c4e-8b6a-4f3e-9e3b-2c1f5e9a7c1a"
title: "git.exeがcore.autocrlfを無視する"
description: ""
date: 2018-01-30
tags: ["JavaScript", "Git", "WinMerge"]
files:
  - "ss:/20190102T070750+0900.png"
  - "ss:/20190102T070816+0900.png"
  - "ss:/20190102T071812+0900.png"
  - "ss:/20190102T072705+0900.png"
---

本文…
````

## 5. Rules & Invariants

- **MUST** 指定されたMarkdown本文の1行目にFrontmatterを挿入する。
- **MUST** Frontmatterを閉じる `---` とMarkdown本文の間に1行の空行を挿入する。
- **MUST** Frontmatter内の`noteID`が未定義、または空欄だった場合、GUIDを生成して設定する。
- **MUST** Fronmatterの追加か更新があり、Markdownファイルを保存する場合、元のファイルエンコーディグで保存する。
- **SHOULD** Frontmatter内の並び: noteId → title → description → date → tags→ files.

## 6. Acceptance

### 6.1 Criteria

- `7. Quality (Non-Functional Gates)`に記載しているすべてのGateを満たす
- `README.md`に、現状態の使用方法と仕様の説明が反映されている

### 6.2 Scenarios (Gherkin)

```gherkin
Scenario: DateTitleでTitleとDateを更新
  Given まだFrontmatterが挿入されていないMarkdown "2018-05-06 GhostscriptでPDFサイズを圧縮する.md"
  When 引数`DateTitle`に"2018-05-06 GhostscriptでPDFサイズを圧縮する"を指定してスクリプトを実行する
  Then 引数で指定された文字列先頭が`yyyy-MM-dd`または"yyyyMMddThhmmss"であれば、それをDateと解釈して切り出す
  And 指定されたMarkdownsファイルの1行目にFrontmatterを追加する。
  And GUIDを生成し`noteId`に設定、`Title`に"GhostscriptでPDFサイズを圧縮する"、`date`に"2018-05-06"を設定、

Scenario: 既存のnoteIdを優先するが他の項目は更新
  Given Frontmatterの定義がすでにあり、`noteId`が"1234"であるMarkdown
  When 引数`Title`に"New Title"、引数`Description`に"New Description"、引数`Date`に"2024-11-09"を指定してスクリプトを実行する
  Then `noteId`は"1234"のまま、Title、Description、Dateが指定の値に更新される

Scenario: Frontmatterの定義がすでにあるがnoteIdの定義がない
  Given Frontmatterの定義がすでにあるがnoteIdの定義がないMarkdownファイル
  When 引数`Path`にMarkdownのファイルパスのみを指定してスクリプトを実行する
  Then Markdown内のFrontmatterに`noteId`が追加され、GUID値が設定される
```

## 7. Quality (Non-Functional Gates)

| Attribute       | Gate                                      |
|-----------------|-------------------------------------------|
| Static analysis | PSScriptAnalyzer 0 errors/warnings        |
| Tests           | `Invoke-Pester -CI` succeeds (pwsh)        |
| Encoding        | Output encoded as UTF-8 with BOM           |
| Idempotence     | Repeated runs with same inputs keep file stable |

## 8. Open Questions


## 9. Decisions & Rationale

- PowerShell 5.xの規定で対応しているGUIDを`noteId` として採用

## 10. References & Changelog

- 2025-11-15: 新規作成
