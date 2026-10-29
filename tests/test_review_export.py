"""Review export keeps base comments and omits private edits in base notes."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required')
class ReviewExportTest(unittest.TestCase):
    def test_optional_base_exports_note_comments_without_private_note_edits(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            repo = root / 'repo'
            repo.mkdir()
            source = repo / 'sample.py'
            source.write_text('value = 1\nmiddle = 2\nother = 3\nsecret = 2\n')
            (repo / 'private.py').write_text('secret = 2\n')
            for args in [('init', '-q'), ('config', 'user.name', 'Test'), ('config', 'user.email', 'test@example.invalid'),
                         ('add', '.'), ('commit', '-qm', 'initial')]:
                subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)
            head = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
            notes = root / 'notes' / head
            notes.mkdir(parents=True)
            (notes / 'sample.py').write_text('# Explain the base value\nvalue = 1\nmiddle = 2\nother = 3\nsecret = 2\n')
            (notes / 'private.py').write_text('secret = 99\n')
            source.write_text('# Worktree feedback\nvalue = 1\nmiddle = 2\nother = 3\nsecret = 2\n')
            legacy, full = root / 'legacy.md', root / 'full.md'
            script = root / 'check.lua'
            script.write_text(f'''
package.loaded.review_mode = {{notes_dir={json.dumps(str(root / 'notes'))}, state_dir={json.dumps(str(root / 'state'))}}}
package.loaded.pr = {{}}
local fennel = dofile({json.dumps(str(ROOT / 'fennel/fennel.lua'))})
local comments = fennel.dofile({json.dumps(str(ROOT / 'review_comments.fnl'))})
assert(comments.export({json.dumps(str(legacy))}) == 1)
local count = comments.export({json.dumps(str(full))}, {json.dumps(head)}); assert(count == 2, "count=" .. count)
vim.cmd.qa()
''')
            result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-c', 'filetype plugin on', '-c', f'lua dofile({json.dumps(str(script))})', '-c', 'qa!'],
                                    cwd=repo, capture_output=True, text=True, timeout=20)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertNotIn("Error", result.stderr)
            self.assertIn('Worktree feedback', legacy.read_text())
            self.assertNotIn('Explain the base value', legacy.read_text())
            self.assertIn('Explain the base value', full.read_text())
            self.assertIn('(base ' + head + ')', full.read_text())
            self.assertNotIn('secret = 99', full.read_text())


if __name__ == '__main__':
    unittest.main()
