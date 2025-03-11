;; --------------------------------------------------------------------
;; Diff

;; TODO:
;; - hotkeys for jumping to next/prev changed hunk
;; - view hunk diff at current line in pop-up (w/ yanking)
;; - picker for files that have changed from the base of the branch (and since
;;   the previous commit, and unstaged)

; (map :n "[C" "]c" {:noremap true :silent true :desc "Next change"})
; (map :n "]C" "[c" {:noremap true :silent true :desc "Prev change"})
; (vim.opt.fillchars:append {:diff  "🞌"})
; ; (tset vim.o :diffopt "filler,context:500")

;; TODO: Diffview
;; - figure out what here is actually useful in various workflows
;;   e.g., code review, reviewing my PR before pushing it, debugging,
;;   finding a part of a changed file in my branch, etc
;; - hide the diffviewer tab / tabline (although maybe this is actually
;;   a good use of it?)
;;      - if hidden, then we need a hotkey to bounce between the diff
;;        view and the main tab
;; - if using Diffview, is there a way to stop it from messing up my
;;   <Leader> hotkeys?
;; - detect the error condition where `!git remote set-head...` hasn't
;;   been run and run it automatically against main or master

; (let [_ (add :sindrets/diffview.nvim)
;             m (require :diffview)]
;     (m.setup {
;         :enhanced_diff_hl true
;         :file_panel {
;             :listing_style :list
;         }
;         :hooks {
;             :diff_buf_win_enter (fn [bufnr winid ctx]
;                 ;; Turn off cursor line for diffview windows because of bg conflict
;                 ;; https://github.com/neovim/neovim/issues/9800.
;                 (tset vim.wo winid :culopt :number)
;             )
;         }
;     })
;
;     (map :n :<Leader>dH ":!git remote set-head -a origin<CR>" {:noremap true :desc "Set origin/HEAD"})
;     (map :n :<Leader>dM ":DiffviewOpen origin/HEAD...HEAD --imply-local<CR>" {:noremap true :desc "Diff origin/HEAD"})
;     (map :n :<Leader>dw ":DiffviewOpen HEAD --imply-local<CR>" {:noremap true :desc "Working changes"})
;     (map :n :<Leader>dc ":DiffviewFileHistory --range=origin/HEAD...HEAD --right-only --no-merges"
;          {:noremap true :desc "Diff commits from HEAD"})
;     (map :n :<Leader>dC ":DiffviewClose<CR>" {:noremap true :desc "Close"})
;     )

(let [m (require :mini.diff)]
    (m.setup {}))

{}

