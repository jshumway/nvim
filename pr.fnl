;; ----------------------------------------------------------------------------
;; Pull requests
;;
;; Work with the GitHub PR for the current branch through the `gh` CLI:
;; - edit its description in a buffer that posts to GitHub when written
;; - open it in the browser (or copy its URL where there is no browser)
;;
;; The description buffer is named `pr://<PR URL without https://>`. `:w`
;; posts the description. `:x` and `:wq` post it and then switch back to the
;; previous buffer, instead of closing the window. If the description changed
;; on GitHub since it was loaded, the write is refused: `:w!` overwrites it,
;; and `:e!` reloads it (dropping your edits).

(local H {
    ;; Description as last loaded from or posted to GitHub, keyed by buffer.
    :base_bodies {}
    ;; A PR just looked up, so its description buffer can be filled without
    ;; fetching it again. Keyed by URL.
    :prefetched {}
})

(local augroup (vim.api.nvim_create_augroup :user_pr {:clear true}))
(local PR_FIELDS "number,title,url,body")

;; ----------------------------------------------------------------------------
;; Helpers

(fn normalize [body]
    "GitHub keeps CRLF from web edits and has no final newline."
    (let [(text) (string.gsub (or body "") "\r\n" "\n")
          (text) (string.gsub text "\n+$" "")]
        text))

(fn gh_sync [args opts]
    "Run gh. Returns true and stdout, or false and the error output."
    (let [res (: (vim.system (vim.list_extend [:gh] args) (vim.tbl_extend :force {:text true} (or opts {}))) :wait)]
        (if (= res.code 0)
            (values true res.stdout)
            (values false (vim.trim (.. res.stderr res.stdout))))))

(fn gh_async [args cwd on_done]
    "Run gh, then call `on_done` with the same values as `gh_sync`."
    (vim.system (vim.list_extend [:gh] args) {:cwd cwd :text true}
        (vim.schedule_wrap (fn [res]
            (if (= res.code 0)
                (on_done true res.stdout)
                (on_done false (vim.trim (.. res.stderr res.stdout))))))))

(fn decode_pr [ok out]
    (if (not ok)
        (do (vim.notify (.. "PR: " out) vim.log.levels.WARN) nil)
        (let [(decoded pr) (pcall vim.json.decode out)]
            (if decoded
                pr
                (do (vim.notify "PR: couldn't read the gh output" vim.log.levels.ERROR) nil)))))

(fn buffer_pr_url [buf_id]
    (let [path (: (vim.api.nvim_buf_get_name buf_id) :match "^pr://(.+)$")]
        (when path (.. "https://" path))))

(fn description_name [url]
    (.. "pr://" (url:gsub "^https?://" "")))

(fn repo_dir []
    "Directory for gh to find the repo and branch in."
    (let [name (or vim.b.review_file (vim.api.nvim_buf_get_name 0))
          dir (vim.fs.dirname name)]
        (if (and (not= name "") (not (name:find "^%a+://")) (= 1 (vim.fn.isdirectory dir)))
            dir
            (vim.fn.getcwd))))

(fn with_current_pr [on_pr]
    "Look up the PR for this description buffer, or for the current branch."
    (let [url (buffer_pr_url 0)
          args [:pr :view]]
        (when url (table.insert args url))
        (vim.list_extend args [:--json PR_FIELDS])
        (gh_async args (repo_dir) (fn [ok out]
            (let [pr (decode_pr ok out)]
                (when pr (on_pr pr)))))))

;; ----------------------------------------------------------------------------
;; Description buffer

(fn buf_body [buf_id]
    (normalize (table.concat (vim.api.nvim_buf_get_lines buf_id 0 -1 false) "\n")))

(fn mark_posted [buf_id body]
    (tset H.base_bodies buf_id body)
    (tset vim.bo buf_id :modified false))

