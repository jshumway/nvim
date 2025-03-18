;; --------------------------------------------------------------------
;; Terminal

;; TODO:
;; - disable statusline in terminal
;; - easy copy/paste between terminal and other buffers
;; - copy/paste to/from system clipboard, working over SSH

(local mini_deps (require :mini.deps))

(local augroup_module (vim.api.nvim_create_augroup :user_terminal {:clear true}))

(let [_ (mini_deps.add {:source :akinsho/toggleterm.nvim})
      m (require :toggleterm)]
    (m.setup))

{
    :on_term_enter 
    #(vim.api.nvim_create_autocmd :TermEnter
        {:pattern "term://*toggleterm#*" :group augroup_module :callback $})

    :normal_toggle_terminal "<Cmd>exe v:count1 . \"ToggleTerm\"<CR>"
    :insert_toggle_terminal "<Esc><Cmd>exe v:count1 . \"ToggleTerm\"<CR>"

    :escape_from_terminal_insert_mode "<C-\\><C-n>"
}

