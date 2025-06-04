(local augroup_module (vim.api.nvim_create_augroup :user_ai {:clear true}))

(local Terminal (-> (require :toggleterm.terminal) (. :Terminal)))

(fn create_goose_terminal []
    (Terminal:new {
        :display_name :goose
        :cmd "pay goose"
        ; :direction :vertical
        :direction :float
        :count 0
    }))

{
    : create_goose_terminal

    :on_goose_term_enter
    #(vim.api.nvim_create_autocmd :TermEnter
        {:pattern "term://*goose*toggleterm#*" :group augroup_module :callback $})
}

