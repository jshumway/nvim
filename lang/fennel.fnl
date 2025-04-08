(local mini-deps (require :mini.deps))

(local augroup_module (vim.api.nvim_create_augroup :user_lang_fennel {:clear true}))

(fn setup_includeexpr []
    (vim.cmd "setlocal includeexpr=substitute(v:fname,'\\\\.','/','g')")
    (vim.opt_local.suffixesadd:prepend :.fnl)
    (vim.opt_local.suffixesadd:prepend :.lua)
    (vim.opt_local.suffixesadd:prepend :.init.fnl)
    (vim.opt_local.suffixesadd:prepend :.init.lua))

(fn setup_nvim_config_dirs []
    (vim.opt_local.path:prepend
        (.. mini-deps.config.path.package :/pack/deps/opt/*/lua))
    (vim.opt_local.path:prepend
        (.. mini-deps.config.path.package :/pack/deps/start/*/lua)))

(vim.api.nvim_create_autocmd :FileType {
    :group augroup_module
    :pattern [:fennel]
    :callback (fn [ctx]
        (setup_includeexpr)
        (setup_nvim_config_dirs)

        ;; Turn off lisp-mode because I don't like 2-space indentation
        ;; for Fennel.
        (set vim.opt_local.lisp false)

        (set vim.b.miniindentscope_disable false)
        (set vim.b.miniindentscope_config {:options {:border :top}})

        (set vim.b.minicursorword_disable false)
    )})

(vim.api.nvim_create_autocmd :FileType {
    :group augroup_module
    :pattern [:lua]
    :callback (fn []
        (setup_includeexpr)
        (setup_nvim_config_dirs)

        (set vim.b.miniindentscope_disable false)
        (set vim.b.minicursorword_disable false)
    )})

