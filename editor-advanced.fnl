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

{
    :move_down_suggestions "pumvisible() ? \"\\<C-n>\" : \"\\<Tab>\""
    :move_up_suggestions "pumvisible() ? \"\\<C-p>\" : \"\\<S-Tab>\""

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
