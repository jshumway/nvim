"""Deck can install a prepared comparison without synchronous Git or hashing."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('nvim'), 'Neovim is required')
class ExternalReviewTest(unittest.TestCase):
    def test_prepared_large_comparison_preserves_buffers_and_never_runs_git(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        repo = root / 'repo';repo.mkdir()
        subprocess.run(['git','init','-q','-b','main',str(repo)],check=True)
        (repo/'file').write_text('saved\n')
        script=root/'check.lua'
        script.write_text(f'''
vim.env.DECK_SESSION_ID='disposable-fixture'
vim.env.DECK_ASYNC_REVIEW='1'
package.loaded['mini.diff']={{config={{source={{}}}},gen_source={{git=function() return {{}} end}},
  get_buf_data=function() end,enable=function() end,disable=function() end}}
package.loaded['mini.pick']={{}}
local fennel=dofile({json.dumps(str(ROOT/'fennel/fennel.lua'))})
local review=fennel.dofile({json.dumps(str(ROOT/'review_mode.fnl'))})
local root={json.dumps(str(repo))}
local state=vim.fn.stdpath('state')..'/review'
vim.fn.mkdir(state,'p')
vim.fn.writefile({{vim.json.encode({{ref=string.rep('b',40),auto=true}})}},
 state..'/'..vim.fn.sha256(root..':main'):sub(1,16)..'.json')
vim.system=function() error('Unexpected Git call on the Neovim main thread') end
vim.cmd.edit(root..'/file')
assert(review.base()==nil,'Deck must validate the saved round before restoring a base')
vim.api.nvim_buf_set_lines(0,0,-1,false,{{'unsaved notes'}})
local items={{}}
for i=1,12000 do items[i]={{rel='file-'..i,path=root..'/file-'..i}} end
review.set_external({{root=root,sha=string.rep('a',40)}},items)
assert(#review.items()==12000)
assert(review.base().sha==string.rep('a',40))
vim.api.nvim_exec_autocmds('FocusGained',{{}})
vim.wait(50,function() return false end)
assert(#review.items()==12000 and vim.bo.modified)
assert(vim.api.nvim_get_current_line()=='unsaved notes')
''')
        env={k:v for k,v in os.environ.items() if not k.startswith('DECK_')}
        for kind in ['DATA','CONFIG','CACHE','STATE']:
            env['XDG_'+kind+'_HOME']=str(root/kind.lower())
        result=subprocess.run(['nvim','--headless','-u','NONE','-i','NONE','-c',
            'lua dofile('+json.dumps(str(script))+')','-c','qa!'],cwd=repo,env=env,
            capture_output=True,text=True,timeout=15)
        self.assertEqual(0,result.returncode,result.stderr)
        self.assertNotIn('Error',result.stderr)
        self.assertNotIn('assertion failed',result.stderr)
