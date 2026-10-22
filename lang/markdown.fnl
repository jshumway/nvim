(local augroup_module (vim.api.nvim_create_augroup :user_lang_markdown {:clear true}))

(vim.api.nvim_create_autocmd :FileType {
    :group augroup_module
    :pattern [:markdown]
    :callback (fn [ctx]
        ;; Soft-wrap prose at word boundaries. Wrapped list items hang under
        ;; their text (the markdown ftplugin sets 'formatlistpat' for this).
        (set vim.opt_local.wrap true)
        (set vim.opt_local.linebreak true)
        (set vim.opt_local.breakindent true)
        (set vim.opt_local.breakindentopt "list:-1")
        ;; Scroll through long wrapped lines by screen line, not a whole line.
        (set vim.opt_local.smoothscroll true)

        ;; Continue bullets and quotes on <CR> and o / O. The ftplugin's
        ;; bullets use the `f` flag, which only keeps the indent.
        (set vim.opt_local.comments "b:-,b:*,b:+,n:>")
        (vim.opt_local.formatoptions:append :ro)

        ;; Move by screen line within wrapped paragraphs, unless given a count
        ;; (so relative jumps like 5j still work).
        (each [_ [key screen_key] (ipairs [[:j :gj] [:k :gk] [:<Down> :gj] [:<Up> :gk]])]
            (vim.keymap.set [:n :x] key #(if (= vim.v.count 0) screen_key key)
                            {:buffer ctx.buf :expr true :silent true})))})
