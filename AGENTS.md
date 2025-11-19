# AGENTS.md — PowerShell Module Development Rules

## Scope

- このファイルは **本リポジトリ全体**に適用されるエージェント向けの**開発規約**である。
- 近い階層に `AGENTS.md` があれば、**そちらを優先**すること。
- 実装すべき仕様については、`./specs/<spec>.md`を参照すること。
- 重複する指示があった場合、`./specs/<spec>.md`より`AGENTS.md`を優先する。
- プロンプト上の明示命令が、もっとも優先される。

## Environment

- 理想的には、Windows 11 の既定 PowerShell (Windows PowerShell 5.x)とPowerShell Coreの両方で動作すること。
- PowerShellの動作バージョンが限定される場合、`#Requires -Version`を必ず指定する。上記の理想的な状態を満たすならば不要。
- PowerShellの動作バージョンが限定される場合は、その理由と互換性をREADME.mdとコード内に明記する。
- コード内の日本語が文字化けないよう、PowerShellスクリプトのファイル形式はUTF8 with BOM CRLFとする。

## Repository Layout

```powershell
<RepositoryRoot>/
  LICENSE
  README.md
  <RepositoryName>.psd1     # ← エントリポイント。Manifest-first
  <RepositoryName>.psm1     # ← 最小のブートストラップのみ
  assets/                    # 画像・サンプルデータ
  bin/                       # 外部実行ファイル（例: exiftool.exeやsqlite3.exeなど）。必要に応じて作成
  PSModules/                 # 外部PSモジュールをサブモジュールで入れる場合に使用。必要に応じて作成
  modules/                   # 機能の本体（.psm1）。1 機能 = 1 ファイルの .psm1（Public/Private を明確化）
  scripts/                   # 実行用 .ps1（ランナー）。Manifest 経由で Import する
  scripts/cmd/               # .cmd ラッパー（ExecutionPolicy 回避等）
  specs/                     # 実装する機能の仕様書
  tests/                     # Pester v5 テスト。テスト用のスクリプトはここに置く。
```

## Naming Conventions

- ディレクトリ名`modules/`、`scripts/`は小文字。ただし、PowerShellのファイル名や`PSModules`などは、PowerShell系であることをわかりやすくするためにUpperCamelCaseの名前を用いる。
- 関数名は、PowerShell承認動詞`Verb-Noun`に従う（例：`Convert-FileToUtf8BOM`）。
- ファイル名はモジュール関数名に合わせるが、**ダッシュ（`-`）は使わない**（例：`modules/ConvertFileToUtf8BOM.psm1`）。
- 公開関数は `Export-ModuleMember -Function <Name>` する。

## Module Manifest

### `./<RepositoryName>.psd1`

`<RepositoryName>.psd1`は、以下のコマンドで作成。

```powershell
New-ModuleManifest -Path <RepositoryName>.psd1
```

- 依存取り込みは **`.psd1` の `NestedModules`** に集約し、`scripts/*.ps1` からは **`.psd1` を `Import-Module`** できるようにする（詳しくは後述）。
- `NestedModules`に`modules/*.psm1`を列挙して、親子の依存を明示する。
- **`FunctionsToExport`/`CmdletsToExport`/`AliasesToExport`/`VariablesToExport` は**ワイルドカード（`'*'`）禁止。**明示列挙**します（未使用は `@()`）。
- `PrivateData.PSData` の `Tags`、`ProjectUri`、`LicenseUri`、（必要なら）`Prerelease` を整備すること。

**例：`<RepositoryName>.psd1`（抜粋）**

