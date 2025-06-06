;; --------------------------------------------------------------------
;; Editor Advanced

;; TODO:
;; - add linter / lsp error diagnostics stuff to status bar
;; - lsp rename opens buffers that it modifies... either want it to write automatically
;;   (so I can manage via git) or be able to quickly navigate between them, by like
;;   having the modified files in a quick list

(local mini_deps (require :mini.deps))

(local treesitter_langs [])

(fn add_treesitter_lang [lang]
    (table.insert treesitter_langs lang))

(local repl_metas {})

(fn add_repl_meta [lang config]
    (tset repl_metas lang config))

(fn overwrite_lsp_open_floating_preview []
    (local orig_open_floating_window vim.lsp.util.open_floating_preview)
    (fn custom_open_floating_preview [contents syntax opts ...]
        (tset opts :max_width 120)
        (tset opts :border :single)
        (local (bufnr winid) (orig_open_floating_window contents syntax opts ...)))
    (tset _G.vim.lsp.util :open_floating_preview custom_open_floating_preview))

(local augroup_module (vim.api.nvim_create_augroup :user_editor_advanced {:clear true}))

(let [_ (mini_deps.add {:source :nvim-treesitter/nvim-treesitter
             :checkout :master :monitor :main
             :hooks {:post_checkout #(vim.cmd :TSUpdate)}})
      m (require :nvim-treesitter.configs)]
    (m.setup {
        :ensure_installed [:lua :vimdoc :ruby :fennel :sql]
        :highlight {:enable true}
    }))

(let [_ (mini_deps.add {:source :nvim-treesitter/nvim-treesitter-textobjects})
      m (require :mini.ai)]
    (local spec_treesitter m.gen_spec.treesitter)
    (m.setup {
        :search_method :cover
        :custom_textobjects {
            :F (spec_treesitter {:a "@function.outer" :i "@function.inner"})
            :C (spec_treesitter {:a "@comment.outer" :i "@comment.inner"})
            :c (spec_treesitter {:a "@statement.outer" :i "@statement.inner"})
            :o (spec_treesitter {
                :a ["@conditional.outer" "@loop.outer" "@assignment.outer"]
                :i ["@conditional.inner" "@loop.inner" "@assignment.inner"]
            })
        }
    }))

(let [_ (mini_deps.add {:source :neovim/nvim-lspconfig})
      m (require :lspconfig)]
    nil)

(let [_ (mini_deps.add {:source :stevearc/conform.nvim})
      m (require :conform)]
    (m.setup {
        :formatters_by_ft {
            :javascript ["prettierd"]
            :typescript ["prettierd"]
            :javascriptreact ["prettierd"]
            :typescriptreact ["prettierd"]
            :html ["prettierd"]
            :json ["prettierd"]
            :jsonc ["prettierd"]
            :graphql ["prettierd"]
            :go [:goimports :gofmt]
        }
        :format_after_save {:lsp_format :fallback}
    }))

(let [_ (mini_deps.add {:source :shortcuts/no-neck-pain.nvim})
      m (require :no-neck-pain)]
    (m.setup {
        :width 160
        :autocmds {
            :enableOnVimEnter true
            :enableOnTabEnter true
        }
        :buffers {
            :setNames true
        }
    })

    ;; Prior to closing the last non-no-neck-pain window, close the no-neck-pain windows
    ;; so that they doesn't interfere with saving the session.
    (vim.api.nvim_create_autocmd :QuitPre {
        :callback
        #(when (= 3 (length (vim.api.nvim_list_wins)))
            (->> (vim.api.nvim_list_wins)
                (vim.tbl_filter
                    #(let [bufnr (vim.fn.winbufnr $)]
                        (= :no-neck-pain (vim.api.nvim_buf_get_option bufnr :filetype))))
                (vim.tbl_map #(vim.api.nvim_win_close $ true))))})
    )

;; TODO: for some reason this is ruining my ability to select (press enter on) entries
;; in the quickfix list. Disabling it for now.
;; (mini_deps.add {:source "milanglacier/yarepl.nvim"})

(fn setup []
    (overwrite_lsp_open_floating_preview)
    ; (local yr (require :yarepl))
    ; (yr.setup {
    ;     :wincmd "vertical 120 split"
    ;     :metas repl_metas
    ; })
    ;
    ; (local yr_ext_cc (require :yarepl.extensions.code_cell))
    ; (yr_ext_cc.register_text_objects [{
    ;     :key :c
    ;     :start_pattern "```.+"
    ;     :end_pattern "```$"
    ;     :ft ["rmd" "quarto" "markdown"]
    ;     :desc "markdown code cells"
    ; }])
)

(local mini_extra (require :mini.extra))

{
    : setup : add_treesitter_lang : add_repl_meta

    :move_down_suggestions "pumvisible() ? \"\\<C-n>\" : \"\\<Tab>\""
    :move_up_suggestions "pumvisible() ? \"\\<C-p>\" : \"\\<S-Tab>\""

    :on_lsp_attach
    #(vim.api.nvim_create_autocmd :LspAttach {:pattern "*" :group augroup_module :callback $})

    :code_action vim.lsp.buf.code_action
    :declaration #(mini_extra.pickers.lsp {:scope :declaration})
    :definition vim.lsp.buf.definition
    :hover vim.lsp.buf.hover
    :implementation #(mini_extra.pickers.lsp {:scope :implementation})
    :outline vim.lsp.buf.document_symbol
    :references #(mini_extra.pickers.lsp {:scope :references})
    :rename vim.lsp.buf.rename
    :signature_help vim.lsp.buf.signature_help
    :type_definition vim.lsp.buf.type_definition ;; #(mini_extra.pickers.lsp {:scope :type_definition})

    ; :repl {
    ;     :make_start_and_attach_for_ft (fn [ft] (.. "<CMD>REPLStart! " ft "<CR>"))
    ;     :make_attach_for_ft (fn [ft] (.. "<CMD>REPLAttachBufferToREPL " ft "<CR>"))
    ;
    ;     :send_visual "<Plug>(REPLSendVisual)"
    ;     :send_line "<Plug>(REPLSendLine)"
    ;     :send_operator "<Plug>(REPLSendOperator)"
    ;     :send_string "<Plug>(REPLExec)"
    ;     :close "<Plug>(REPLClose)"
    ;     :focus "<Plug>(REPLFocus)"
    ;     :hide "<Plug>(REPLHide)"
    ;     :toggle_focus "<Plug>(REPLHideOrFocus)"
    ; }
}
