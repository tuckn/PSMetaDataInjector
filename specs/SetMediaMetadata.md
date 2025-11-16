# SetMediaMetadata — Media Metadata Injector

メディアファイルにメタデータを書き込むPowerShellモジュール。

- Status: Active (feature-complete, ongoing polish)
- Owner: @tuckn
- Links: modules/SetMediaMetadata.psm1, scripts/SetMediaMetadata.ps1/.cmd, tests/SetMediaMetadata.Tests.ps1, README.md

## 1. Summary (Introduction)

Exiftoolを利用し、メディアファイルにメタデータを書き込む。書き込み先のタグは、Lightroom Classicに合わせている。ファイル名から生成日時タグを書き込む機能がある他、タイトル、概要、階層キーワードに対応。ファイル単位の指定、フォルダ単位の指定が可能。

## 2. Intent (User Story / Goal)

As a content curator,
I want to normalize image metadata (created datetime, title, keywords) in bulk,
so that Lightroom, DAM tools, and AI workflows read consistent tags regardless of source filenames.

## 3. Scope

### In-Scope

- Exiftoolで対応しているメディアファイル、かつXMPデータがき込み可能なメディア形式（.png、.jpgなど）
- ファイル単体指定、複数ファイル指定、フォルダ指定
- ファイル名パターンからのタイムスタンプ推論
- 引数で指定されたメタデータ情報をXMPとして書き込む
- PowerShellモジュール（.psm1）とそれをラッパーするスクリプト（.ps1）の提供
- PowerShellスクリプト（.ps1）をラッパーするCMDスクリプト（.cmd）の提供

### Non-Goals

- Exiftoolで対応していないメディアファイル
- Exiftoolバイナリのインストールまたは管理
- メタデータ以外のファイル内容の編集

## 4. Contract (API / CLI / Data)

### 4.1 Module API (`Set-MediaMetadata`)

| Param            | Type          | Req | Default | Notes |
|------------------|---------------|-----|---------|-------|
| `-InputPath`     | string        | ✓   | —       | File or directory; wildcard + pipeline supported |
| `-Recurse`       | switch        | —   | false   | Directory traversal |
| `-OutputDirectory` | string      | —   | —       | Copy/modify files under this root |
| `-InferCreatedDate` | switch     | —   | false   | メディアの生成日時をファイル名から推測 |
| `-CreatedDate`   | datetime?     | —   | null    | メディアの生成日時を直接指定|
| `-Title`         | string        | —   | null    | Trims whitespace; empty ignored |
| `-Description`   | string        | —   | null → "" | Null normalized to empty string |
| `-Keywords`      | string[]      | —   | null    | Lightroom Classicの階層タグに対応 |
| `-ExifToolPath`  | string        | —   | auto    | Resolves via PATH when omitted |
| `-Passthru`      | switch        | —   | false   | Emits objects (SourcePath, FilePath, Timestamp, etc.) |

### 4.2 Wrapper CLI
 
**`scripts/SetMediaMetadata.ps1`**
- 受け取る引数は、Module APIと同等
- `-ConfJsonPath <string>`の指定により、設定ファイルからも引数を指定可能
- 受け取った引数と設定ファイルの項目が重複する場合、引数の値を優先

**`scripts/cmd/SetMediaMetadata.cmd`**
- 受け取ったすべての引数を.ps1スクリプトに渡す

### 4.3 Data Spec

#### Example: ファイル名から日時の変換

- `*20180124T043720+0900*.png`
- `*20180124043720*.png`
- `*2018-01-24 043720*.png`
- `*2018-01-24_04-37-20*.png`
- `*2018_01_24_04_37_20*.png`
- `*20180124_043720*.png`
- `*24_01_2018 04_37_20*.png`
- `2018-01-24*.png` 時刻不明
- `*1516736240*.png` UNIXエポック

`*`は0文字以上の任意の文字列を示す。

#### Example: XMP - Created DateTiem

```xml
<exif:DateTimeOriginal>2018-01-24T04:37:20</exif:DateTimeOriginal>
<photoshop:DateCreated>2018-01-24T04:37:20</photoshop:DateCreated>
<xmp:CreateDate>2018-01-24T04:37:20</xmp:CreateDate>
```

#### Example: XMP - Title

```xml
<dc:title>
   <rdf:Alt>
      <rdf:li xml:lang="x-default">タイトル</rdf:li>
   </rdf:Alt>
</dc:title>
```

#### Example: XMP - Description

