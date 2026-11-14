#Requires -Version 7.0
<# Creates a NEW dedicated private GitHub repo from this package. Requires GitHub CLI
and an authenticated GitHub session. Refuses to overwrite an existing remote.
Does not change Pages settings or make source public. Use -WhatIf first.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$RepositoryName = 'ecc-palette-studio')
$ErrorActionPreference = 'Stop'
if ($RepositoryName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$') { throw 'Invalid repository name.' }
foreach ($command in @('git','gh')) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command missing: $command" } }
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    & gh auth status
    if ($LASTEXITCODE -ne 0) { throw 'Authenticate first with gh auth login.' }
    $owner = & gh api user --jq .login
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($owner)) { throw 'Cannot resolve authenticated GitHub owner.' }
    $fullName = "$($owner.Trim())/$RepositoryName"
    & gh repo view $fullName --json name 2>$null
    if ($LASTEXITCODE -eq 0) { throw "Repository already exists: $fullName. Refusing to replace it." }
    if (Test-Path -LiteralPath '.git') { throw 'Run from the extracted repository package, without existing Git metadata.' }
    if ($PSCmdlet.ShouldProcess($fullName,'Initialize local source, commit and create a private GitHub repository')) {
        & git init --initial-branch=main
        if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
        & git add --all
        if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
        & git commit -m 'Release ECC Palette Studio palettes, terminal tools and product page'
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed. Check your Git author settings.' }
        & gh repo create $fullName --private --source . --remote origin --push --description 'Creative color palettes, Windows Terminal schemes and PowerShell installer tools'
        if ($LASTEXITCODE -ne 0) { throw 'GitHub publication failed. Inspect local Git state before retrying.' }
        Write-Host "[SUCCESS] Created and pushed https://github.com/$fullName" -ForegroundColor Green
    }
} finally { Pop-Location }
