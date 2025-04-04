;; --------------------------------------------------------------------
;; Editor Advanced

;; TODO:
;; - add linter / lsp error diagnostics stuff to status bar
;; - lsp rename opens buffers that it modifies... either want it to write automatically
;;   (so I can manage via git) or be able to quickly navigate between them, by like
;;   having the modified files in a quick list

(local mini_deps (require :mini.deps))

(local augroup_module (vim.api.nvim_create_augroup :user_editor_advanced {:clear true}))

(let [_ (mini_deps.add {:source :nvim-treesitter/nvim-treesitter
             :checkout :master :monitor :main
    	     :hooks {:post_checkout #(vim.cmd :TSUpdate)}})
      m (require :nvim-treesitter.configs)]
    (m.setup {
        :ensure_installed [:lua :vimdoc :ruby :fennel]
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

(local orig_open_floating_window vim.lsp.util.open_floating_preview)
(fn custom_open_floating_preview [contents syntax opts ...]
    (tset opts :max_width 120)
    (tset opts :border :single)
    (local (bufnr winid) (orig_open_floating_window contents syntax opts ...)))
(tset _G.vim.lsp.util :open_floating_preview custom_open_floating_preview)

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

(local mini-extra (require :mini.extra))


(let [_ (mini_deps.add {:source "milanglacier/yarepl.nvim"})
      yr (require :yarepl)]
    (yr.setup {
        :wincmd ...
        :metas {}
    }))

; (let [_ (mini_deps.add {:source :Vigemus/iron.nvim})
;       m (require :iron.core)
;       common (require :iron.fts.common)
;       view (require :iron.view)]
;     (m.setup {
;         :config {
;             :scratch_repl true
;             :repl_definition { }
;             :repl_filetype (fn [bufnr ft] ft)
;             :repl_open_cmd (view.split.vertical.botright 90 {
;                 :number false
;             })
;         }
;         :ignore_blank_lines true
;     }))

; (local iron (require :iron.core))
; (local iron_marks (require :iron.marks))

{
    :move_down_suggestions "pumvisible() ? \"\\<C-n>\" : \"\\<Tab>\""
    :move_up_suggestions "pumvisible() ? \"\\<C-p>\" : \"\\<S-Tab>\""

    :on_lsp_attach
    #(vim.api.nvim_create_autocmd :LspAttach {:pattern "*" :group augroup_module :callback $})

    :code_action vim.lsp.buf.code_action
    :declaration #(mini-extra.pickers.lsp {:scope :declaration})
    :definition vim.lsp.buf.definition
    :hover vim.lsp.buf.hover
    :implementation #(mini-extra.pickers.lsp {:scope :implementation})
    :outline vim.lsp.buf.document_symbol
    :references #(mini-extra.pickers.lsp {:scope :references})
    :rename vim.lsp.buf.rename
    :signature_help vim.lsp.buf.signature_help
    :type_definition #(mini-extra.pickers.lsp {:scope :type_definition})

    :repl {
        ; :start_and_attach "<CMD>REPLStart!<CR>"
        ; :attach "<CMD>REPLAttachBufferToREPL<CR>"
        :send_visual "<Plug>(REPLSendVisual)"
        :send_line "<Plug>(REPLSendLine)"
        :send_operator "<Plug>(REPLSendOperator)"
        :send_string "<Plug>(REPLExec)"
        :close "<Plug>(REPLClose)"
        :focus "<Plug>(REPLFocus)"
        :hide "<Plug>(REPLHide)"
        :toggle_focus "<Plug>(REPLHideOrFocus)"
    }

    ; :repl {
    ;     :send_motion #(iron.run_motion :send_motion)
    ;     :send_mark iron.send_mark
    ;     :send_line iron.send_line
    ;     :send_until_cursor iron.send_until_cursor
    ;     :send_file iron.send_file
    ;     :send_visual iron.visual_send
    ;     :send_paragraph iron.send_paragraph
    ;     :send_code_block #(iron.send_code_block false)
    ;     :send_code_block_and_move #(iron.send_code_block true)
    ;
    ;     :restart #(vim.cmd "IronRestart")
    ;     :toggle #(vim.cmd "IronRepl")
    ;
    ;     :mark_motion #(iron.run_motion :mark_motion)
    ;     :mark_visual iron.mark_visual
    ;     :remove_mark iron_marks.drop_last
    ;     :clear_hl iron_marks.clear_hl
    ;
    ;     :cr #(iron.send nil (string.char 13))
    ;     :interrupt #(iron.send nil (string.char 3))
    ;     :clear #(iron.send nil (string.char 12))
    ;     :send_q #(iron.send nil :q)
    ;     :exit iron.close_repl
    ; }
}