```xml
<dc:description>
   <rdf:Alt>
      <rdf:li xml:lang="x-default">意図して脳細胞を増やすことについての気づきを綴った内容</rdf:li>
   </rdf:Alt>
</dc:description>
```

#### Example 1: XMP - Keywords

```powershell
-Keywords "JavaScript", "React", "WinMerge"
```

```xml
<dc:subject>
   <rdf:Bag>
      <rdf:li>IT (information technology)</rdf:li>
      <rdf:li>JavaScript</rdf:li>
      <rdf:li>React</rdf:li>
      <rdf:li>WinMerge</rdf:li>
   </rdf:Bag>
</dc:subject>

<lr:weightedFlatSubject>
   <rdf:Bag>
      <rdf:li>JavaScript</rdf:li>
      <rdf:li>React</rdf:li>
      <rdf:li>WinMerge</rdf:li>
   </rdf:Bag>
</lr:weightedFlatSubject>
```

#### Example 2: XMP - Keywords

```powershell
-Keywords "IT (information technology)|programming language|JavaScript", "IT (information technology)|programming language|JavaScript|React", "IT (information technology)|software|application|WinMerge"
```

```xml
<dc:subject>
   <rdf:Bag>
      <rdf:li>IT (information technology)</rdf:li>
      <rdf:li>JavaScript</rdf:li>
      <rdf:li>React</rdf:li>
      <rdf:li>WinMerge</rdf:li>
      <rdf:li>application</rdf:li>
      <rdf:li>programming language</rdf:li>
      <rdf:li>software</rdf:li>
   </rdf:Bag>
</dc:subject>

<lr:weightedFlatSubject>
   <rdf:Bag>
      <rdf:li>JavaScript</rdf:li>
      <rdf:li>React</rdf:li>
      <rdf:li>WinMerge</rdf:li>
   </rdf:Bag>
</lr:weightedFlatSubject>

<lr:hierarchicalSubject>
   <rdf:Bag>
      <rdf:li>IT (information technology)|programming language|JavaScript</rdf:li>
      <rdf:li>IT (information technology)|programming language|JavaScript|React</rdf:li>
      <rdf:li>IT (information technology)|software|application|WinMerge</rdf:li>
   </rdf:Bag>
</lr:hierarchicalSubject>
```

## 5. Rules & Invariants

- **SHOULD** Windows 10/11の規定であるWindows PowerShell 5.xとPowerShell Coreの両方で動作
- **MUST** メタデータの更新は`exiftool`で行う
- **MUST** 更新前と後で更新内容に変化がない場合、書き込みは行わず、処理がスキップしたことをメッセージで通知する
- **MUST** 更新前と後で更新内容に変化がない場合、書き込みは行わず、処理がスキップしたことをメッセージで通知する
- **MUST** `-OutputDirectory`の指定がない場合、既存のファイルを上書きする
- **MUST** `-Passthru`のオブジェクトには、SourcePath、FilePath、Timestamp、Title、Description、Keywords、などを含む
- **MAY** `-Passthru`のオブジェクトに必要と判断した値があれば、自由に追加して良い

### Created DateTime

- **MUST** `-InferCreatedDate`が設定された場合、本仕様書の`4.3 Data Spec`の`Example: ファイル名から日時の変換`に記載されている例を参照し、ファイル名から生成日時を解析する
- **MUST** `-InferCreatedDate`と`-CreatedDate`が同時に指定された場合、まずはファイル名から日時を推測し、もしそれが失敗したら`-CreatedDate`の値を採用する
- **MUST** 時刻の書式は `YYYY-MM-DDThh:mm:ss`。タイムゾーンの書き込みは行わない
- **MUST** 時刻が不明な場合は、00:00:00とする
- **MUST** 書き込むメタデータは、本仕様書の`4.3 Data Spec`の`Example: XMP - Created DateTiem`に記載されている例を参照すること

### Title / Description

- **MUST** `-Title`が設定された場合、本仕様書の`4.3 Data Spec`の`Example: XMP - Title`に記載されている例を参照し、メタデータを更新する
- **MUST** `-Description`が設定された場合、本仕様書の`4.3 Data Spec`の`Example: XMP - Description`に記載されている例を参照し、メタデータを更新する

### Keywords

