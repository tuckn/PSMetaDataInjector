
@{
    RootModule           = 'PSMetaDataInjector.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '2a894c3c-8895-40bd-9ad4-4d5341930c1b'
    Author               = 'Tuckn'
    CompanyName          = 'Unknown'
    Copyright            = '(c) 2025 Tuckn. All rights reserved.'
    Description          = 'Injects metadata (capture dates, titles, keywords, and Markdown frontmatter) into files.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop')
    NestedModules        = @(
        'modules/SetMediaMetadata.psm1'
        'modules/SetFrontmatter.psm1'
    )
    FunctionsToExport    = @('Set-MediaMetadata', 'Set-MarkdownFrontmatter')
    CmdletsToExport      = @()
    AliasesToExport      = @()
    VariablesToExport    = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('exif','xmp','metadata','images','title','keywords','markdown','frontmatter','powershell-module')
            ProjectUri = 'https://github.com/tuckn/PSMetaDataInjector'
            LicenseUri = 'https://github.com/tuckn/PSMetaDataInjector/blob/main/LICENSE'
        }
    }
}
