import hashlib,json,unittest,zipfile
from pathlib import Path
from html.parser import HTMLParser
ROOT=Path(__file__).resolve().parents[1]
class Links(HTMLParser):
 def __init__(self):super().__init__();self.files=[]
 def handle_starttag(self,tag,attrs):
  d=dict(attrs)
  if tag=='a' and d.get('href','').startswith('downloads/'):self.files.append(d['href'])
class ReleaseTests(unittest.TestCase):
 def test_all_download_targets_exist(self):
  links=Links();links.feed((ROOT/'dist/index.html').read_text())
  for f in links.files:self.assertTrue((ROOT/'dist'/f).is_file(),f)
 def test_installer_unchanged(self):
  with zipfile.ZipFile(ROOT/'dist/downloads/ECC-Windows-Terminal-Theme-Installer.zip') as z:
   self.assertEqual(z.read('Install-ECCWindowsTerminalThemes.ps1'),(ROOT/'scripts/Install-ECCWindowsTerminalThemes.ps1').read_bytes())
 def test_release_has_no_credentials_or_site_identity(self):
  with zipfile.ZipFile(ROOT/'dist/downloads/ECC-Palette-Studio-Repository.zip') as z:
   self.assertIsNone(z.testzip());self.assertFalse(any('/.git/' in n or '/.openai/' in n or '/.env' in n for n in z.namelist()))
if __name__=='__main__':unittest.main()
