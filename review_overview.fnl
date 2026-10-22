;; ----------------------------------------------------------------------------
;; Review overview
;;
;; A short overview of the change under review: what it does and why, then
;; the changed files, most important first, each with a line on what it does
;; and why it's part of the change. Test files sit under the file they test.
;; Files that rarely matter (package files, generated code, lockfiles) are
;; listed at the bottom without a description.
;;
;; The overview also sets the review order: next/prev file and the hunk jumps
;; that cross files follow it.
;;
;; Overviews live in the git dir, one per head commit:
;; `$(git rev-parse --git-path review-overview)/<head>.json`. A fleet worker
;; writes one when it hands a change over for review; otherwise `claude -p`
;; writes one in the background when review mode starts. Each is rendered to
;; a markdown file next to it, with paths from the repo root, so `gf` opens a
;; file and <CR> opens it at its first change.
;;
;; The JSON: {"summary": "...", "files": [{"path": "...", "why": "...",
;; "tests": [{"path": "...", "why": "..."}]}]}, plus optional "title" and
;; "url".

(local review (require :review_mode))

(local H {
    ;; Heads an overview is being written for.
    :generating {}
    ;; Head whose overview should open once it's written.
    :open_when_ready nil
    ;; {:root :head :md} of the overview in use.
    :current nil
})

(when (= vim.g.review_overview_auto nil) (set vim.g.review_overview_auto true))

;; Matched against the file name, or with a "/" against the whole path.
(local LOW_SIGNAL ["^__package%.rb$" "%.rbi$" "^BUILD$" "^BUILD%.bazel$" "%.lock$" "^go%.sum$"
                   "^package%-lock%.json$" "^pnpm%-lock%.yaml$" "%.pb%.go$" "_pb%.rb$" "_pb2%.pyi?$"
                   "%.snap$" "/generated/" "^generated/"])

(local SCHEMA (vim.json.encode {
    :type :object
    :required [:summary :files]
    :properties {
        :summary {:type :string}
        :files {:type :array
                :items {:type :object
                        :required [:path :why]
                        :properties {:path {:type :string}
                                     :why {:type :string}
                                     :tests {:type :array
                                             :items {:type :object
                                                     :required [:path :why]
                                                     :properties {:path {:type :string}
                                                                  :why {:type :string}}}}}}}}}))

;; Characters of diff to send; larger diffs are cut down per file.
(local DIFF_BUDGET 150000)

;; ----------------------------------------------------------------------------
;; Helpers

(fn git [args cwd]
    (let [res (: (vim.system (vim.list_extend [:git] args) {:cwd cwd :text true}) :wait)]
        (when (= res.code 0) (vim.trim res.stdout))))

(fn low_signal? [rel]
    (let [name (vim.fs.basename rel)]
        (accumulate [found false _ pattern (ipairs (or vim.g.review_low_signal LOW_SIGNAL)) &until found]
            (not= nil (if (pattern:find "/" 1 true) (rel:find pattern) (name:find pattern))))))

(fn overview_dir [root]
    (let [dir (git [:rev-parse :--git-path :review-overview] root)]
        (when dir (if (vim.startswith dir "/") dir (.. root "/" dir)))))

(fn read_overview [path]
    (when (= 1 (vim.fn.filereadable path))
        (let [(ok data) (pcall vim.json.decode (table.concat (vim.fn.readfile path) "\n")
                               {:luanil {:object true :array true}})]
            (when (and ok (= (type data) :table) (= (type data.files) :table)) data))))

(fn plan [data rels]
    "Order the changed files `rels`: the described ones in the overview's
    order with their tests after them, then any it left out, then the
    low-signal ones."
    (let [changed {}
          seen {}
          entries []
          missing []
          low []
          order []]
        (each [_ rel (ipairs rels)] (tset changed rel true))
        (fn take [path]
            (when (and (= (type path) :string) (. changed path) (not (. seen path)) (not (low_signal? path)))
                (tset seen path true)
                true))
        (each [_ file (ipairs data.files)]
            (when (take file.path)
                (table.insert entries {:path file.path :why file.why
                                       :tests (icollect [_ test (ipairs (or file.tests []))]
                                                  (when (take test.path) test))})))
        (each [_ rel (ipairs rels)]
            (when (not (. seen rel))
                (table.insert (if (low_signal? rel) low missing) rel)))
        (table.sort missing)
        (table.sort low)
        (each [_ entry (ipairs entries)]
            (table.insert order entry.path)
            (each [_ test (ipairs entry.tests)] (table.insert order test.path)))
        (vim.list_extend order missing)
        (vim.list_extend order low)
        {: entries : missing : low : order}))

