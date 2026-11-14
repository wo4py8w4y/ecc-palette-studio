import importlib.util,json,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('catalog',Path(__file__).resolve().parents[1]/'scripts/Sync-PaletteCatalog.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
ROOT=Path(__file__).resolve().parents[1]
class CatalogTests(unittest.TestCase):
 def test_originals(self):
  c=m.build(ROOT);self.assertEqual(len(c['palettes']),10)
  for p in c['palettes']:
   self.assertEqual(p['darkest'],p['scheme']['background']);self.assertTrue(all(k in p['scheme'] for k in m.ANSI));self.assertGreaterEqual(p['contrast'],4.5)
 def test_additional_formats(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td);(r/'more.json').write_text(json.dumps({'name':'Extra','colors':{'Night':'#010203','Pink':'#FF00AA'}}));(r/'plain.json').write_text('["#111111","#ABCDEF"]')
   c=m.build(r);self.assertEqual(len(c['palettes']),2);self.assertEqual(c['palettes'][0]['darkest'],'#010203');self.assertIsNone(c['palettes'][0]['scheme'])
 def test_excludes_build_output(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td);(r/'dist').mkdir();(r/'dist'/'colors.json').write_text('["#111111","#FFFFFF"]');self.assertEqual(m.build(r)['palettes'],[])
 def test_hex_validation(self):self.assertEqual(m.normalized_colors(['#ffffff','oops',{'hex':'#fff'}]),[{'name':'Color 1','hex':'#FFFFFF','value_origin':'repository'}])
if __name__=='__main__':unittest.main()
