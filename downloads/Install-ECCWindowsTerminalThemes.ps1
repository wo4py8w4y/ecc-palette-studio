#Requires -Version 7.0
<#
.SYNOPSIS
    Safely adds ECC colour schemes to an existing Windows Terminal settings.json.
.DESCRIPTION
    Backs up settings.json, preserves existing JSONC formatting/comments, skips
    duplicate scheme names, validates all input/output JSON, and uses an atomic
    file replacement. Does not change the active colour scheme or profiles.
.EXAMPLE
    .\Install-ECCWindowsTerminalThemes.ps1 -WhatIf
.EXAMPLE
    .\Install-ECCWindowsTerminalThemes.ps1
.EXAMPLE
    .\Install-ECCWindowsTerminalThemes.ps1 -SettingsPath 'D:\Terminal\settings.json' -SchemePath '.\ECC-Windows-Terminal-Color-Schemes.json'
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string]$SchemePath = (Join-Path $PSScriptRoot 'ECC-Windows-Terminal-Color-Schemes.json'),
    [Parameter()]
    [string]$SettingsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message, [ValidateSet('Info','Success','Warning','Error')][string]$Level='Info')
    $colors = @{ Info='Cyan'; Success='Green'; Warning='Yellow'; Error='Red' }
    Write-Host ('[{0}] {1}' -f $Level.ToUpperInvariant(), $Message) -ForegroundColor $colors[$Level]
}

function Get-JsonDocument {
    param([Parameter(Mandatory)][string]$Text, [string]$Label)
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $true
    $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
    try {
        return [System.Text.Json.JsonDocument]::Parse($Text, $options)
    }
    catch {
        throw "Invalid JSON in '$Label': $($_.Exception.Message)"
    }
}

function Get-JsoncTokens {
    # Tokenizes JSONC without interpreting punctuation inside strings or comments.
    param([string]$Text)
    $tokens = [System.Collections.Generic.List[object]]::new()
    $depth = 0
    $i = 0
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        if ([char]::IsWhiteSpace($ch)) { $i++; continue }
        if ($ch -eq '/' -and $i+1 -lt $Text.Length) {
            if ($Text[$i+1] -eq '/') {
                $i += 2
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
                continue
            }
            if ($Text[$i+1] -eq '*') {
                $i += 2
                $closed = $false
                while ($i+1 -lt $Text.Length) {
                    if ($Text[$i] -eq '*' -and $Text[$i+1] -eq '/') { $i += 2; $closed=$true; break }
                    $i++
                }
                if (-not $closed) { throw 'Unterminated block comment in settings.json.' }
                continue
            }
        }
        if ($ch -eq '"') {
            $start = $i
            $i++
            while ($i -lt $Text.Length) {
                if ($Text[$i] -eq '\') { $i += 2; continue }
                if ($Text[$i] -eq '"') { $i++; break }
                $i++
            }
            if ($i -gt $Text.Length -or $Text[$i-1] -ne '"') { throw 'Unterminated JSON string.' }
            $raw = $Text.Substring($start, $i-$start)
            $value = ConvertFrom-Json -InputObject $raw -NoEnumerate
            $tokens.Add([pscustomobject]@{Kind='string';Value=$value;Start=$start;End=$i;Depth=$depth})
            continue
        }
        $symbol = [string]$ch
        if ('{}[]:,'.Contains($symbol)) {
            $tokens.Add([pscustomobject]@{Kind=$symbol;Value=$symbol;Start=$i;End=($i+1);Depth=$depth})
            if ($symbol -eq '{' -or $symbol -eq '[') { $depth++ }
            if ($symbol -eq '}' -or $symbol -eq ']') { $depth-- }
            $i++
            continue
        }
        # numbers, booleans and null are immaterial for insertion-point discovery.
        $start = $i
        while ($i -lt $Text.Length -and -not [char]::IsWhiteSpace($Text[$i]) -and -not '{}[],:'.Contains([string]$Text[$i])) {
            if ($Text[$i] -eq '/' -and $i+1 -lt $Text.Length -and ('/','*' -contains [string]$Text[$i+1])) { break }
            $i++
        }
        if ($i -eq $start) { throw "Unexpected character at position $i." }
        $tokens.Add([pscustomobject]@{Kind='literal';Value=$Text.Substring($start,$i-$start);Start=$start;End=$i;Depth=$depth})
    }
    return $tokens.ToArray()
}

