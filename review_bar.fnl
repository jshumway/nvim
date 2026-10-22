;; ----------------------------------------------------------------------------
;; Review bar
;;
;; While review mode is on, the tabline becomes a second status line for the
;; review: what's being reviewed (the pull request, the base and branch) on
;; the left; on the right, where the current file is among the files not done
;; yet, how many are done, and which hunk of the file the cursor is in. Tabs,
;; when there's more than one, are listed at the far right.
;;
;; The highlight groups link to mini.statusline's, unless the colorscheme sets
;; them: ReviewBarBadge, ReviewBar, ReviewBarItem and ReviewBarDim.

(local review (require :review_mode))

(local H {
    ;; Tabline options from before review mode, restored after.
    :saved nil
    ;; Branch being reviewed.
    :branch nil
    ;; Pull request for {root branch}: {:number :title :url}, or false when
    ;; the branch has none.
    :prs {}
    ;; Hunk text last drawn, to redraw only when it changes.
    :hunk nil
})

(fn set_highlights []
    (each [name link (pairs {:ReviewBarBadge :MiniStatuslineModeOther
                             :ReviewBar :MiniStatuslineFilename
                             :ReviewBarItem :MiniStatuslineDevinfo
                             :ReviewBarDim :MiniStatuslineInactive})]
        (vim.api.nvim_set_hl 0 name {: link :default true})))

(set_highlights)

(fn git [args cwd]
    (let [res (: (vim.system (vim.list_extend [:git] args) {:cwd cwd :text true}) :wait)]
        (when (= res.code 0) (vim.trim res.stdout))))

(fn pr_key [root branch] (.. root "\1" (or branch "")))

(fn fetch_pr [root branch]
    "Look up the pull request for `branch`, in the background."
    (let [key (pr_key root branch)]
        (when (and branch (= nil (. H.prs key)))
            (tset H.prs key false)
            (vim.system [:gh :pr :view branch :--json "number,title,url"] {:cwd root :text true}
                (vim.schedule_wrap (fn [res]
                    (let [(ok pr) (if (= res.code 0) (pcall vim.json.decode res.stdout) (values false nil))]
                        (when (and ok (= (type pr) :table) pr.number)
                            (tset H.prs key pr)
                            (vim.cmd.redrawtabline)))))))))

(fn escape [text] (pick-values 1 (text:gsub "%%" "%%%%")))

(fn shorten [text width]
    (if (<= (vim.fn.strchars text) width)
        text
        (.. (vim.fn.strcharpart text 0 (- width 1)) "…")))

(fn hunk_text []
    (let [{: i : n} (review.hunk_position)]
        (when (> n 0)
            (string.format "hunk %s/%d" (if i (tostring i) "-") n))))

(fn file_text []
    (let [p (review.progress)]
        (when p
            (if (= p.n 0) "✓ all files done"
                p.i (string.format "file %d/%d" p.i p.n)
                p.done (string.format "file ✓, %d left" p.n)
                (string.format "file -/%d" p.n)))))

(fn tabs []
    (let [count (vim.fn.tabpagenr :$)
          current (vim.fn.tabpagenr)]
        (if (<= count 1)
            ""
            (table.concat
                (fcollect [i 1 count]
                    (.. "%" i "T" (if (= i current) "%#ReviewBarBadge#" "%#ReviewBarDim#") " " i " "))
                ""))))

(fn render []
    (let [base (review.base)]
        (if (= base nil)
            ""
            (let [since (and (base.ref:match "^%x+$") (vim.startswith base.sha base.ref))
                  pr (. H.prs (pr_key base.root H.branch))
                  progress (review.progress)
                  hunk (hunk_text)
                  file (file_text)
                  right []]
                (set H.hunk hunk)
                (when vim.b.review_file (table.insert right "base version"))
                (when file (table.insert right file))
                (when (and progress (> progress.done_count 0) (> progress.n 0))
                    (table.insert right (string.format "%d/%d done" progress.done_count progress.total)))
                (when hunk (table.insert right hunk))
                (when ((. (require :review_overview) :writing)) (table.insert right "writing overview…"))
                (.. "%#ReviewBarBadge# REVIEW "
                    "%#ReviewBarItem# "
                    (escape (if since (.. "since " (base.ref:sub 1 10)) base.ref))
                    (if H.branch (.. " → " (escape H.branch)) "")
                    " %#ReviewBar# "
                    (if pr (escape (.. "#" pr.number " " (shorten (or pr.title "") 80))) "")
                    "%<%="
                    (if (> (length right) 0)
                        (.. "%#ReviewBar# " (escape (table.concat right "  ·  ")) " ")
                        "")
                    (tabs)
                    "%T%#ReviewBar#")))))

(fn update []
    (let [base (review.base)]
        (when base
            (let [branch (git [:branch :--show-current] base.root)]
                (set H.branch (when (not= branch "") branch))
                (fetch_pr base.root H.branch)
                (vim.cmd.redrawtabline)))))

(fn show []
    (when (= H.saved nil)
        (set H.saved {:showtabline vim.o.showtabline :tabline vim.o.tabline}))
    (set vim.o.tabline "%!v:lua.require'review_bar'.render()")
    (set vim.o.showtabline 2)
    (update))

(fn hide []
    (when H.saved
        (set vim.o.showtabline H.saved.showtabline)
        (set vim.o.tabline H.saved.tabline)
        (set H.saved nil)))

(local augroup (vim.api.nvim_create_augroup :review_bar {:clear true}))

(vim.api.nvim_create_autocmd :User {:group augroup :pattern :ReviewStart :callback show})
(vim.api.nvim_create_autocmd :User {:group augroup :pattern :ReviewStop :callback hide})

;; The branch may have been switched outside of Neovim.
(vim.api.nvim_create_autocmd [:FocusGained :TermLeave :ShellCmdPost] {
    :group augroup
    :callback #(when H.saved (update))})

(vim.api.nvim_create_autocmd :ColorScheme {:group augroup :callback set_highlights})

(vim.api.nvim_create_autocmd :BufEnter {
    :group augroup
    :callback #(when H.saved (vim.cmd.redrawtabline))})

(vim.api.nvim_create_autocmd :User {
    :group augroup
    :pattern :MiniDiffUpdated
    :callback #(when H.saved (vim.cmd.redrawtabline))})

;; The tabline isn't redrawn as the cursor moves; redraw it when the cursor
;; goes into another hunk.
(vim.api.nvim_create_autocmd :CursorMoved {
    :group augroup
    :callback #(when (and H.saved (not= H.hunk (hunk_text)))
                   (vim.cmd.redrawtabline))})

{
    : render
}