(fn text_lines [text indent]
    (icollect [_ line (ipairs (vim.split (vim.trim (or text "")) "\n" {:plain true}))]
        (.. indent line)))

(fn render [data p branch]
    (let [lines [(.. "# " (or data.title branch "Overview"))]]
        (when data.url (table.insert lines data.url))
        (table.insert lines "")
        (vim.list_extend lines (text_lines data.summary ""))
        (table.insert lines "")
        (table.insert lines "## Files")
        (each [i entry (ipairs p.entries)]
            (table.insert lines "")
            (table.insert lines (.. i ". " entry.path))
            (vim.list_extend lines (text_lines entry.why "   "))
            (each [_ test (ipairs entry.tests)]
                (table.insert lines (.. "   - " test.path))
                (vim.list_extend lines (text_lines test.why "     "))))
        (when (> (length p.missing) 0)
            (vim.list_extend lines ["" "## Not described" ""])
            (each [_ rel (ipairs p.missing)] (table.insert lines (.. "- " rel))))
        (when (> (length p.low) 0)
            (vim.list_extend lines ["" "## Also changed" ""])
            (each [_ rel (ipairs p.low)] (table.insert lines (.. "- " rel))))
        lines))

;; ----------------------------------------------------------------------------
;; Writing an overview

(fn cut_diff [diff]
    "Keep the diff under DIFF_BUDGET by shortening the largest files' parts."
    (if (<= (length diff) DIFF_BUDGET)
        diff
        (let [parts (vim.split diff "\ndiff --git " {:plain true})
              limit (math.max 3000 (math.floor (/ DIFF_BUDGET (length parts))))]
            (table.concat
                (icollect [_ part (ipairs parts)]
                    (if (<= (length part) limit)
                        part
                        (.. (part:sub 1 limit) "\n[... rest of this file's diff left out ...]")))
                "\ndiff --git "))))

(fn build_prompt [root base pr rels]
    (let [files (icollect [_ rel (ipairs rels)] (when (not (low_signal? rel)) rel))
          commits (or (git [:log :--reverse "--format=- %s%n%b" (.. base.sha "..HEAD")] root) "")
          diff (if (> (length files) 0)
                   (or (git (vim.list_extend [:diff :--no-color :--no-ext-diff :-U5 base.sha :HEAD :--] files) root) "")
                   "")]
        (table.concat
            ["You are writing a short overview of a code change for the engineer reviewing it."
             ""
             "Return:"
             "- summary: two or three plain sentences: what the change does, and why."
             (.. "- files: the changed files listed below, most important first: the core logic of the "
                 "change, then the code that supports it, then config and docs. Give each one a `why`: "
                 "one short sentence on what its change does and why it is part of this change. Put "
                 "each test file in `tests` under the production file it tests, not in the top-level "
                 "list; a test that covers several files goes under the most important one. Use the "
                 "paths exactly as listed.")
             ""
             (if pr
                 (.. "Pull request: " (or pr.title "") "\n\n" (: (or pr.body "") :sub 1 6000))
                 "")
             ""
             "Commits:"
             (commits:sub 1 8000)
             ""
             "Changed files:"
             (table.concat files "\n")
             ""
             "Diff:"
             (cut_diff diff)]
            "\n")))

(var apply nil)

(fn generate [root head base]
    "Write the overview for `head` with `claude -p`, in the background."
    (tset H.generating head true)
    (vim.cmd.redrawtabline)
    (vim.notify "Review: writing an overview of the change…")
    (let [rels (icollect [_ item (ipairs (or (review.items) []))] item.rel)
          dir (overview_dir root)]
        (vim.system [:gh :pr :view :--json "title,body,url"] {:cwd root :text true}
            (vim.schedule_wrap (fn [res]
                (let [(ok pr) (if (= res.code 0) (pcall vim.json.decode res.stdout) (values false nil))
                      pr (when (and ok (= (type pr) :table)) pr)]
                    (vim.system [:claude :-p :--model (or vim.g.review_overview_model :sonnet)
                                 :--output-format :json :--no-session-persistence
                                 :--tools "" :--json-schema SCHEMA]
                        {:cwd root :text true :stdin (build_prompt root base pr rels) :timeout 600000}
                        (vim.schedule_wrap (fn [out]
                            (tset H.generating head nil)
                            (vim.cmd.redrawtabline)
                            (let [(decoded result) (pcall vim.json.decode (or out.stdout ""))
                                  data (and decoded (= (type result) :table) result.structured_output)]
                                (if (and (= (type data) :table) (= (type data.files) :table))
                                    (do
                                        (set data.title (?. pr :title))
                                        (set data.url (?. pr :url))
                                        (vim.fn.mkdir dir :p)
                                        (vim.fn.writefile [(vim.json.encode data)] (.. dir "/" head ".json"))
                                        (apply root head))
                                    (vim.notify (.. "Review: couldn't write the overview: "
                                                    (: (vim.trim (.. (or out.stderr "") (or out.stdout ""))) :sub -400))
                                                vim.log.levels.ERROR))))))))))))