```powershell
@{
  RootModule           = '<RepositoryName>.psm1'
  ModuleVersion        = '0.1.0'
  CompatiblePSEditions = @('Desktop')   # PS7 を併記する場合は 'Core' も
  # PowerShellVersion  = '5.1'          # 必要に応じて

  # 依存モジュールは Manifest で宣言
  NestedModules = @(
    'modules/ConvertHealthPlanetGraphJsonToCsv.psm1'
    # 'modules/OtherPublicFunction.psm1'
  )

  # 公開 API は明示列挙（ワイルドカード禁止）
  FunctionsToExport = @(
    'Convert-HealthPlanetGraphJsonToCsv'
  )
  CmdletsToExport   = @()
  AliasesToExport   = @()
  VariablesToExport = @()

  PrivateData = @{
    PSData = @{
      Tags       = @('files','csv','healthplanet','powershell-module')
      ProjectUri = 'https://github.com/<owner>/<RepositoryName>'
      LicenseUri = 'https://github.com/<owner>/<RepositoryName>/blob/main/LICENSE'
      # Prerelease = 'preview1'
    }
  }
}
```

### `./<RepositoryName>.psm1`

Strict モードとモジュールルートの定義のみ。**`Import-Module` は書かない**。取り込みは .psd1 の NestedModules に委譲する

```powershell
Set-StrictMode -Version 3.0
$script:ModuleRoot = Split-Path -Parent $PSCommandPath
```

## Coding Rules

- このファイルと`./specs/*.md`の内容に従い、コーディングを行うこと
- 検討・作業中に何か疑問点が発生した場合、`./specs/*.md`の`## 8. Open Questions`に追加する

- Windows 11既定のPowerShell (Windows PowerShell 5.x)で動作することを優先するため、可能な限りPS5で利用可能なコマンドレット・構文を使用する。
- PS5で動作するならば、`#Requires -Version` は指定しない。
  - もし、PS5で動作せず、PowerShell Coreが必須となる場合、`#Requires -Version`を明記し、その背景を`README.md`とコメントベースヘルプに明記する。
- `Set-StrictMode -Version 3.0` 必須
- `$ErrorActionPreference = 'Stop'` 必須
- **出力の分流**: 成功系は **パイプライン出力**、情報系は `Write-Verbose` / `Write-Information`。`Write-Host` は避ける。
- **安全性**: 破壊的操作（上書き・作成）を行う関数には、`[CmdletBinding(SupportsShouldProcess = $true)]` を適用し、`-WhatIf`/`-Confirm` に対応すること。必要なら `ConfirmImpact` を調整。
- 外部コマンド呼び出しは `-ErrorAction Stop` を徹底。

### `./modules/<ModuleName>.psm1`

- 1機能 = 1ファイル
- **Public/Private を明確化**する。Public は `Export-ModuleMember -Function ...` で明示（Private は未Export）。
- コメントベースヘルプ（`.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.EXAMPLE`）を必須化。
- `Export-ModuleMember`した関数は、`<RepositoryName>.psd1`の`FunctionsToExport` でも明示する。

以下サンプル。

```powershell
...
..

function Convert-HealthPlanetGraphJsonToCsv {
<#
.SYNOPSIS
Converts a Health Planet graph JSON export to CSV.

.DESCRIPTION
The Convert-HealthPlanetGraphJsonToCsv function reads one or more graph JSON files exported from Health Planet and produces long and/or wide CSV files. The function accepts a single JSON file or a directory that contains JSON files. When a directory is provided, the function can optionally recurse into child directories. Long CSV output contains one row per metric per date, while wide CSV output pivots metrics into columns per date.

.PARAMETER InputPath
Specifies the path to a Health Planet JSON file or a directory that contains JSON files. The path may be absolute or relative.

.PARAMETER Mode
Controls which CSV shapes are produced. Long creates long-form CSV. Wide creates wide-form CSV. Both produces both files. Defaults to Long.

.PARAMETER OutputDirectory
Specifies the directory where generated CSV files are placed. When omitted, CSV files are created in the same directory as their JSON source. The directory is created automatically when it does not already exist.

.PARAMETER ApplyFormat
When supplied, metric values are rounded according to the format string metadata embedded within the JSON file (for example %.1f or %d). By default, raw values are preserved.

.PARAMETER Recurse
When InputPath is a directory, include JSON files from all subdirectories.

.PARAMETER Passthru
When supplied, the function outputs the generated objects to the pipeline in addition to writing the CSV files. The output is an ordered hashtable with FilePath, Mode, and Rows keys.

.EXAMPLE
Convert-HealthPlanetGraphJsonToCsv -InputPath ./tests/20251005-20251012.json -Mode Both

Reads the specified JSON file and writes long and wide CSV files next to the source file.

.EXAMPLE
Convert-HealthPlanetGraphJsonToCsv -InputPath ./data -OutputDirectory ./out -Recurse -ApplyFormat -Verbose

Processes every JSON file under ./data recursively, writing formatted CSV files into ./out.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $InputPath,

        [ValidateSet('Long', 'Wide', 'Both')]
        [string] $Mode = 'Long',
...
..

Export-ModuleMember -Function Convert-HealthPlanetGraphJsonToCsv
```

