(local mini-deps (require :mini.deps))

(local augroup_module (vim.api.nvim_create_augroup :user_lang_fennel {:clear true}))

(vim.api.nvim_create_autocmd :FileType {
    :group augroup_module
    :pattern [:fennel]
    :callback (fn []
        (vim.cmd "setlocal includeexpr=substitute(v:fname,'\\\\.','/','g')")
        (vim.opt_local.suffixesadd:prepend :.fnl)
        (vim.opt_local.suffixesadd:prepend :.lua)
        (vim.opt_local.suffixesadd:prepend :init.fnl)
        (vim.opt_local.suffixesadd:prepend :.init.lua)

        (vim.opt_local.path:prepend
            (.. mini-deps.config.path.package :/pack/deps/opt/*/lua/**))

        (vim.opt_local.path:prepend
            (.. mini-deps.config.path.package :/pack/deps/start/*/lua/**))
    })

