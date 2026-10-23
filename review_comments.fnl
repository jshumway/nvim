;; ----------------------------------------------------------------------------
;; Review comments
;;
;; Comment on a PR by writing in the code. While reviewing, add comment lines
;; to a file in its own comment syntax, or edit its code; base version notes
;; work too, for comments on removed code. `:ReviewSend` collects these into
;; an editable list, and writing that list adds them to your pending review
;; on GitHub. Nothing is posted until you submit the review there.
;;
;; - New comment lines become a comment on the line below them (the line
;;   above, at the end of a file).
;; - Edited, added or removed code becomes a suggested change for the lines
;;   it replaces, with any new comment lines right above it as its text.
;;   Comment lines after the first line of code are part of the suggestion.
;; - New comment lines in a base version notes buffer become a comment on the
;;   base side. Other edits in notes stay private.
;;
;; GitHub only takes line comments inside the PR's diff, so a comment outside
;; it goes on the file instead, and one on a file the PR doesn't change goes
;; in the review's summary. GitHub can't add a summary to a pending review
;; that has none, so then it's copied for you to paste in. After sending, your edits are stashed (see `git
;; stash list`) and sent notes move to the notes dir's `sent/`, so the files
;; are back at the PR's head.
;;
;; `export` writes the same comments as a markdown list, for an agent to work
;; through (`fleet feedback` uses it).

(local review (require :review_mode))
(local pr_module (require :pr))

(local text_diff (or (and vim.text vim.text.diff) vim.diff))
(local SENT_DIR (.. review.state_dir "/sent"))

(local H {
    ;; Preview buffers: {buf_id ctx}.
    :previews {}
})

;; ----------------------------------------------------------------------------
;; Helpers

(fn run [cmd cwd]
    "Run `cmd`. Returns stdout, or nil and the error output."
    (let [res (: (vim.system cmd {:cwd cwd :text true}) :wait)]
        (if (= res.code 0)
            (values res.stdout nil)
            (values nil (vim.trim (.. (or res.stderr "") (or res.stdout "")))))))

(fn git [args cwd]
    (let [out (run (vim.list_extend [:git] args) cwd)]
        (when out (vim.trim out))))

(fn split_lines [text]
    (let [(text) (string.gsub (or text "") "\n$" "")]
        (if (= text "") [] (vim.split text "\n" {:plain true}))))

(fn decode [text]
    (let [(ok value) (pcall vim.json.decode (or text "") {:luanil {:object true :array true}})]
        (when (and ok (= (type value) :table)) value)))

;; ----------------------------------------------------------------------------
;; Comment syntax

(fn comment_syntax [rel]
    "The file type's comment leader and trailer, like {:left \"#\" :right \"\"}."
    (let [ft (vim.filetype.match {:filename rel})
          cs (and ft (vim.filetype.get_option ft :commentstring))
          (left right) (when (and (= (type cs) :string) (cs:find "%%s"))
                           (cs:match "^(.-)%%s(.-)$"))]
        (when (and left (not= (vim.trim left) ""))
            {:left (vim.trim left) :right (vim.trim (or right ""))})))

(fn comment_text [syntax line]
    "The text of `line` if it's a comment, else nil."
    (when syntax
        (let [line (vim.trim line)]
            (when (vim.startswith line syntax.left)
                (var text (pick-values 1 (: (line:sub (+ (length syntax.left) 1)) :gsub "^ " "")))
                (when (and (not= syntax.right "") (vim.endswith text syntax.right))
                    (set text (vim.trim (text:sub 1 (- (length text) (length syntax.right))))))
                text))))

(fn leading_comments [syntax lines]
    "How many of the first `lines` are a comment block: comment lines, with
    blank lines between them."
    (var n 0)
    (var stop false)
    (each [i line (ipairs lines) &until stop]
        (if (comment_text syntax line) (set n i)
            (= (vim.trim line) "") nil
            (set stop true)))
    n)

(fn comment_body [syntax lines n]
    (vim.trim (table.concat (fcollect [i 1 n] (or (comment_text syntax (. lines i)) "")) "\n")))

(fn blank? [lines]
    (accumulate [all true _ line (ipairs lines)] (and all (= (vim.trim line) ""))))

;; ----------------------------------------------------------------------------
;; Collecting comments

(fn parse_diff [text]
    "Files and hunks of a `git diff`, as [{:path :old_path :hunks [{:old_start
    :old_count :new_start :new_count :minus :plus}]}]."
    (let [files []]
        (var file nil)
        (var hunk nil)
        (each [_ line (ipairs (vim.split text "\n" {:plain true}))]
            (if (vim.startswith line "diff --git ")
                (do (set file {:hunks []}) (set hunk nil) (table.insert files file))
                (and file (= hunk nil) (vim.startswith line "--- "))
                (set file.old_path (let [p (line:sub 5)] (when (not= p "/dev/null") (pick-values 1 (p:gsub "^a/" "")))))
                (and file (= hunk nil) (vim.startswith line "+++ "))
                (set file.path (let [p (line:sub 5)] (when (not= p "/dev/null") (pick-values 1 (p:gsub "^b/" "")))))
                (and file (vim.startswith line "@@ "))
                (let [(a b c d) (line:match "^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")]
                    (set hunk {:old_start (tonumber a) :old_count (if (= b "") 1 (tonumber b))
                               :new_start (tonumber c) :new_count (if (= d "") 1 (tonumber d))
                               :minus [] :plus []})
                    (table.insert file.hunks hunk))
                (and hunk (vim.startswith line "-")) (table.insert hunk.minus (line:sub 2))
                (and hunk (vim.startswith line "+")) (table.insert hunk.plus (line:sub 2))))
        files))

(fn suggestion_body [text lines]
    (.. (if (not= text "") (.. text "\n\n") "")
        "```suggestion\n" (table.concat lines "\n") (if (> (length lines) 0) "\n" "") "```"))

(fn hunk_item [syntax head h]
    "The comment or suggestion one hunk of edits makes, if any. `head` is the
    file's lines at HEAD."
    (let [a h.old_start
          b h.old_count
          plus h.plus
          ;; In a replacement, as many leading comment lines as it had are
          ;; edits of existing comments; the rest are new.
          k (if (= b 0)
                (leading_comments syntax plus)
                (math.max 0 (- (leading_comments syntax plus) (leading_comments syntax h.minus))))
          text (comment_body syntax plus k)
          code (vim.list_slice plus (+ k 1))
          last (length head)]
        (if (and (= b 0) (blank? code))
            (when (> k 0)
                {:kind :comment :side :RIGHT :line (if (< a last) (+ a 1) (math.max a 1)) : text :body text})
            (let [(start line suggestion)
                  (if (> b 0) (values a (+ a b -1) code)
                      (> a 0) (values a a (vim.list_extend [(. head a)] code))
                      (values 1 1 (vim.list_extend (vim.deepcopy code) [(. head 1)])))]
                {:kind :suggestion :side :RIGHT : line :start_line (when (< start line) start)
                 : text : suggestion :body (suggestion_body text suggestion)}))))

(fn worktree_items [root]
    "Comments and suggestions from uncommitted edits to files in HEAD."
    (let [diff (or (run [:git :-c :core.quotePath=false :diff :HEAD :-U0 :--no-color :--no-ext-diff] root) "")
          items []]
        (each [_ file (ipairs (parse_diff diff))]
            ;; New and deleted files can't take comments.
            (when (and file.path file.old_path)
                (let [syntax (comment_syntax file.path)
                      head (split_lines (run [:git :show (.. "HEAD:" file.path)] root))]
                    (each [_ h (ipairs file.hunks)]
                        (let [item (hunk_item syntax head h)]
                            (when item
                                (set item.path file.path)
                                (set item.source {:path file.path})
                                (table.insert items item)))))))
        items))

(fn notes_items [root sha]
    "Comments from new comment lines in base version notes taken on `sha`."
    (let [dir (.. review.notes_dir "/" sha)
          items []]
        (when (= 1 (vim.fn.isdirectory dir))
            (each [rel kind (vim.fs.dir dir {:depth 100})]
                (let [base_text (and (= kind :file) (run [:git :show (.. sha ":" rel)] root))]
                    (when base_text
                        (let [notes (vim.fn.readfile (.. dir "/" rel))
                              syntax (comment_syntax rel)
                              last (length (split_lines base_text))]
                            (each [_ [sa ca sb cb] (ipairs (text_diff base_text (.. (table.concat notes "\n") "\n")
                                                                      {:result_type :indices}))]
                                (when (= ca 0)
                                    (let [added (vim.list_slice notes sb (+ sb cb -1))
                                          k (leading_comments syntax added)
                                          text (comment_body syntax added k)]
                                        (when (> k 0)
                                            (table.insert items
                                                {:kind :comment :side :LEFT :path rel
                                                 :line (if (< sa last) (+ sa 1) (math.max sa 1))
                                                 : text :body text
                                                 :source {:notes (.. dir "/" rel) :sha sha : rel}}))))))))))
        items))

(fn diff_ranges [root base_sha]
    "The lines of the PR's diff that GitHub takes comments on, as
    {path {:RIGHT [[from to]] :LEFT [[from to]]}}."
    (let [out (or (run [:git :-c :core.quotePath=false :diff :--no-color :--no-ext-diff :-U3 base_sha :HEAD] root) "")
          ranges {}]
        (each [_ file (ipairs (parse_diff out))]
            (let [r {:RIGHT [] :LEFT []}]
                (each [_ h (ipairs file.hunks)]
                    (table.insert r.RIGHT [h.new_start (+ h.new_start h.new_count -1)])
                    (table.insert r.LEFT [h.old_start (+ h.old_start h.old_count -1)]))
                (tset ranges (or file.path file.old_path) r)))
        ranges))

(fn place [item ranges]
    "Where GitHub takes the item: :line, :file, or the review :summary."
    (let [file (. ranges item.path)
          from (or item.start_line item.line)]
        (set item.place
            (if (= file nil) :summary
                (accumulate [ok false _ [a b] (ipairs (. file item.side)) &until ok]
                    (and (<= a from) (<= item.line b)))
                :line
                :file))))

(fn location [item]
    (.. item.path ":" (if item.start_line (.. item.start_line "-" item.line) item.line)))

(fn item_key [item]
    (vim.fn.sha256 (table.concat [item.path item.side item.line (or item.start_line "") item.body] "\1")))

;; ----------------------------------------------------------------------------
;; GitHub

(local PR_QUERY "query($owner:String!, $name:String!, $number:Int!) {
  viewer { login }
  repository(owner:$owner, name:$name) { pullRequest(number:$number) {
    id headRefOid
    reviews(states:PENDING, first:20) { nodes { id body viewerDidAuthor } } } } }")

(local ADD_REVIEW "mutation($pr:ID!, $commit:GitObjectID, $body:String) {
  addPullRequestReview(input:{pullRequestId:$pr, commitOID:$commit, body:$body}) { pullRequestReview { id body } } }")

(local ADD_THREAD "mutation($review:ID!, $path:String!, $body:String!, $line:Int, $side:DiffSide,
    $startLine:Int, $startSide:DiffSide, $subjectType:PullRequestReviewThreadSubjectType) {
  addPullRequestReviewThread(input:{pullRequestReviewId:$review, path:$path, body:$body, line:$line,
    side:$side, startLine:$startLine, startSide:$startSide, subjectType:$subjectType}) { thread { id } } }")

(local UPDATE_REVIEW "mutation($review:ID!, $body:String!) {
  updatePullRequestReview(input:{pullRequestReviewId:$review, body:$body}) { pullRequestReview { id } } }")

(fn graphql [host query vars on_done]
    "Call GitHub's GraphQL API; `on_done` gets the data, or nil and an error."
    (let [args [:gh :api :graphql :--hostname host :-f (.. "query=" query)]]
        (each [k v (pairs vars)]
            (table.insert args (if (= (type v) :number) :-F :-f))
            (table.insert args (.. k "=" (tostring v))))
        (vim.system args {:text true}
            (vim.schedule_wrap (fn [res]
                (let [data (decode res.stdout)
                      err (?. data :errors 1 :message)]
                    (if (and (= res.code 0) data (= err nil))
                        (on_done data.data nil)
                        (on_done nil (or err (vim.trim (.. (or res.stderr "") (or res.stdout ""))))))))))))

(fn thread_vars [review_id item]
    (if (= item.place :line)
        {:review review_id :path item.path :body item.body :line item.line :side item.side
         :startLine item.start_line :startSide (when item.start_line item.side)}
        ;; Outside the diff: on the file, saying which lines it means.
        {:review review_id :path item.path :subjectType :FILE
         :body (.. (if item.start_line (.. "Lines " item.start_line "-" item.line) (.. "Line " item.line))
                   (if (= item.side :LEFT) " (base side)" "") ":\n\n"
                   (pick-values 1 (item.body:gsub "```suggestion\n" "```\n")))}))

;; ----------------------------------------------------------------------------
;; Sent record, so a retry after a failure doesn't post twice

(fn sent_file [url]
    (.. SENT_DIR "/" (: (vim.fn.sha256 url) :sub 1 16) ".json"))

(fn read_sent [url]
    (let [path (sent_file url)
          data (when (= 1 (vim.fn.filereadable path)) (decode (table.concat (vim.fn.readfile path) "\n")))
          keys {}]
        (each [_ key (ipairs (or (?. data :keys) []))] (tset keys key true))
        keys))

(fn write_sent [url keys]
    (vim.fn.mkdir SENT_DIR :p)
    (vim.fn.writefile [(vim.json.encode {:keys (vim.tbl_keys keys)})] (sent_file url)))

;; ----------------------------------------------------------------------------
;; After sending

(fn reload_buffers [paths]
    "Reload unmodified buffers showing `paths` (absolute)."
    (let [wanted {}]
        (each [_ path (ipairs paths)] (tset wanted path true))
        (each [_ buf_id (ipairs (vim.api.nvim_list_bufs))]
            (let [name (vim.api.nvim_buf_get_name buf_id)
                  path (if (name:find "^review://") name (vim.fn.fnamemodify name ":p"))]
                (when (and (vim.api.nvim_buf_is_loaded buf_id) (. wanted path) (not (. vim.bo buf_id :modified)))
                    (vim.api.nvim_buf_call buf_id #(vim.cmd "silent edit!")))))))

(fn clean_up [ctx]
    "Stash the edits the comments came from and archive the notes, so the
    files are back at the PR's head."
    (let [paths {}
          notes {}
          reload []]
        (each [_ item (ipairs ctx.all)]
            (if item.source.path (tset paths item.source.path true)
                item.source.notes (tset notes item.source.notes item.source)))
        (let [rels (vim.tbl_keys paths)]
            (when (> (length rels) 0)
                (let [(_ err) (run (vim.list_extend [:git :stash :push :-m (.. "review comments sent to PR #" ctx.number) :--]
                                                    rels)
                                   ctx.root)]
                    (if err
                        (vim.notify (.. "Review: couldn't stash the edits: " err) vim.log.levels.WARN)
                        (each [_ rel (ipairs rels)] (table.insert reload (.. ctx.root "/" rel)))))))
        (each [file source (pairs notes)]
            (let [dest (.. review.notes_dir "/sent/" source.sha "/" source.rel)]
                (vim.fn.mkdir (vim.fs.dirname dest) :p)
                (os.rename file dest)))
        (each [_ buf_id (ipairs (vim.api.nvim_list_bufs))]
            (let [name (vim.api.nvim_buf_get_name buf_id)
                  (short rel) (name:match "^review://.-@(%x+)/(.+)$")]
                (when (and short (accumulate [hit false _ source (pairs notes) &until hit]
                                     (and (= source.rel rel) (vim.startswith source.sha short))))
                    (table.insert reload name))))
        (reload_buffers reload)))

;; ----------------------------------------------------------------------------
;; Preview and sending

(fn render_preview [buf_id ctx]
    (let [lines [(.. "# PR #" ctx.number ": " ctx.title)
                 (.. "# " ctx.url)
                 "# These go into your pending review on GitHub; nothing is posted until you submit it there."
                 "# Delete an item to leave it out, or edit its text. :w adds them, :q! cancels."]]
        (when ctx.own (table.insert lines "# This is your own PR."))
        (each [_ item (ipairs ctx.items)]
            (table.insert lines "")
            (table.insert lines (.. "## [" item.id "] " (location item)
                                    (if (= item.kind :suggestion) " suggestion" "")
                                    (if (= item.side :LEFT) " (base side)" "")
                                    (if (= item.place :file) " (outside the diff: goes on the file)"
                                        (= item.place :summary) " (file not in the PR: goes in the review summary)"
                                        "")))
            (vim.list_extend lines (vim.split item.body "\n" {:plain true})))
        (vim.api.nvim_buf_set_lines buf_id 0 -1 false lines)
        (tset vim.bo buf_id :modified false)))

(fn parse_preview [buf_id ctx]
    "The items left in the preview, with their text as edited."
    (let [by_id {}
          chosen []]
        (each [_ item (ipairs ctx.items)] (tset by_id item.id item))
        (var current nil)
        (each [_ line (ipairs (vim.api.nvim_buf_get_lines buf_id 0 -1 false))]
            (let [id (line:match "^## %[(%d+)%]")]
                (if id
                    (do (set current {:item (. by_id (tonumber id)) :lines []})
                        (when current.item (table.insert chosen current)))
                    current
                    (table.insert current.lines line))))
        (icollect [_ c (ipairs chosen)]
            (let [body (vim.trim (table.concat c.lines "\n"))]
                (when (not= body "") (vim.tbl_extend :force c.item {: body}))))))

(fn send_preview [buf_id]
    (let [ctx (. H.previews buf_id)
          items (or (and ctx (parse_preview buf_id ctx)) [])
          sent (and ctx (read_sent ctx.url))]
        (var remaining (vim.deepcopy items))
        (fn fail [err]
            (vim.notify (string.format "Review: stopped after %d of %d: %s"
                                       (- (length items) (length remaining)) (length items) err)
                        vim.log.levels.ERROR)
            ;; Show what is left, so writing again sends only that.
            (set ctx.items remaining)
            (render_preview buf_id ctx))
        (fn summary_text [existing]
            (let [lines (icollect [_ item (ipairs remaining)]
                            (when (= item.place :summary) (.. "`" (location item) "`: " item.body)))]
                (when (> (length lines) 0)
                    (.. (if (not= (or existing "") "") (.. existing "\n\n") "") (table.concat lines "\n\n")))))
        (fn mark_summary_sent []
            (each [_ item (ipairs remaining)]
                (when (= item.place :summary) (tset sent item.key true)))
            (write_sent ctx.url sent)
            (set remaining (icollect [_ item (ipairs remaining)] (when (not= item.place :summary) item))))
        (fn finish [review_id]
            (write_sent ctx.url {})
            (clean_up ctx)
            (review.record_reviewed)
            (vim.api.nvim_buf_delete buf_id {:force true})
            (vim.notify (string.format "Review: added %d to your pending review on PR #%d. Submit it in GitHub."
                                       (length items) ctx.number))
            (pr_module.open_url (.. ctx.url "/files")))
        (fn summary [review_id existing]
            (let [text (summary_text existing)]
                (if (= text nil)
                    (finish review_id)
                    (= (or existing "") "")
                    (do (pr_module.copy text)
                        (vim.notify (.. "Review: GitHub can't add a summary to a pending review that has none, "
                                        "so it's copied: paste it into the summary when you submit"))
                        (mark_summary_sent)
                        (finish review_id))
                    (graphql ctx.host UPDATE_REVIEW {:review review_id :body text}
                        (fn [_ err]
                            (if err (fail err)
                                (do (mark_summary_sent)
                                    (finish review_id))))))))
        (fn threads [review_id existing]
            ;; One at a time, recording each, until only summary items are left.
            (let [item (accumulate [found nil _ item (ipairs remaining) &until found]
                           (when (not= item.place :summary) item))]
                (if (= item nil)
                    (summary review_id existing)
                    (graphql ctx.host ADD_THREAD (thread_vars review_id item)
                        (fn [_ err]
                            (if err (fail (.. (location item) ": " err))
                                (do (tset sent item.key true)
                                    (write_sent ctx.url sent)
                                    (set remaining (icollect [_ other (ipairs remaining)]
                                                       (when (not= other.id item.id) other)))
                                    (threads review_id existing))))))))
        (if (or (= ctx nil) (= (length items) 0))
            (vim.notify "Review: nothing to send" vim.log.levels.INFO)
            (graphql ctx.host PR_QUERY {:owner ctx.owner :name ctx.name :number ctx.number}
                (fn [data err]
                    (let [pull (?. data :repository :pullRequest)
                          pending (accumulate [found nil _ r (ipairs (or (?. pull :reviews :nodes) [])) &until found]
                                      (when r.viewerDidAuthor r))]
                        (if err (fail err)
                            (not= pull.headRefOid ctx.head)
                            (fail "the PR has new commits since; pull them and run :ReviewSend again")
                            pending (threads pending.id pending.body)
                            ;; A new review can start with the summary.
                            (let [text (summary_text "")]
                                (graphql ctx.host ADD_REVIEW {:pr pull.id :commit ctx.head :body text}
                                    (fn [created err]
                                        (if err (fail err)
                                            (do (when text (mark_summary_sent))
                                                (threads (?. created :addPullRequestReview :pullRequestReview :id)
                                                         (or text ""))))))))))))))

(fn collect_items [root pr_base]
    (let [items (worktree_items root)]
        (when pr_base (vim.list_extend items (notes_items root pr_base)))
        (each [_ item (ipairs items)] (set item.key (item_key item)))
        items))

(fn send []
    "Collect the comments and suggestions and open them for review before
    they go into the pending review."
    (vim.cmd "silent! wall")
    (let [base (review.base)
          root (or (?. base :root) (git [:rev-parse :--show-toplevel] (vim.fn.getcwd)) (vim.fn.getcwd))
          (out err) (run [:gh :pr :view :--json "number,url,title,headRefOid,baseRefName,author"] root)
          pr (decode out)
          head (and pr (git [:rev-parse :HEAD] root))]
        (if (= pr nil)
            (vim.notify (.. "Review: can't find the PR for this branch: " (or err "")) vim.log.levels.WARN)
            (not= head pr.headRefOid)
            (vim.notify (string.format (.. "Review: your checkout is at %s but the PR is at %s, so comments "
                                           "would land on the wrong lines. Pull or push first.")
                                       (head:sub 1 10) (pr.headRefOid:sub 1 10))
                        vim.log.levels.WARN)
            (let [(host owner name) (pr.url:match "^https?://([^/]+)/([^/]+)/([^/]+)/pull/%d+")
                  ;; The same base review mode finds, so base version notes
                  ;; are found too.
                  base_rev (review.branch_rev root pr.baseRefName)
                  pr_base (and base_rev (git [:merge-base :HEAD base_rev] root))
                  all (collect_items root pr_base)
                  sent (read_sent pr.url)
                  items (icollect [_ item (ipairs all)] (when (not (. sent item.key)) item))
                  ranges (if pr_base (diff_ranges root pr_base) {})
                  login (vim.trim (or (run [:gh :api :user :--hostname host :--jq :.login] root) ""))]
                (each [i item (ipairs items)]
                    (set item.id i)
                    (place item ranges))
                (when (< (length items) (length all))
                    (vim.notify (string.format "Review: skipping %d already sent" (- (length all) (length items)))))
                (if (= (length items) 0)
                    (vim.notify "Review: no comments to send. Add comment lines or edit code, then :ReviewSend."
                                vim.log.levels.INFO)
                    (do
                        (vim.cmd "botright new")
                        (let [buf_id (vim.api.nvim_get_current_buf)
                              ctx {: root : host : owner : name :number pr.number :url pr.url :title pr.title
                                   :head head : items : all :own (= (?. pr :author :login) login)}]
                            (vim.api.nvim_buf_set_name buf_id (string.format "review-send://%s/%s/%d" owner name pr.number))
                            (tset vim.bo buf_id :buftype :acwrite)
                            (tset vim.bo buf_id :bufhidden :wipe)
                            (tset vim.bo buf_id :swapfile false)
                            (tset vim.bo buf_id :filetype :markdown)
                            (tset H.previews buf_id ctx)
                            (render_preview buf_id ctx)
                            (vim.api.nvim_create_autocmd :BufWriteCmd {
                                :buffer buf_id
                                :callback #(send_preview buf_id)})
                            (vim.api.nvim_create_autocmd :BufWipeout {
                                :buffer buf_id
                                :callback #(tset H.previews buf_id nil)}))))))))

;; ----------------------------------------------------------------------------
;; For agents

(fn export [path]
    "Write the comments in the working tree to `path` as markdown, for an agent
    to work through. Returns how many there are."
    (let [root (git [:rev-parse :--show-toplevel] (vim.fn.getcwd))
          items (if root (worktree_items root) [])]
        (when (> (length items) 0)
            (let [lines ["# Review comments" ""
                         "Comments and suggested changes Jared wrote in the files while reviewing. Lines are numbered as in HEAD, before his edits."]]
                (each [_ item (ipairs items)]
                    (vim.list_extend lines ["" (.. "## " (location item))])
                    (when (not= item.text "") (vim.list_extend lines (vim.split item.text "\n" {:plain true})))
                    (when (= item.kind :suggestion)
                        (vim.list_extend lines
                            ["" (.. "Suggested: replace " (if item.start_line (.. "lines " item.start_line "-" item.line)
                                                             (.. "line " item.line))
                                    (if (= (length item.suggestion) 0) " with nothing." " with:"))])
                        (when (> (length item.suggestion) 0)
                            (vim.list_extend lines ["```"])
                            (vim.list_extend lines item.suggestion)
                            (vim.list_extend lines ["```"]))))
                (vim.fn.writefile lines path)))
        (length items)))

(vim.api.nvim_create_user_command :ReviewSend #(send)
    {:desc "Collect review comments and add them to your pending review on GitHub"})

{
    : send
    : export
    ;; For tests.
    : hunk_item
    : comment_syntax
}