### `./scripts/*.ps1`

- 実行可能 .ps1。このランナーは `<RepositoryName>.psd1` を `Import-Module`する
- 型/クラス（解析時依存）が必要な特殊ケースのみ、`scripts/*.ps1`内で`using module`して`modules/<ModuleName>.psm1`を取り込むことを許可する
- モジュールに引数を渡す前の処理を主に行

以下に参考を示す。

```powershell
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string] $InputPath,

    [ValidateSet('Long', 'Wide', 'Both')]
    [string] $Mode = 'Long',

    ...
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\<RepositoryName>.psd1') -Force -ErrorAction Stop

#
# <ModuleName>.psm1に渡す引数を整形し、呼び出す前の処理
#

Convert-HealthPlanetGraphJsonToCsv @effectiveParameters
```

### `./scripts/cmd/*.cmd`

- PowerShellランナー `./script/*.ps1` をCMDから実行するためのスクリプト。
- 可能なら `pwsh` を優先、無ければ `powershell` にフォールバック。
- PowerShellの実行ポリシー対策で、`-ExecutionPolicy Bypass -File ...`で呼び出す。
- `-NoProfile -NonInteractive` を付けて 起動時間短縮と環境依存性低減。

以下に参考を示す。

```bat
@echo off
setlocal EnableExtensions
set "_ROOT=%~dp0.."
set "_SCRIPT=%_ROOT%\scripts\RunConvert.ps1"
set "_CONF=%_ROOT%\scripts\config.json"

where pwsh.exe >nul 2>&1 && (
  pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%_SCRIPT%" -ConfJsonPath "%_CONF%"
) || (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%_SCRIPT%" -ConfJsonPath "%_CONF%"
)
endlocal
```

### `./scripts/config_sample.json`

- スクリプト実行時に`-ConfigJsonPath <Config Path>`の指定がある場合のみ適用する。
- スクリプト実行時に引数の指定を容易にするために利用される。
- `-ConfigJsonPath <Config File Path>`が指定された場合で、`<Config File Path>`の内容とコマンドラインの引数が重複している場合、コマンドラインの引数の値を優先する。

### `./README.md`

- 

## Build & Test (Executable)

- Pester v5によるユニット/統合テストを `./tests/` に配置（`Invoke-Pester -CI`）
- テストファイルは`./modules/<ModuleName>.psm1`と対になるように、`./modules/<ModuleName>.Tests.ps1`を作成する
- `./assets/`にあるファイルを更新しないこと。ここにあるファイルをテスト用として利用する場合、`./tests/`にコピーすること。
- PSScriptAnalyzerをCIで走らせ、少なくとも次のルールを有効化する。`PSUseApprovedVerbs`, `PSAvoidUsingWriteHost`, `UseToExportFieldsInManifest`

- Codexが動作しているWSL上には、`pwsh`がインストールされている。動作確認やテストにはこれを利用すること。
- ただし、`pwsh`はWindows 11のシステム規定のPowerShell 5.xとは動作が一部異なるため、最終的な確認はWindows上で行う必要がある。よって、ユーザーにテスト手順を示し、そちらの環境でも動作確認するように依頼する。
