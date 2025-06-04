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
    (m.setup {
        :size #(if (= $.direction :horizontal) 20
                   (= $.direction :vertical) 120)
    }))

(local Terminal (-> (require :toggleterm.terminal) (. :Terminal)))

(fn create_terminal [?count]
    (Terminal:new {
        :direction :float
        ; :direction :horizontal
        :count (or ?count 1)
    }))

(let [_ (mini_deps.add {:source :xb-bx/editable-term.nvim})
      m (require :editable-term)]
    (m.setup {
        :promts {
            "$ " {}
            "❯ " {}
            ".. " {}
        }
    }))

{
    :on_term_enter
    #(vim.api.nvim_create_autocmd :TermEnter
        {:pattern "term://*toggleterm#*" :group augroup_module :callback $})

    : create_terminal

    :escape_from_terminal_insert_mode "<C-\\><C-n>"
    :terminal_insert_focus_window_up "<C-\\><C-N><C-w>k"

    :focus_or_toggle (fn [term]
        (if (and (term:is_open) (not (term:is_focused))) (term:focus)
            (and (term:is_open) (term:is_focused)) (term:close)
            (not (term:is_open)) (term:open)))
}

