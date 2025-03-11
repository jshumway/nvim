(local augroup_module (vim.api.nvim_create_augroup :user_buffer {:clear true}))

;; --------------------------------------------------------------------
;; Buffer persistence
;;
;; Disable swapfiles, autosave and reload buffers regularly. Ideally
;; this will make vim play nice with frequent git checkouts.

(tset vim.o :swapfile false)
(tset vim.o :autowriteall true)

;; https://unix.stackexchange.com/a/383044
(vim.api.nvim_create_autocmd [:FocusGained :BufEnter :CursorHold :CursorHoldI] {
    :group augroup_module
    :pattern "*"
    :command "if mode() !~ '\v(c|r.?|!|t)' && getcmdwintype() == '' | checktime | endif"
})

(vim.api.nvim_create_autocmd [:FileChangedShellPost] {
    :group augroup_module
    :pattern "*"
    :callback (fn [] (vim.notify "File changed on disk; buffer reloaded."))
})

;; --------------------------------------------------------------------
;; Buffer management

(local bufremove (require :mini.bufremove))
(bufremove.setup {})

(local mini_pick (require :mini.pick))

{
    :wipeout bufremove.wipeout
    :last_buffer :<c-^>
    :next_buffer ":bnext<CR>"
    :prev_buffer ":bprevious<CR>"
    :pick_buffers mini_pick.builtin.buffers
}

