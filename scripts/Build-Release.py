#!/usr/bin/env python3
"""Copy release downloads and package a GitHub-ready source tree without credentials."""
from pathlib import Path
import shutil,zipfile,json
ROOT=Path(__file__).resolve().parents[1];downloads=ROOT/'dist/downloads';downloads.mkdir(parents=True,exist_ok=True)
for src in [ROOT/'README.md',ROOT/'palettes/ecc-creative-image-palettes.json',ROOT/'palettes/ECC-Windows-Terminal-Color-Schemes.json',ROOT/'scripts/Install-ECCWindowsTerminalThemes.ps1',ROOT/'scripts/Sync-PaletteCatalog.py',ROOT/'scripts/Publish-GitHubRepository.ps1']:
 shutil.copyfile(src,downloads/src.name)
package=downloads/'ECC-Palette-Studio-Repository.zip'
with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED) as z:
 for path in sorted(ROOT.rglob('*')):
  if not path.is_file() or path==package:continue
  rel=path.relative_to(ROOT)
  if any(p in {'.git','.openai','__pycache__','.venv','node_modules'} for p in rel.parts):continue
  if path.suffix in {'.tar','.gz'}:continue
  z.write(path,Path('ecc-palette-studio')/rel)
with zipfile.ZipFile(package) as z:
 assert z.testzip() is None
 assert 'ecc-palette-studio/scripts/Install-ECCWindowsTerminalThemes.ps1' in z.namelist()
print(f'Release package: {package.name} ({package.stat().st_size:,} bytes)')