(fn write_description [buf_id force]
    (let [url (buffer_pr_url buf_id)
          body (buf_body buf_id)
          current (decode_pr (gh_sync [:pr :view url :--json :body]))]
        (if (= current nil)
            nil
            (= (normalize current.body) body)
            (do (mark_posted buf_id body) (vim.notify "PR description is unchanged"))
            (and (not= (normalize current.body) (. H.base_bodies buf_id)) (not force))
            (vim.notify (.. "PR: the description changed on GitHub since it was loaded. "
                            "Use :w! to overwrite it, or :e! to reload it (drops your edits).")
                        vim.log.levels.ERROR)
            (let [(ok out) (gh_sync [:pr :edit url :--body-file :-] {:stdin body})]
                (if ok
                    (do (mark_posted buf_id body) (vim.notify "PR description posted"))
                    (vim.notify (.. "PR: " out) vim.log.levels.ERROR))))))

(fn setup_description_buffer [buf_id]
    ;; Make `:x` and `:wq` post, then go back to the previous buffer, so they
    ;; don't close the window.
    (vim.api.nvim_buf_create_user_command buf_id :PRWriteAndLeave
        (fn [opts]
            (vim.cmd (if opts.bang "write!" "write"))
            (let [alt (vim.fn.bufnr "#")]
                (when (and (not (. vim.bo buf_id :modified))
                           (> alt 0) (not= alt buf_id) (= 1 (vim.fn.buflisted alt)))
                    (vim.cmd.buffer alt))))
        {:bang true :desc "Post the PR description and leave"})
    (each [_ cmd (ipairs [:x :xit :wq])]
        (vim.cmd (string.format
            "cnoreabbrev <buffer> <expr> %s getcmdtype() ==# ':' && getcmdline() ==# '%s' ? 'PRWriteAndLeave' : '%s'"
            cmd cmd cmd))))

(fn read_description [buf_id]
    (let [url (buffer_pr_url buf_id)
          pr (and url (or (. H.prefetched url)
                          (decode_pr (gh_sync [:pr :view url :--json PR_FIELDS]))))]
        (when url (tset H.prefetched url nil))
        (when pr
            (let [body (normalize pr.body)
                  undolevels (. vim.bo buf_id :undolevels)]
                ;; Loading the description shouldn't be undoable.
                (tset vim.bo buf_id :undolevels -1)
                (vim.api.nvim_buf_set_lines buf_id 0 -1 false (vim.split body "\n"))
                (tset vim.bo buf_id :undolevels undolevels)
                ;; Not a real file, so writes go through BufWriteCmd.
                (tset vim.bo buf_id :buftype :acwrite)
                (tset vim.bo buf_id :swapfile false)
                (tset vim.bo buf_id :filetype :markdown)
                (mark_posted buf_id body)
                (setup_description_buffer buf_id)
                (vim.notify (string.format "PR #%d: %s" pr.number pr.title))))))

(vim.api.nvim_create_autocmd :BufReadCmd {
    :group augroup
    :pattern "pr://*"
    :callback #(read_description $.buf)})

(vim.api.nvim_create_autocmd :BufWriteCmd {
    :group augroup
    :pattern "pr://*"
    :callback #(write_description $.buf (= vim.v.cmdbang 1))})

(vim.api.nvim_create_autocmd :BufWipeout {
    :group augroup
    :pattern "pr://*"
    :callback #(tset H.base_bodies $.buf nil)})

;; ----------------------------------------------------------------------------
;; Public functions

(fn edit_description []
    (with_current_pr (fn [pr]
        (tset H.prefetched pr.url pr)
        (vim.cmd.edit (vim.fn.fnameescape (description_name pr.url)))
        ;; Only used if the buffer wasn't already open.
        (tset H.prefetched pr.url nil))))

(fn copy [text]
    "Put `text` on the clipboard, through OSC 52 where there is no clipboard
    (a devbox), which reaches the laptop's clipboard through the terminal."
    (if (= 1 (vim.fn.has :clipboard))
        (vim.fn.setreg "+" text)
        (((. (require :vim.ui.clipboard.osc52) :copy) "+") (vim.split text "\n" {:plain true}))))

(fn open_url [url]
    "Open `url` in the browser. Where there is none (a devbox), copy it instead:
    OSC 52 reaches the laptop's clipboard through the terminal."
    (let [(cmd) (vim.ui.open url)]
        (when (= cmd nil)
            (copy url)
            (vim.notify (.. "No browser here; copied " url)))))

(fn open_in_browser []
    (let [url (buffer_pr_url 0)]
        (if url
            (open_url url)
            (with_current_pr #(open_url $.url)))))

{
    : edit_description
    : open_in_browser
    : open_url
    : copy
}
