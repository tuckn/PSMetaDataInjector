
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $InputPath,

    [switch] $Recurse,

    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory,

    [Nullable[datetime]] $CreatedDate,

    [switch] $InferCreatedDate,

    [ValidateNotNullOrEmpty()]
    [string] $Title,

    [AllowNull()]
    [string] $Description,

    [string[]] $Keywords,

    [ValidateNotNullOrEmpty()]
    [string] $ExifToolPath,

    [ValidateNotNullOrEmpty()]
    [string] $ConfigJsonPath,

    [switch] $Passthru
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\PSMetaDataInjector.psd1') -Force -ErrorAction Stop

$parameterOrder = @(
    'InputPath',
    'Recurse',
    'OutputDirectory',
    'CreatedDate',
    'InferCreatedDate',
    'Title',
    'Description',
    'Keywords',
    'ExifToolPath',
    'Passthru'
)
$configParameters = @{}

if ($PSBoundParameters.ContainsKey('ConfigJsonPath')) {
    try {
        $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigJsonPath -ErrorAction Stop).ProviderPath
    }
    catch {
        throw ("The configuration file '{0}' could not be resolved: {1}" -f $ConfigJsonPath, $_.Exception.Message)
    }

    try {
        $configContent = Get-Content -LiteralPath $resolvedConfigPath -Raw -ErrorAction Stop
        $configData = $configContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw ("Failed to parse configuration file '{0}': {1}" -f $resolvedConfigPath, $_.Exception.Message)
    }

    foreach ($name in $parameterOrder) {
        if ($null -ne $configData.$name) {
            $configParameters[$name] = $configData.$name
        }
    }
}

$effectiveParameters = @{}

foreach ($name in $parameterOrder) {
    if ($configParameters.ContainsKey($name)) {
        $effectiveParameters[$name] = $configParameters[$name]
    }
}

foreach ($name in $parameterOrder) {
    if ($PSBoundParameters.ContainsKey($name)) {
        $effectiveParameters[$name] = $PSBoundParameters[$name]
    }
}

foreach ($control in @('WhatIf', 'Confirm')) {
    if ($PSBoundParameters.ContainsKey($control)) {
        $effectiveParameters[$control] = $PSBoundParameters[$control]
    }
}

if (-not $effectiveParameters.ContainsKey('InputPath') -or [string]::IsNullOrWhiteSpace([string]$effectiveParameters['InputPath'])) {
    throw 'InputPath must be supplied either on the command line or in the configuration file.'
}

Set-MediaMetadata @effectiveParameters