- **MUST** `-Keywords`が設定された場合、本仕様書の`4.3 Data Spec`の`Example 1: XMP - Keywords`および`Example 2: XMP - Keywords`に記載されている例を参照し、メタデータを更新する
- **MUST** `-Keywords`で`|`を含む文字列が指定され場合、それを階層キーワードとして解釈する。
- **MUST** 書き込むキーワードは、大文字・小文字は区別する（例: `Apple`と`apple`は別）

## 6. Acceptance

### 6.1 Criteria

- `7. Quality (Non-Functional Gates)`に記載しているすべてのGateを満たす
- `README.md`に、現状態の使用方法と仕様の説明が反映されている

### 6.2 Scenarios (Gherkin)

```gherkin
Scenario: ファイル名から生成日時を推測してメタデータを書き込む
  Given "19990102T174300+0900.jpg"
  When 引数に`InferCreatedDate`と`Passthur`を指定してスクリプトを実行する
  Then exiftoolを1回呼び出し、生成日時`1999-01-02T17:43:00`であるXMPメタデータを対象のファイルに書き込む
  And Passthruオブジェクトに"1999-01-02T17:43:00"が含まれる。

Scenario: 指定された生成日時のメタデータを書き込む
  Given "Screenshot_AsusH370PRO.png"
  When 引数に`CreatedDate "2022-03-02"`を指定してスクリプトを実行する
  Then exiftoolを1回呼び出し、生成日時`2022-03-02T00:00:00`であるXMPメタデータを対象のファイルに書き込む

Scenario Outline: InferCreatedDateの日時推測失敗時にCreatedDateを適用
  Given <input>
  When 引数に`-InferCreatedDate`と`-CreatedDate "<fallbackDate>"`を指定してスクリプトを実行する
  Then 生成日時を示すXMPメタデータに<writtenDate>が書き込まれる
Examples:
  | input | fallbackDate | writtenDate |
  | Screenshot_AsusH370PRO.png | 2025-01-01T00:00:00 | 2025-01-01T00:00:00 |
  | 2009-01-13_Screenshot_HTC-S22HT.png | 2025-01-01T00:00:00 | 2009-01-13T00:00:00 |

Scenario: 入力のフォルダ対応と出力先フォルダの指定
  When 引数に`InferCreatedDate`、`InputPath "./assets"`、`OutputDirectory "./test/dest"`を指定してスクリプトを実行する
  Then "./assets"内にあるすべての対応ファイルに対し処理を行い、"./test/dest"に同一のファイル名で保存する。

Scenario: 指定されたタイトルと概要文のメタデータを書き込む
  Given "Screenshot 2025-11-02 073031.png"
  When 引数に`Title "自身のアバターアイコンを作成"`と`Description "自身のアバターアイコンを作成し、Paintで表示したときのスクリーンショット"`を指定してスクリプトを実行する
  Then exiftoolを1回呼び出し、TitleとDescriptionのXMPメタデータに指定された文字列を適用する

Scenario: 指定されたキーワードのメタデータを書き込む
  Given "2003-01-28-224920_yuno-Image1.jpg"
  When 引数に`Keywords "screenshot", "game", "YU-NO"`を指定してスクリプトを実行する
  Then exiftoolを1回呼び出し、Keywordsに関するXMPメタデータを更新する

Scenario: 階層化キーワードの書き込み
  When 引数に`-Keywords "A|B|C","A|B|D","E"`を指定してスクリプトを実行する
  Then dc:subject contains A,B,C,D,E without duplicates (case-insensitive, stable order)
  And  lr:weightedFlatSubject contains C,D,E
  And  lr:hierarchicalSubject contains exactly "A|B|C","A|B|D"

Scenario: CLI overrides JSON
  Given config.json sets Title="X"
  When I pass -Title "Y" on CLI
  Then the written title equals "Y" (not "X")

Scenario: Dry-RUnへの対応
  When 引数に`WhatIf`を指定してスクリプトを実行する
  Then exiftoolを実行せず、実施される処理内容だけを示す
```

## 7. Quality (Non-Functional Gates)

| Attribute       | Gate                                      | Notes |
|-----------------|-------------------------------------------|-------|
| Static analysis | PSScriptAnalyzer 0 errors                  | Run during CI |
| Tests           | `Invoke-Pester -CI` (pwsh + Windows PS5 guidance) | Manual PS5 validation encouraged |
| Performance     | - | |

## 8. Open Questions

1. Provide dry-run diff output beyond WhatIf logging?

## 9. Decisions & Rationale

- 2025-11-14 Lightroom Classicの記録方法を採用 

## 10. References & Changelog

- 2025-11-15: 新規作成
