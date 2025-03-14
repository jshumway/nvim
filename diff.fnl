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

(local mini_diff (require :mini.diff))
(mini_diff.setup {})

(fn trim [s]
   (s:gsub "^%s*(.-)%s*$" "%1"))

(fn escape [s]
    (s:gsub "[%-%.%+%[%]%(%)%$%^%%%?%*]" "%%%1"))

(fn get_current_file_contents_at_merge_base []
    (local root (trim (vim.fn.system [:git :rev-parse :--show-toplevel])))
    (local current_path_abs (vim.fn.expand "%:p"))
    (local current_path_from_git_root (string.gsub current_path_abs (escape (.. root "/")) ""))
    (vim.notify (fv current_path_from_git_root))
    (local merge_base (trim (vim.fn.system [:git :show-branch :--merge-base])))
    (vim.fn.system [:git :show (.. merge_base ":" current_path_from_git_root)]))

(fn set_merge_base_as_ref_text []
    ;; TODO: OR, maybe we just need to configure this buffer to use source "none", so
    ;; that it won't update, and we'll just be able to see the differences vs the text
    ;; on disk. It only needs to be a real source if we want it to react to changes
    ;; (which we probably do).
    (mini_diff.toggle_overlay)
    (mini_diff.set_ref_text 0 (get_current_file_contents_at_merge_base)))

;; TODO: review mode: build on mini.diff's overlay view to create a mode where
;; it is easy to review changes between the current state of files and a specific
;; point in git history. E.g., vs another feature branch, vs master, vs the index.
;;
;; The idea would be that you turn the mode on (globally) and select the base.
;; Then whenever you enter a file, the reference is taken from that base as the
;; comparison point for mini.diff. Combine this with a way to jump between changed
;; files (list collect from `git status --short`), and you'll bounce between files
;; and they'll automatically have the diff calculated from the right point.
;;
;; This can probably replace my desired usage of Diffview entierly.

{
    ;; TODO: have this command reset the reference text to be the index or whatever...
    :toggle_inline_changes mini_diff.toggle_overlay
    :test set_merge_base_as_ref_text
    ;; NOTE: disabled, only exports from open buffers
    ; :export_to_quickfix #(vim.fn.setqflist (mini_diff.export :qf {:scope :all}))
}

