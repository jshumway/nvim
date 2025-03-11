;; --------------------------------------------------------------------
;; Editor Advanced

;; TODO:
;; - enable conform
;; - lsp motions: expand / shrink selection
;; - add linter / lsp error diagnostics stuff to status bar
;; - lsp rename opens buffers that it modifies... either want it to write automatically
;;   (so I can manage via git) or be able to quickly navigate between them, by like
;;   having the modified files in a quick list
;; - setup generic LSP stuff and have lang specific stuff in their own files?

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

(let [_ (mini_deps.add {:source :neovim/nvim-lspconfig})
      m (require :lspconfig)]
    nil

    ; (each [_ lsp (ipairs [:gopls])]
    ;     ((. m lsp :setup) {}))
    )

; (later-let [_ (mini_deps.add {:source :stevearc/conform.nvim
;                     :depends ["git@git.corp.stripe.com:stevearc/nvim-stripe-configs"]})
;             m (require :conform)]
;     (m.setup {
;         :formatters_by_ft {
;             :javascript ["prettierd"]
;             :typescript ["prettierd"]
;             :javascriptreact [ "prettierd" ]
;             :typescriptreact [ "prettierd" ]
;             :html [ "prettierd" ]
;             :json [ "prettierd" ]
;             :jsonc [ "prettierd" ]
;             :graphql [ "prettierd" ]
;             :go [:goimports :gofmt]
;             :lua [ "stylua" ]
;             :python [ "zoolander_format_python" ]
;             :sql [ "zoolander_format_sql" ]
;             :bzl [ "zoolander_format_build" ]
;             :java [ "zoolander_format_java" ]
;             :scala [ "zoolander_format_scala" ]
;             :terraform [ "sc_terraform" ]
;         }
;         :format_after_save {:lsp_format :fallback}
;     }))

(local mini-extra (require :mini.extra))

{
    :on_lsp_attach
    #(vim.api.nvim_create_autocmd :LspAttach {:pattern "*" :group augroup_module :callback $})

    :definition vim.lsp.buf.definition
    :type_definition #(mini-extra.pickers.lsp {:scope :type_definition})
    :references #(mini-extra.pickers.lsp {:scope :references})
    :implementation #(mini-extra.pickers.lsp {:scope :implementation})
    :declaration #(mini-extra.pickers.lsp {:scope :declaration})

    :signature_help vim.lsp.buf.signature_help 
    :hover vim.lsp.buf.hover 

    :rename vim.lsp.buf.rename 
    :code_action vim.lsp.buf.code_action 
}
