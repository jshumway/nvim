;; --------------------------------------------------------------------
;; Navigation
;;
;; Systems to find and open files, bounce between diagnostics, mark
;; files to come back to later, and other navigation tools.

;; TODO:
;; - fix: live (and non-live) grep across the codebase (mini.fuzzy)
;; - need a way for (live)grep to be started with the current directory as the
;;   limiting path, as part of the search string so it is editable
;;
;; - mini.files binding for opening a file and closing the picker
;;      - honestly not sure what this means... like a single key way to do it?
;; - MiniPick.files key to open on right side of vsplit
;;
;; - MiniExtra.pickers.diagnostic
;; - setup brackets to iterate through stuff like diagnostics, fixlist, w/e

;; TODO: mini.pick + fixlist integration
;; - swap out quicklists (to files), saving the current one
;; - delete the current quicklist (and its file)
;; - send everything in a picker to the quicklist
;; - hotkeys to navigate the quicklist - ctrl-n/p
;; - this is probably its own little extension to manage quicklists in this
;;   way, and then could be integrated into any picker
;; - maybe I could call it picklist...

;; TODO: file marking system
;; - set a global "mark namespace" key
;;      - can be set automatically when git branch changes
;;      - or can be set manually (like a project name)
;;      - displays in status line
;; - use mini.visits to mark a file w/in the current namespace
;; - open a picker with files marked in the current namespace

(local augroup_module (vim.api.nvim_create_augroup :user_navigation {:clear true}))

(local mini_pick (require :mini.pick))
(local mini_extra (require :mini.extra))

(local mini_files (require :mini.files))
(mini_files.setup {
    :windows {
        :preview true
        :width_preview 120
    }
})

(tset mini_pick.registry :files (fn [local_opts]
    (local opts {:source {:cwd local_opts.cwd}})
    (tset local_opts :cwd nil)
    (mini_pick.builtin.files local_opts opts)))

(tset mini_pick.registry :grep_live (fn [local_opts]
    (local opts {:source {:cwd local_opts.cwd}})
    (tset local_opts :cwd nil)
    (mini_pick.builtin.grep_live local_opts opts)))

(tset mini_pick.registry :grep (fn [local_opts]
    (local opts {:source {:cwd local_opts.cwd}})
    (tset local_opts :cwd nil)
    (mini_pick.builtin.grep local_opts opts)))

;; NOTE: Required for mini_extra.pickers.visit_paths to function.
(local mini_visits (require :mini.visits))
(mini_visits.setup)

(local mini_fuzzy (require :mini.fuzzy))
(mini_fuzzy.setup)

(fn buffer_basename []
    (string.gsub (vim.fn.expand "%:p") PATH_PATTERN "%1"))

(fn explore_files_at_current_path []
    (mini_files.open (buffer_basename)))

(local mini_deps (require :mini.deps))

(let [_ (mini_deps.add :stevearc/quicker.nvim)
      m (require :quicker)]
    (m.setup))

;; TODO: quickfix / location list nav?
;; TODO: marks?

;; --------------------------------------------------------------------
;; Arglist

(local arglist_add "<CMD>$arge %<BAR>argded<BAR>args<CR>")

(local arglist_delete "<CMD>argd %<BAR>args<CR>")
(local arglist_clear "<CMD>%argd<CR><C-L>")

;; TODO: cycle around list
(local arglist_prev "<CMD>exe v:count1 .. 'N'<BAR>args<CR><ESC>")
(local arglist_next "<CMD>exe v:count1 .. 'n'<BAR>args<CR><ESC>")

(fn arglist_pick [] (mini_pick.start {:source {:items vim.fn.argv :name :Arglist}}))

(vim.api.nvim_create_autocmd :TabNewEntered {
    :group augroup_module
    :command "argl|%argd"
})

;; --------------------------------------------------------------------
;; Handle line numbers in file names

(mini_deps.add {:source "lewis6991/fileline.nvim"})
(vim.cmd "packadd fileline.nvim")

{
    :pick_recent #(mini_extra.pickers.visit_paths {:recency_weight 1 :preserve_order true})
    :pick_frequent #(mini_extra.pickers.visit_paths {:recency_weight 0})

    :pick_files mini_pick.builtin.files
    :pick_files_at_path #(mini_pick.registry.files {:cwd (buffer_basename)})
    :pick_grep_live mini_pick.builtin.grep_live
    :pick_grep_live_at_path #(mini_pick.registry.grep_live {:cwd (buffer_basename)})
    :pick_grep mini_pick.builtin.grep
    :pick_grep_at_path #(mini_pick.builtin.grep {:cwd (buffer_basename)})

    : explore_files_at_current_path

    ;; unclear if these should actually be defined here
    :resume_last_picker mini_pick.builtin.resume
    :pick_help mini_pick.builtin.help

    : arglist_add
    : arglist_clear
    : arglist_delete
    : arglist_next
    : arglist_prev
    : arglist_pick
}

