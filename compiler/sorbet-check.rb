if exists("current_compiler")
  finish
endif
let current_compiler = "sorbet-check"

let s:cpo_save = &cpo
set cpo&vim

CompilerSet makeprg=pay\ exec\ scripts/bin/typecheck
CompilerSet errorformat=%-G\ %.%#,%E%f:%l:\ %m\ http%.%#,%G-%.%#

let &cpo = s:cpo_save
unlet s:cpo_save

