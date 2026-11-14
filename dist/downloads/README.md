# ECC Palette Studio

10 image-inspired palettes, 49 original color entries, 10 Windows Terminal schemes, a PowerShell installer and an interactive product page.

## Included

- `palettes/ecc-creative-image-palettes.json`: original names, colors, roles, printed/estimated provenance.
- `palettes/ECC-Windows-Terminal-Color-Schemes.json`: 16 ANSI colors, foreground, cursor and selection fields per scheme. The darkest original color by relative luminance is pinned as background.
- `scripts/Install-ECCWindowsTerminalThemes.ps1`: original recovered installer. Supports `-WhatIf`, JSONC validation, timestamped backup, duplicate-name skipping and same-directory atomic replacement. It does not activate a theme.
- `scripts/Sync-PaletteCatalog.py`: dependency-free local repository scanner. Recognizes creative collections, Windows Terminal scheme collections, color maps and hex arrays. Preserves source files and records SHA-256 provenance. It does not invent Terminal schemes for additional creative palettes.
- `scripts/Publish-GitHubRepository.ps1`: creates a new dedicated private GitHub repo from this extracted package using authenticated `gh`. Refuses existing repositories and Git metadata.
- `tests/test_catalog.py`: validates source backgrounds, required Terminal slots, foreground contrast and additional JSON formats.
- `dist/`: standalone static product page with gallery, filters, search, terminal preview, details, local JSON import and downloads. Imports remain browser-local and do not modify release downloads.

## Create a palette from an image

Open **Image to palette** in the product page, choose or drop a PNG, JPG or WebP (up to 20 MB and 40 megapixels), and select 3–10 requested colors. Extraction is automatic after selection. Rename the palette, copy individual hex values, copy/download the JSON, or add it to the browser session collection. Download JSON to keep it; uploads and generated palettes are not stored remotely or included in the fixed release downloads.

The extractor resizes a sample to at most 240 pixels on its longest side, ignores alpha below 128, and runs deterministic weighted Lab k-means over an RGB histogram. Colors are quantized averages with approximate proportions; this is not OCR, semantic image interpretation or exact pixel sampling. Images with fewer distinct colors can return fewer than requested. The darkest extracted color is assigned the background role. New image palettes do not automatically generate 16 ANSI Terminal schemes.

`dist/extractor.js` is the reusable dependency-free extraction engine; `dist/image-upload.js` handles local file selection, decoding, extraction and export.

Run image checks with `node tests/test_extractor.cjs` and `node tests/test_image_flow.cjs`. The latter exercises application handlers with mocked browser decoding/canvas, including errors and JSON export. A live browser file-chooser test timed out, so the complete real-browser upload flow is not claimed as verified.

## Install Windows Terminal schemes

Easiest: extract `dist/downloads/ECC-Windows-Terminal-Theme-Installer.zip`, open PowerShell 7 in that extracted folder, and run:

```powershell
.\Install-ECCWindowsTerminalThemes.ps1 -WhatIf
.\Install-ECCWindowsTerminalThemes.ps1
```

From the repository root, explicitly point to the palette file:

```powershell
.\scripts\Install-ECCWindowsTerminalThemes.ps1 -SchemePath .\palettes\ECC-Windows-Terminal-Color-Schemes.json -WhatIf
.\scripts\Install-ECCWindowsTerminalThemes.ps1 -SchemePath .\palettes\ECC-Windows-Terminal-Color-Schemes.json
```

If multiple Terminal installations are detected, pass `-SettingsPath` to choose the target. Keep the settings editor closed while installing. Select the new `ECC | …` scheme under Settings → profile → Appearance → Color scheme.

## Backup and restore

Before a write, the installer creates a sibling named `settings.json.backup-YYYYMMDD-HHMMSS-XXXXXX.json`. To restore after closing settings editors:

```powershell
Copy-Item -LiteralPath 'FULL_PATH_TO_BACKUP' -Destination 'FULL_PATH_TO_SETTINGS_JSON' -Force
```

No M365 access, administrator privilege or online dependency is required by the installer. Respect your local execution policy. The installer was recovered intact, inspected and packaged, but has not been executed on Windows during this build. Start with `-WhatIf`.

## Add more palette JSON

Place JSON files under `palettes/` (subdirectories allowed), then run:

```bash
python scripts/Sync-PaletteCatalog.py
python -m unittest discover -s tests -v
python scripts/Build-Release.py
```

The scanner also accepts `--root PATH` and `--output PATH`. It skips build output, Git metadata, node_modules and tests, reads JSON files up to 5 MB, and validates six-digit hex values. Additional palette colors are retained without auto-generating terminal themes. Duplicate palette name/color pairs are collapsed. No network call is made.

## Preview the product page

```bash
python scripts/Build-Release.py
python -m http.server 8080 --directory dist --bind 127.0.0.1
```

Open http://127.0.0.1:8080/. The site needs no build framework or external assets.

## Dedicated GitHub repository

GitHub creation/publication was blocked during this build: the connected account exposed no repositories, the prior `wo4py8w4y/NewRepo2` reference returned 404, and the web interface required sign-in. No additional remote repository palette data has been claimed or incorporated. The deployed Site has its own source repository, but this is not a GitHub repository.

To publish the complete extracted package to a new **private** GitHub repository:

```powershell
# Install Git and GitHub CLI beforehand and sign in:
gh auth login
# Review the operation, then publish:
.\scripts\Publish-GitHubRepository.ps1 -WhatIf
.\scripts\Publish-GitHubRepository.ps1
```

The default new repository name is `ecc-palette-studio`; override `-RepositoryName` if needed. This creates and pushes source only. It does not enable GitHub Pages or change visibility. The product page is separately deployed using Sites with private access.

## Provenance and usage

Original creative palette JSON and Terminal scheme JSON were recovered from the user's prior deliverables. Reference-image names and textual inspirations are preserved as metadata; source images are not redistributed. Estimated colors are visual approximations. ANSI slots include derived shades; they are not all original source colors. Foreground/background contrast is measured, not a blanket accessibility guarantee for every ANSI pair.

No third-party license is asserted for source reference imagery or original creative material. Check applicable rights before redistributing it publicly.
