;; --------------------------------------------------------------------
;; Navigation
;;
;; Systems to find and open files, bounce between diagnostics, mark
;; files to come back to later, and other navigation tools.

;; TODO:
;; - MiniExtra.pickers.diagnostic
;; - setup brackets to iterate through stuff like diagnostics, fixlist, w/e.
;;   I actually think this is offered through mini.brackets or something...
;;   I would just want to set up mini.clue to make the forward/backward
;;   repeatable

;; TODO: mini.pick
;; - maybe a different binding to send selected elements to the quickfix list
;; - couple of bindings to iterate the quickfix list

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

;; TODO: this needs to set the cursor too
(fn arglist_pick [] (mini_pick.start {:source {:items vim.fn.argv :name :Arglist}}))

;; Create a new local arglist for each tabpage.
(vim.api.nvim_create_autocmd :TabNewEntered {
    :group augroup_module
    :command "argl|%argd"
})

;; arglist_open_cursor_or_last_buffer either focuses the buffer currently
;; pointed to by argidx, if it is not already focused; otherwise it opens the
;; previously focused buffer.
(fn arglist_open_cursor_or_last_buffer []
    (let [path (vim.fn.expand "%")
          args (-> (vim.fn.argv) (vim.iter) (: :enumerate))
          (current_idx) (args:find #(= path $2))
          argidx (+ 1 (vim.fn.argidx))]
        (if (or (= current_idx argidx) (= 0 (vim.fn.argc)))
            (let [key (vim.api.nvim_replace_termcodes :<C-^> true false true)]
                (vim.api.nvim_feedkeys key :n false))
        :else
            (vim.cmd.argument))))

;; arglist_shift moves through the arglist, updating argidx, with wrapping.
(fn arglist_shift [n]
    (let [target_idx (+ n (vim.fn.argidx))
          target_idx (% target_idx (vim.fn.argc))
          diff (- target_idx (vim.fn.argidx))]
        (if (< diff 0)
            (vim.cmd (.. (tostring (math.abs diff)) "prev"))
        :else
            (vim.cmd (.. (tostring (math.abs diff)) "next"))))
    (vim.cmd :args))

(fn arglist_next [] (arglist_shift 1))
(fn arglist_prev [] (arglist_shift -1))


;; TODO: this is going to need to be tab-aware eventually...
;; the buffer we'll be showing in the floating window...
;; the window we'll make float, appear, and disappear

; H.buffer_create = function()
;   local buf_id = vim.api.nvim_create_buf(false, true)
;   H.set_buf_name(buf_id, 'content')
;   vim.bo[buf_id].filetype = 'mininotify'
;   return buf_id
; end

;; For setting buffer contents:
;; https://github.com/echasnovski/mini.nvim/blob/main/lua/mini/notify.lua#L738C1-L738C17

; let buf = nvim_create_buf(v:false, v:true)
; call nvim_buf_set_lines(buf, 0, -1, v:true, ["test", "text"])
; let opts = {'relative': 'cursor', 'width': 10, 'height': 2, 'col': 0,
;     \ 'row': 1, 'anchor': 'NW', 'style': 'minimal'}
; let win = nvim_open_win(buf, 0, opts)
; " optional: change highlight, otherwise Pmenu is used
; call nvim_set_option_value('winhl', 'Normal:MyHighlight', {'win': win})


;; In mini.notify, the lifecycle of the notification window is managed by
;; tracking the list of active notifications, and starting a timer for each
;; notification to be removed from that list once it is done, refreshing the
;; overall notification system each time. During a refresh, if there are no
;; active notifications, the window is closed.

;; I could probably do a similar thing here, but maybe just updating an
;; incrementing counter or something so a defered function knows if it is
;; still in charge of the window or not.

;; That's if I want it to be based on a raw delay. That's the easiest,
;; certainly.

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

    : arglist_open_cursor_or_last_buffer
    : arglist_add
    : arglist_clear
    : arglist_delete
    : arglist_next
    : arglist_prev
    : arglist_pick
}