(set apply (fn [root head]
    "Use the overview for `head`: set the review order and render it."
    (let [dir (overview_dir root)
          data (and dir (read_overview (.. dir "/" head ".json")))
          base (review.base)]
        (when (and data base (= base.root root))
            (let [p (plan data (icollect [_ item (ipairs (or (review.items) []))] item.rel))
                  md (.. dir "/" head ".md")
                  branch (let [b (git [:branch :--show-current] root)] (when (not= b "") b))
                  first_time (not (and H.current (= H.current.head head)))]
                (vim.fn.writefile (render data p branch) md)
                (set H.current {: root : head : md})
                (review.set_order p.order)
                (if (or (= H.open_when_ready head)
                        ;; Started with nothing open, like `nvim +Review`.
                        (and first_time (= (vim.api.nvim_buf_get_name 0) "") (not vim.bo.modified)))
                    (do (set H.open_when_ready nil)
                        (vim.cmd.edit (vim.fn.fnameescape md)))
                    first_time
                    (vim.notify "Review: overview ready (<Leader>do)")))))))

(fn on_review_start []
    (let [base (review.base)
          root (?. base :root)
          head (and root (git [:rev-parse :HEAD] root))
          dir (and head (overview_dir root))]
        (when dir
            (if (= 1 (vim.fn.filereadable (.. dir "/" head ".json")))
                (apply root head)
                (and vim.g.review_overview_auto (not= head base.sha) (not (. H.generating head)))
                (generate root head base)))))

(fn open [regenerate]
    "Open the overview for HEAD, writing it first if there is none."
    (when (review.items)
        (let [base (review.base)
              root base.root
              head (git [:rev-parse :HEAD] root)
              dir (overview_dir root)
              json (.. dir "/" head ".json")]
            (when regenerate (os.remove json))
            (if (= 1 (vim.fn.filereadable json))
                (do (apply root head)
                    (when (not= (vim.api.nvim_buf_get_name 0) (.. dir "/" head ".md"))
                        (vim.cmd.edit (vim.fn.fnameescape (.. dir "/" head ".md")))))
                (do (set H.open_when_ready head)
                    (if (. H.generating head)
                        (vim.notify "Review: still writing the overview; it opens when it's ready")
                        (generate root head base)))))))

;; ----------------------------------------------------------------------------
;; The overview buffer

(fn setup_buffer [buf_id]
    (let [base (review.base)
          root (or (?. base :root) (?. H.current :root))]
        (when root
            (tset vim.bo buf_id :path (.. (root:gsub "[, ]" "\\%0") ",")))
        (tset vim.bo buf_id :modifiable false)
        (tset vim.bo buf_id :readonly true)
        (vim.keymap.set :n :<CR>
            (fn []
                ;; The first changed file named on the line, wherever the cursor is.
                (let [changed {}]
                    (each [_ item (ipairs (or (review.items) []))] (tset changed item.rel true))
                    (let [rel (accumulate [found nil word (string.gmatch (vim.api.nvim_get_current_line) "%S+")
                                           &until found]
                                  (when (. changed word) word))]
                        (if rel (review.open_file rel) (vim.cmd "normal! gf")))))
            {:buffer buf_id :desc "Open the file at its first change"})))

(local augroup (vim.api.nvim_create_augroup :review_overview {:clear true}))

(vim.api.nvim_create_autocmd :User {
    :group augroup
    :pattern :ReviewStart
    :callback #(vim.schedule on_review_start)})

(vim.api.nvim_create_autocmd :BufReadPost {
    :group augroup
    :pattern "*/review-overview/*.md"
    :callback #(setup_buffer $.buf)})

;; A new HEAD (a pull, a new commit) gets its own overview.
(vim.api.nvim_create_autocmd [:FocusGained :TermLeave :ShellCmdPost] {
    :group augroup
    :callback #(let [base (review.base)]
                   (when (and base H.current (= H.current.root base.root)
                              (not= H.current.head (git [:rev-parse :HEAD] base.root)))
                       (on_review_start)))})

(vim.api.nvim_create_user_command :ReviewOverview (fn [opts] (open opts.bang))
    {:bang true :desc "Open the review overview (! writes it again)"})

{
    :open #(open false)
    :regenerate #(open true)
    ;; For the review bar.
    :writing #(not= nil (next H.generating))
}