function Get-SettingsCandidate {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:LOCALAPPDATA) {
        foreach ($folder in @(
            'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState',
            'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState',
            'Microsoft\Windows Terminal'
        )) { $candidates.Add((Join-Path (Join-Path $env:LOCALAPPDATA $folder) 'settings.json')) }
    }
    $existing = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($existing.Count -eq 0) {
        throw "No Windows Terminal settings.json found. Supply -SettingsPath explicitly. Searched: $($candidates -join '; ')"
    }
    if ($existing.Count -gt 1) {
        throw "Multiple Windows Terminal settings files were found. Specify -SettingsPath to choose one: $($existing -join '; ')"
    }
    return $existing[0]
}

try {
    if (-not $SettingsPath) { $SettingsPath = Get-SettingsCandidate }
    $SettingsPath = [IO.Path]::GetFullPath($SettingsPath)
    $SchemePath = [IO.Path]::GetFullPath($SchemePath)
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw "Settings file does not exist: $SettingsPath" }
    if (-not (Test-Path -LiteralPath $SchemePath -PathType Leaf)) { throw "Scheme file does not exist: $SchemePath" }
    if ($SettingsPath -eq $SchemePath) { throw 'SettingsPath and SchemePath must be different files.' }

    $settingsText = [IO.File]::ReadAllText($SettingsPath)
    $schemesText = [IO.File]::ReadAllText($SchemePath)
    $settingsDoc = Get-JsonDocument $settingsText $SettingsPath
    $schemesDoc = Get-JsonDocument $schemesText $SchemePath
    try {
        if ($settingsDoc.RootElement.ValueKind -ne 'Object') { throw 'Settings must be a JSON object.' }
        if ($schemesDoc.RootElement.ValueKind -ne 'Object') { throw 'Scheme source must be a JSON object with a schemes array.' }
        $sourceArray = [System.Text.Json.JsonElement]::new()
        if (-not $schemesDoc.RootElement.TryGetProperty('schemes', [ref]$sourceArray) -or $sourceArray.ValueKind -ne 'Array') {
            throw "The scheme source does not contain a 'schemes' array."
        }
        $currentArray = [System.Text.Json.JsonElement]::new()
        $hasSchemes = $settingsDoc.RootElement.TryGetProperty('schemes', [ref]$currentArray)
        if ($hasSchemes -and $currentArray.ValueKind -ne 'Array') { throw "Existing 'schemes' property is not an array; refusing to change it." }

        $knownNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($hasSchemes) {
            foreach ($entry in $currentArray.EnumerateArray()) {
                if ($entry.ValueKind -eq 'Object') {
                    $n = [System.Text.Json.JsonElement]::new()
                    if ($entry.TryGetProperty('name',[ref]$n) -and $n.ValueKind -eq 'String') { [void]$knownNames.Add($n.GetString()) }
                }
            }
        }
        $required = @('name','background','foreground','cursorColor','selectionBackground','black','red','green','yellow','blue','purple','cyan','white','brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightPurple','brightCyan','brightWhite')
        $toAdd = [System.Collections.Generic.List[string]]::new()
        $skipped = 0
        foreach ($scheme in $sourceArray.EnumerateArray()) {
            if ($scheme.ValueKind -ne 'Object') { throw 'Every source scheme must be a JSON object.' }
            foreach ($propertyName in $required) {
                $property = [System.Text.Json.JsonElement]::new()
                if (-not $scheme.TryGetProperty($propertyName, [ref]$property) -or $property.ValueKind -ne 'String') { throw "Scheme missing string property: $propertyName" }
                if ($propertyName -ne 'name' -and $property.GetString() -cnotmatch '^#[0-9A-Fa-f]{6}$') { throw "Invalid hex colour for $propertyName in source scheme." }
            }
            $name = $scheme.GetProperty('name').GetString()
            if ([string]::IsNullOrWhiteSpace($name)) { throw 'Scheme name cannot be empty.' }
            if (-not $knownNames.Add($name)) { $skipped++; Write-Status "Skipping existing scheme: $name" Warning; continue }
            $toAdd.Add($scheme.GetRawText())
        }
    }
    finally { $settingsDoc.Dispose(); $schemesDoc.Dispose() }

    Write-Status "Settings: $SettingsPath"
    Write-Status "Source:   $SchemePath"
    Write-Status "New schemes: $($toAdd.Count); skipped duplicate names: $skipped"
    if ($toAdd.Count -eq 0) { Write-Status 'No changes needed. Settings left untouched.' Success; return }

    $tokens = @(Get-JsoncTokens $settingsText)
    $foundIndex = -1
    for ($j=0; $j -lt $tokens.Count-2; $j++) {
        if ($tokens[$j].Kind -eq 'string' -and $tokens[$j].Depth -eq 1 -and
            $tokens[$j].Value -ceq 'schemes' -and $tokens[$j+1].Kind -eq ':') {
            $foundIndex = $j + 2
            break
        }
    }
    if ($hasSchemes -and ($foundIndex -lt 0 -or $tokens[$foundIndex].Kind -ne '[')) {
        throw 'Unable to locate schemes array safely in the original file.'
    }
    $newline = if ($settingsText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $formatted = @($toAdd | ForEach-Object {
        $obj = $_ | ConvertFrom-Json -AsHashtable
        ($obj | ConvertTo-Json -Depth 32).Trim() -replace '(?m)^', '        '
    }) -join (',' + $newline)

    if ($hasSchemes) {
        $openingIndex = $foundIndex
        $closingIndex = -1
        for ($j=$openingIndex+1; $j -lt $tokens.Count; $j++) {
            if ($tokens[$j].Kind -eq ']' -and $tokens[$j].Depth -eq 2) { $closingIndex=$j; break }
        }
        if ($closingIndex -lt 0) { throw 'Unable to find closing bracket for schemes array.' }
        $innerTokens = @($tokens | Select-Object -Skip ($openingIndex+1) -First ($closingIndex-$openingIndex-1))
        $nonEmpty = ($innerTokens.Count -gt 0)
        $hasTrailingComma = $nonEmpty -and ($innerTokens[-1].Kind -eq ',')
        $comma = if ($nonEmpty -and -not $hasTrailingComma) { ',' } else { '' }
        $insertion = $comma + $newline + $formatted + $newline + '    '
        $position = [int]$tokens[$closingIndex].Start
    }
    else {
        $rootClose = @($tokens | Where-Object { $_.Kind -eq '}' -and $_.Depth -eq 1 } | Select-Object -Last 1)
        if ($rootClose.Count -ne 1) { throw 'Unable to locate root JSON object closing brace.' }
        $position = [int]$rootClose[0].Start
        $prior = @($tokens | Where-Object { $_.Start -lt $position } | Select-Object -Last 1)
        $comma = if ($prior.Count -gt 0 -and $prior[0].Kind -ne '{' -and $prior[0].Kind -ne ',') { ',' } else { '' }
        $insertion = $comma + $newline + '    "schemes": [' + $newline + $formatted + $newline + '    ]' + $newline
    }
    $candidate = $settingsText.Insert($position, $insertion)
    $check = Get-JsonDocument $candidate 'merged settings candidate'
    try {
        $array = [System.Text.Json.JsonElement]::new()
        if (-not $check.RootElement.TryGetProperty('schemes', [ref]$array) -or $array.ValueKind -ne 'Array') {
            throw 'Merged candidate does not contain a valid schemes array.'
        }
    }
    finally { $check.Dispose() }

    if (-not $PSCmdlet.ShouldProcess($SettingsPath, "Backup and append $($toAdd.Count) colour schemes")) { return }
    $backup = '{0}.backup-{1}-{2}.json' -f $SettingsPath, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,6))
    Copy-Item -LiteralPath $SettingsPath -Destination $backup -ErrorAction Stop
    Write-Status "Backup created: $backup" Success
    $temp = Join-Path (Split-Path $SettingsPath -Parent) ('.ecc-terminal-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        # UTF-8 without BOM is the standard Windows Terminal JSON representation.
        [IO.File]::WriteAllText($temp, $candidate, [Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($temp, $SettingsPath, $null)
        Write-Status "Successfully installed $($toAdd.Count) schemes. Existing settings and comments preserved." Success
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
catch {
    Write-Status $_.Exception.Message Error
    throw
}
