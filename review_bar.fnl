;; ----------------------------------------------------------------------------
;; Review bar
;;
;; While review mode is on, the tabline becomes a second status line for the
;; review: what's being reviewed (the pull request, the base and branch) on
;; the left; on the right, where the current file is among the files not done
;; yet, how many are done, and which hunk of the file the cursor is in. Tabs,
;; when there's more than one, are listed before the file and hunk.
;;
;; It's laid out like the status line, with mini.statusline, and colored by
;; whose change it is: blue for your own, green for someone else's pull
;; request (grey until that's known). The highlight groups are
;; ReviewBar{Self,Other,Pending}{Block,Text,Dim}: Block for the end sections,
;; colored like the status line's mode, and Text and Dim for the text between.

(local review (require :review_mode))
(local mini_statusline (require :mini.statusline))

(local H {
    ;; Tabline options from before review mode, restored after.
    :saved nil
    ;; Branch being reviewed.
    :branch nil
    ;; Pull request for {root branch}: {:number :title :url :author}, false
    ;; when the branch has none, or :loading.
    :prs {}
    ;; Your GitHub login, false if it can't be found, or :loading.
    :login nil
    ;; Hunk text last drawn, to redraw only when it changes.
    :hunk nil
})

(fn hl_color [name attr]
    (let [value (. (vim.api.nvim_get_hl 0 {: name :link false}) attr)]
        (when value (string.format "#%06x" value))))

(fn blend [color base amount]
    "Mix `amount` of `color` into `base`, both as #rrggbb."
    (let [channel (fn [hex i] (tonumber (hex:sub (+ 2 (* 2 i)) (+ 3 (* 2 i))) 16))]
        (.. "#" (table.concat
                    (fcollect [i 0 2]
                        (string.format "%02x" (math.floor (+ 0.5 (* amount (channel color i))
                                                             (* (- 1 amount) (channel base i))))))
                    ""))))

(fn set_highlights []
    (let [(ok palettes) (pcall require :no-clown-fiesta.palettes)
          palette (when (and ok (= vim.g.colors_name :no-clown-fiesta)) (palettes.get :dark))
          bg (or (hl_color :Normal :bg) "#151515")]
        (each [kind color (pairs {:Self (or (?. palette :blue) (hl_color :DiagnosticInfo :fg) "#bad7ff")
                                  :Other (or (?. palette :green) (hl_color :DiagnosticOk :fg) "#90a959")})]
            (vim.api.nvim_set_hl 0 (.. :ReviewBar kind :Block) {:fg bg :bg color :default true})
            (vim.api.nvim_set_hl 0 (.. :ReviewBar kind :Text) {:fg color :bg bg :default true})
            (vim.api.nvim_set_hl 0 (.. :ReviewBar kind :Dim) {:fg (blend color bg 0.6) :bg bg :default true}))
        (each [name link (pairs {:ReviewBarPendingBlock :MiniStatuslineModeNormal
                                 :ReviewBarPendingText :MiniStatuslineFilename
                                 :ReviewBarPendingDim :MiniStatuslineDevinfo})]
            (vim.api.nvim_set_hl 0 name {: link :default true}))))

(set_highlights)

(fn git [args cwd]
    (let [res (: (vim.system (vim.list_extend [:git] args) {:cwd cwd :text true}) :wait)]
        (when (= res.code 0) (vim.trim res.stdout))))

(fn pr_key [root branch] (.. root "\1" (or branch "")))

(fn fetch_pr [root branch]
    "Look up the pull request for `branch`, and your login, in the background."
    (let [key (pr_key root branch)]
        (when (= H.login nil)
            (set H.login :loading)
            (vim.system [:gh :api :user :--jq :.login] {:cwd root :text true}
                (vim.schedule_wrap (fn [res]
                    (set H.login (and (= res.code 0) (not= (vim.trim res.stdout) "") (vim.trim res.stdout)))
                    (vim.cmd.redrawtabline)))))
        (when (= nil (. H.prs key))
            (tset H.prs key (if branch :loading false))
            (when branch
                (vim.system [:gh :pr :view branch :--json "number,title,url,author"] {:cwd root :text true}
                    (vim.schedule_wrap (fn [res]
                        (let [(ok pr) (if (= res.code 0) (pcall vim.json.decode res.stdout) (values false nil))]
                            (tset H.prs key (and ok (= (type pr) :table) pr.number pr))
                            (vim.cmd.redrawtabline)))))))))

(fn kind [pr]
    "Whose change this is: :Self, :Other, or :Pending while that isn't known."
    (if (or (= pr :loading) (and pr (= H.login :loading)))
        :Pending
        (and pr H.login (?. pr :author :login) (not= pr.author.login H.login))
        :Other
        :Self))

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

(fn tabs [hl]
    (let [count (vim.fn.tabpagenr :$)
          current (vim.fn.tabpagenr)]
        (if (<= count 1)
            ""
            (table.concat
                (fcollect [i 1 count]
                    (.. "%" i "T%#" (if (= i current) (.. hl :Text) (.. hl :Dim)) "# " i " "))
                ""))))

(fn render []
    (let [base (review.base)]
        (if (= base nil)
            ""
            (let [since (and (base.ref:match "^%x+$") (vim.startswith base.sha base.ref))
                  pr (. H.prs (pr_key base.root H.branch))
                  hl (.. :ReviewBar (kind pr))
                  progress (review.progress)
                  hunk (hunk_text)
                  file (file_text)
                  info []]
                (set H.hunk hunk)
                (when ((. (require :review_overview) :writing)) (table.insert info "writing overview…"))
                (when vim.b.review_file (table.insert info "base version"))
                (when (and progress (> progress.done_count 0) (> progress.n 0))
                    (table.insert info (string.format "%d/%d done" progress.done_count progress.total)))
                (mini_statusline.combine_groups [
                        {:hl (.. hl :Block) :strings ["REVIEW"]}
                        {:hl (.. hl :Dim) :strings [(escape (.. (if since (.. "since " (base.ref:sub 1 10)) base.ref)
                                                                (if H.branch (.. " → " H.branch) "")))]}
                        "%<"
                        {:hl (.. hl :Text) :strings [(if (= (type pr) :table)
                                                         (escape (.. "#" pr.number " " (shorten (or pr.title "") 80)))
                                                         "")]}
                        "%="
                        {:hl (.. hl :Dim) :strings [(escape (table.concat info " · "))]}
                        (tabs hl)
                        "%T"
                        {:hl (.. hl :Block) :strings [(escape (table.concat (icollect [_ text (pairs [file hunk])] text) " · "))]}])))))

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
