;; ----------------------------------------------------------------------------
;; Review mode
;;
;; Diff buffers against a fixed git base instead of the index, so mini.diff
;; marks everything the branch changed. By default the base is where the
;; branch forked from the default branch, which matches what a PR shows.
;; Start from the shell with `nvim +Review` or `nvim "+Review main"`.
;;
;; While review mode is on:
;; - every buffer in the repo uses the base as its mini.diff reference text
;; - the changed files picker lists files changed since the base, including
;;   uncommitted and untracked ones
;; - next/prev file steps through that same list
;; - the base version toggle swaps a file with an editable copy of it at the
;;   base, for taking notes (see "Base version notes" below)
;;
;; Review mode is remembered per repo and branch: opening a file on a branch
;; brings back its review base and the notes buffers that were open. The
;; overlay settings are remembered everywhere.
;;
;; NOTE: listing uncommitted changes needs `git status`, which can be slow in
;; very large repos, so it runs in the background and the picker updates when
;; it finishes. Everything else avoids reading the index.

(local mini_diff (require :mini.diff))
(local mini_pick (require :mini.pick))

(local NUL (string.char 0))
(local text_diff (or (and vim.text vim.text.diff) vim.diff))

(local H {
    ;; {:root :ref :sha} while review mode is on.
    :base nil
    ;; mini.diff's source from before review mode replaced it.
    :saved_source nil
    ;; Uncommitted changes from the last `git status`, keyed by path from the
    ;; repo root.
    :worktree_changes {}
    ;; Reference text the review source set for each buffer, as mini.diff
    ;; stores it.
    :ref_texts {}
    ;; Notes buffers: {buf_id {:base_text :notes_path}}.
    :notes {}
    ;; Repo root of each notes buffer, keyed by buffer name. Known before the
    ;; buffer loads when it was reopened from saved state.
    :notes_roots {}
    ;; Repo roots whose saved state was already checked.
    :restored {}
    ;; Set while exiting, when buffers going away shouldn't change saved state.
    :exiting false
    ;; Whether to show the mini.diff overlay, in and out of review mode.
    :overlay {:review true :normal false}
})

(local NOTES_DIR (.. (vim.fn.stdpath :data) "/review-notes"))
(local notes_ns (vim.api.nvim_create_namespace :review_notes))
(local augroup (vim.api.nvim_create_augroup :review_mode {:clear true}))

;; ----------------------------------------------------------------------------
;; Git helpers

(fn git [args cwd]
    "Run git synchronously. Returns trimmed stdout, or nil on failure."
    (let [res (: (vim.system (vim.list_extend [:git] args) {:cwd cwd :text true}) :wait)]
        (when (= res.code 0)
            (vim.trim res.stdout))))

(fn git_lines [args cwd]
    (let [out (git args cwd)]
        (if (or (= out nil) (= out "")) [] (vim.split out "\n"))))

(fn realpath [path]
    ;; Deleted files no longer exist, so resolve their directory instead.
    (or (vim.uv.fs_realpath path)
        (let [dir (vim.uv.fs_realpath (vim.fs.dirname path))]
            (if dir (.. dir "/" (vim.fs.basename path)) path))))

(fn buf_path [buf_id]
    (let [name (vim.api.nvim_buf_get_name buf_id)]
        (when (not= name "")
            (realpath (vim.fn.fnamemodify name ":p")))))

(fn relpath [root path]
    (when (and path (vim.startswith path (.. root "/")))
        (string.sub path (+ (length root) 2))))

(fn current_dir []
    (let [path (buf_path 0)]
        (if (and path (= 1 (vim.fn.isdirectory (vim.fs.dirname path))))
            (vim.fs.dirname path)
            (vim.fn.getcwd))))

(fn git_root [dir]
    (let [root (git [:rev-parse :--show-toplevel] dir)]
        (when root (realpath root))))

(fn default_branch [root]
    (or (git [:rev-parse :--abbrev-ref :origin/HEAD] root)
        (accumulate [found nil
                     _ ref (ipairs [:origin/main :origin/master :main :master])
                     &until found]
            (when (git [:rev-parse :--verify :--quiet ref] root) ref))))

(fn base_text [base rel]
    "Contents of `rel` at the base commit, or nil if it did not exist."
    (let [res (: (vim.system [:git :show (.. base.sha ":" rel)] {:cwd base.root :text true}) :wait)]
        (when (= res.code 0) res.stdout)))

(fn buf_text [buf_id]
    (.. (table.concat (vim.api.nvim_buf_get_lines buf_id 0 -1 false) "\n") "\n"))

(fn disk_text [path]
    (let [lines (if (= 1 (vim.fn.filereadable path)) (vim.fn.readfile path) [])]
        (if (= (length lines) 0) "" (.. (table.concat lines "\n") "\n"))))

;; ----------------------------------------------------------------------------
;; Saved state

(local STATE_DIR (.. (vim.fn.stdpath :state) "/review"))
(local SETTINGS_FILE (.. STATE_DIR "/settings.json"))

(fn read_json [path]
    (when (= 1 (vim.fn.filereadable path))
        (let [(ok value) (pcall vim.json.decode (table.concat (vim.fn.readfile path) "\n"))]
            (when (and ok (= (type value) :table)) value))))

(fn write_json [path value]
    (vim.fn.mkdir STATE_DIR :p)
    (vim.fn.writefile [(vim.json.encode value)] path))

(fn current_branch [root]
    "The checked out branch, or nil when HEAD is detached."
    (let [head_file (.. root "/.git/HEAD")
          branch (if (= 1 (vim.fn.filereadable head_file))
                     (: (or (. (vim.fn.readfile head_file "" 1) 1) "") :match "^ref: refs/heads/(.+)$")
                     ;; Worktrees have a .git file instead of a directory.
                     (git [:branch :--show-current] root))]
        (when (not= branch "") branch)))

(fn branch_file [root branch]
    (.. STATE_DIR "/" (: (vim.fn.sha256 (.. root ":" branch)) :sub 1 16) ".json"))

(fn save_settings []
    (write_json SETTINGS_FILE {:overlay H.overlay}))

(fn save_branch_state [root]
    "Save the review base and open notes buffers for `root`'s current branch."
    (let [branch (and root (not H.exiting) (current_branch root))]
        (when branch
            (write_json (branch_file root branch)
                {: root
                 : branch
                 :ref (when (and H.base (= H.base.root root)) H.base.ref)
                 :notes (icollect [_ buf_id (ipairs (vim.api.nvim_list_bufs))]
                            (let [name (vim.api.nvim_buf_get_name buf_id)]
                                (when (and (= 1 (vim.fn.buflisted buf_id)) (= (. H.notes_roots name) root))
                                    name)))}))))

(let [settings (read_json SETTINGS_FILE)]
    (when (and settings (= (type settings.overlay) :table))
        (each [mode on (pairs settings.overlay)]
            (tset H.overlay mode on))))

;; ----------------------------------------------------------------------------
;; mini.diff source

(fn set_ref_text [buf_id text]
    (when (vim.api.nvim_buf_is_valid buf_id)
        ;; mini.diff ends the text with a newline, and stores no text for `[]`.
        (tset H.ref_texts buf_id (if (not= (type text) :string) false
                                     (= (text:sub -1) "\n") text
                                     (.. text "\n")))
        (pcall mini_diff.set_ref_text buf_id text)))

(fn keep_review_ref_text [buf_id]
    "Put back the base text if something else replaced it.

    When review mode starts, a buffer may already be attached to mini.diff's
    git source, which may still be reading the index. Detaching doesn't stop
    that read, and when it finishes it sets the index as the reference text."
    (let [expected (. H.ref_texts buf_id)
          data (and expected H.base (vim.api.nvim_buf_is_valid buf_id) (mini_diff.get_buf_data buf_id))]
        (when (and data (= data.summary.source_name :review) (not= data.ref_text expected))
            (pcall mini_diff.set_ref_text buf_id expected))))

(fn sync_overlay [buf_id]
    (let [data (and (vim.api.nvim_buf_is_valid buf_id) (mini_diff.get_buf_data buf_id))
          want (. H.overlay (if H.base :review :normal))]
        (when (and data data.ref_text (not= data.overlay want))
            (mini_diff.toggle_overlay buf_id))))

(fn review_source []
    (fn attach [buf_id]
        (let [base H.base
              rel (and base (relpath base.root (buf_path buf_id)))]
            (if (= rel nil)
                ;; Not in the reviewed repo, so let the next source handle it.
                false
                (do
                    (vim.system [:git :show (.. base.sha ":" rel)] {:cwd base.root :text true}
                        (vim.schedule_wrap (fn [res]
                            (when (= H.base base)
                                (if (= res.code 0)
                                    (set_ref_text buf_id (pick-values 1 (res.stdout:gsub "\r\n" "\n")))
                                    ;; Not in the base: a new file, unless git ignores it. mini.diff
                                    ;; can't take an empty reference, so a new file's first line
                                    ;; shows as changed rather than added.
                                    (vim.system [:git :check-ignore :--quiet rel] {:cwd base.root}
                                        (vim.schedule_wrap (fn [ignore]
                                            (when (= H.base base)
                                                (set_ref_text buf_id (if (= ignore.code 0) [] "")))))))))))
                    nil))))

    {:name :review : attach})

(fn reattach_buffers []
    (each [_ buf_id (ipairs (vim.api.nvim_list_bufs))]
        (when (mini_diff.get_buf_data buf_id)
            (mini_diff.disable buf_id)
            (mini_diff.enable buf_id)))
    ;; Also catch the current buffer if mini.diff had given up on it.
    (when (and (= vim.bo.buftype "") vim.bo.buflisted)
        (mini_diff.enable 0)))

;; ----------------------------------------------------------------------------
;; Changed files

(fn committed_changes [base]
    "Files changed between the base and HEAD, as {path status}."
    (let [out (git [:diff :--name-status :--no-renames :-z base.sha :HEAD] base.root)
          fields (if out (vim.split out NUL {:plain true}) [])
          changes {}]
        (for [i 1 (- (length fields) 1) 2]
            (tset changes (. fields (+ i 1)) (. fields i)))
        changes))

(fn refresh_worktree_changes [on_done]
    (let [base H.base]
        (vim.system [:git :status :--porcelain=v1 :-z :--untracked-files=all] {:cwd base.root :text true}
            (vim.schedule_wrap (fn [res]
                (when (and (= res.code 0) (= H.base base))
                    (let [changes {}]
                        (var skip_next false)
                        (each [_ field (ipairs (vim.split res.stdout NUL {:plain true}))]
                            (if skip_next
                                (set skip_next false)
                                (> (length field) 3)
                                (let [xy (field:sub 1 2)
                                      status (if (= xy "??") "?"
                                                 (not= (xy:sub 2 2) " ") (xy:sub 2 2)
                                                 (xy:sub 1 1))]
                                    ;; Renames and copies are followed by the source path.
                                    (when (xy:find "[RC]") (set skip_next true))
                                    (tset changes (field:sub 4) (if (status:find "[RC]") "A" status)))))
                        (set H.worktree_changes changes)
                        (when on_done (on_done)))))))))

(fn changed_files []
    "Picker items for files changed since the base. The two status columns are
    committed changes and uncommitted changes."
    (let [base H.base
          committed (committed_changes base)
          worktree H.worktree_changes
          paths (vim.tbl_keys (vim.tbl_extend :force {} committed worktree))]
        (table.sort paths)
        (icollect [_ rel (ipairs paths)]
            {:text (.. (or (. committed rel) " ") (or (. worktree rel) " ") " " rel)
             :path (.. base.root "/" rel)
             : rel})))

(fn file_diff [item opts]
    (text_diff (or (base_text H.base item.rel) "") (disk_text item.path) opts))

(fn first_changed_line [item]
    (let [hunk (. (file_diff item {:result_type :indices}) 1)]
        (if hunk (math.max 1 (. hunk 3)) 1)))

(fn open_item [item]
    (vim.cmd.edit (vim.fn.fnameescape item.path))
    (pcall vim.api.nvim_win_set_cursor 0 [(first_changed_line item) 0])
    (vim.cmd "normal! zz"))

(fn preview_item [buf_id item]
    (let [patch (file_diff item {:result_type :unified :ctxlen 3})
          lines (if (= patch "") ["No changes since the base"] (vim.split patch "\n" {:trimempty true}))]
        (vim.api.nvim_buf_set_lines buf_id 0 -1 false lines)
        (tset vim.bo buf_id :filetype :diff)))

;; ----------------------------------------------------------------------------
;; Base version notes
;;
;; The base version toggle swaps the window between a file and a copy of it at
;; the base, named like `review://master@0123456789ab/path/to/file.rb`. The
;; copy is editable, for taking notes. Notes are saved automatically under
;; NOTES_DIR (one file per base commit and path), are marked in the sign
;; column, and never touch the real file or its diff.
;;
;; When toggling, the cursor moves to the matching line on the other side, at
;; the same height in the window, so only the changed code appears to move.

(fn map_line [hunks line from_current]
    "Map `line` to the other side of `hunks` (vim.diff indices from base to
    current). `from_current` maps a current line to the base, otherwise the
    reverse."
    ;; Lines up to `before` on this side precede the hunk; `count` lines follow.
    (var after_offset 0)
    (var result nil)
    (each [_ [start_a count_a start_b count_b] (ipairs hunks) &until result]
        (let [(start count other_start other_count) (if from_current
                                                         (values start_b count_b start_a count_a)
                                                         (values start_a count_a start_b count_b))
              before (if (= count 0) start (- start 1))
              other_before (if (= other_count 0) other_start (- other_start 1))]
            (if (<= line before)
                (set result (+ line (- other_before before)))
                (<= line (+ before count))
                ;; Inside a changed hunk: keep the position within it if possible.
                (set result (+ other_before (math.min (- line before) other_count)))
                (set after_offset (- (+ other_before other_count) (+ before count))))))
    (math.max 1 (or result (+ line after_offset))))

(fn map_across [line from_text base_text to_text]
    "Map `line` in `from_text` to `to_text`, going through the base."
    (let [base_line (map_line (text_diff base_text from_text {:result_type :indices}) line true)]
        (map_line (text_diff base_text to_text {:result_type :indices}) base_line false)))

(fn move_to_line [line row_in_window col]
    (let [last (vim.api.nvim_buf_line_count 0)
          line (math.min line last)]
        (vim.api.nvim_win_set_cursor 0 [line col])
        (vim.fn.winrestview {:topline (math.max 1 (- line row_in_window))})))

(fn cursor_state []
    (let [[line col] (vim.api.nvim_win_get_cursor 0)]
        (values line (- line (. (vim.fn.winsaveview) :topline)) col)))

(fn notes_name [base rel]
    (.. "review://" base.ref "@" (base.sha:sub 1 12) "/" rel))

(fn mark_notes [buf_id]
    (let [info (. H.notes buf_id)]
        (when info
            (vim.api.nvim_buf_clear_namespace buf_id notes_ns 0 -1)
            (each [_ [_start_a _count_a start count] (ipairs (text_diff info.base_text (buf_text buf_id) {:result_type :indices}))]
                (for [line start (+ start count -1)]
                    (vim.api.nvim_buf_set_extmark buf_id notes_ns (- line 1) 0
                        {:sign_text "▍" :sign_hl_group :DiagnosticSignHint}))))))

(fn save_notes [buf_id]
    (let [info (. H.notes buf_id)]
        (when info
            (if (= (buf_text buf_id) info.base_text)
                (os.remove info.notes_path)
                (do
                    (vim.fn.mkdir (vim.fs.dirname info.notes_path) :p)
                    (vim.fn.writefile (vim.api.nvim_buf_get_lines buf_id 0 -1 false) info.notes_path)))
            (tset vim.bo buf_id :modified false))))

(fn read_notes_buffer [buf_id]
    "Fill a `review://` buffer with its saved notes, or the file at the base."
    (let [name (vim.api.nvim_buf_get_name buf_id)
          (ref short rel) (name:match "^review://(.-)@(%x+)/(.+)$")
          root (or (. H.notes_roots name)
                   (if (and short H.base (vim.startswith H.base.sha short))
                       H.base.root
                       (git_root (vim.fn.getcwd))))
          sha (and root short (git [:rev-parse :--verify :--quiet (.. short "^{commit}")] root))
          text (and sha (base_text {: root : sha} rel))]
        (if (= text nil)
            (vim.notify (.. "Review: can't load " name) vim.log.levels.WARN)
            (let [notes_path (.. NOTES_DIR "/" sha "/" rel)
                  undolevels (. vim.bo buf_id :undolevels)
                  (base_lines) (text:gsub "\n$" "")]
                ;; Loading the text shouldn't be undoable.
                (tset vim.bo buf_id :undolevels -1)
                (vim.api.nvim_buf_set_lines buf_id 0 -1 false
                    (if (= 1 (vim.fn.filereadable notes_path))
                        (vim.fn.readfile notes_path)
                        (vim.split base_lines "\n")))
                (tset vim.bo buf_id :undolevels undolevels)
                (tset H.notes buf_id {:base_text text : notes_path})
                (tset vim.b buf_id :review_file (.. root "/" rel))
                ;; Not a real file, so writes go through BufWriteCmd and LSP skips it.
                (tset vim.bo buf_id :buftype :acwrite)
                (tset vim.bo buf_id :swapfile false)
                (tset vim.bo buf_id :modified false)
                (tset vim.bo buf_id :filetype (or (vim.filetype.match {:filename rel}) ""))
                (mark_notes buf_id)
                (tset H.notes_roots name root)
                (save_branch_state root)))))

;; ----------------------------------------------------------------------------
;; Public functions

(fn start [ref root]
    "Review against the merge base of HEAD and `ref` (default: the default branch)."
    (let [root (or root (git_root (current_dir)))
          ref (or ref (and root (default_branch root)))
          sha (and root ref (or (git [:merge-base :HEAD ref] root)
                                (git [:rev-parse :--verify :--quiet (.. ref "^{commit}")] root)))]
        (if (= root nil)
            (vim.notify "Review: not in a git repository" vim.log.levels.WARN)
            (= sha nil)
            (vim.notify (.. "Review: can't resolve base " (tostring ref)) vim.log.levels.ERROR)
            (do
                (when (= H.base nil)
                    (set H.saved_source mini_diff.config.source))
                (set H.base {: root : ref : sha})
                (set H.worktree_changes {})
                (set H.ref_texts {})
                (set vim.g.review_base ref)
                (set mini_diff.config.source [(review_source) (mini_diff.gen_source.git)])
                (reattach_buffers)
                (refresh_worktree_changes)
                (save_branch_state root)
                (vim.notify (string.format "Reviewing against %s (%s)" ref (sha:sub 1 10)))))))

(fn stop []
    (when H.base
        (local root H.base.root)
        (set H.base nil)
        (set H.ref_texts {})
        (set vim.g.review_base nil)
        (set mini_diff.config.source H.saved_source)
        (reattach_buffers)
        (save_branch_state root)
        (vim.notify "Review mode off")))

(fn toggle_overlay []
    "Toggle the mini.diff overlay in all buffers, for the current mode."
    (let [mode (if H.base :review :normal)]
        (tset H.overlay mode (not (. H.overlay mode)))
        (save_settings)
        (each [_ buf_id (ipairs (vim.api.nvim_list_bufs))]
            (sync_overlay buf_id))
        (vim.notify (.. "Diff overlay " (if (. H.overlay mode) "on" "off") (if H.base " in review mode" "")))))

(fn restore_branch_state [root]
    "Reopen the notes buffers and review base saved for `root`'s branch."
    (let [branch (current_branch root)
          state (and branch (read_json (branch_file root branch)))]
        (when state
            (each [_ name (ipairs (or state.notes []))]
                (tset H.notes_roots name root)
                ;; Listed but not loaded until visited.
                (tset vim.bo (vim.fn.bufadd name) :buflisted true))
            (when (and (= (type state.ref) :string) (= H.base nil))
                (start state.ref root)))))

(fn restore_for_buffer [buf_id]
    "Restore saved state the first time a file in a repo is opened."
    (let [name (vim.api.nvim_buf_get_name buf_id)
          found (and (vim.api.nvim_buf_is_valid buf_id)
                     (= (. vim.bo buf_id :buftype) "")
                     (not= name "")
                     (vim.fs.root buf_id ".git"))
          root (and found (realpath found))]
        (when (and root (not (. H.restored root)))
            (tset H.restored root true)
            (restore_branch_state root))))

(fn ensure_base []
    (when (= H.base nil) (start))
    H.base)

(fn pick_base []
    (let [root (git_root (current_dir))]
        (if (= root nil)
            (vim.notify "Review: not in a git repository" vim.log.levels.WARN)
            (let [default (default_branch root)
                  current (git [:branch :--show-current] root)
                  items [default]]
                (each [_ branch (ipairs (git_lines [:for-each-ref :--sort=-committerdate "--format=%(refname:short)" :refs/heads] root))]
                    (when (and (not= branch current) (not= branch default))
                        (table.insert items branch)))
                (mini_pick.start {:source {
                    :name "Review base"
                    : items
                    ;; Show the commits that would be under review.
                    :preview (fn [buf_id ref]
                        (vim.api.nvim_buf_set_lines buf_id 0 -1 false
                            (git_lines [:log :--oneline :-n :200 (.. ref "..HEAD")] root)))
                    :choose (fn [ref] (when ref (vim.schedule #(start ref))) nil)}})))))

(fn pick_changed_files []
    (when (ensure_base)
        (let [name (.. "Changed since " H.base.ref)]
            ;; `git status` may finish after the picker opens; update it in place.
            (refresh_worktree_changes #(when (and (mini_pick.is_picker_active)
                                                  (= (. (mini_pick.get_picker_opts) :source :name) name))
                                           (mini_pick.set_picker_items (changed_files))))
            (mini_pick.start {:source {
                : name
                :items (changed_files)
                :cwd H.base.root
                :preview preview_item
                :choose (fn [item] (when item (vim.schedule #(open_item item))) nil)}}))))

(fn goto_changed_file [direction]
    (when (ensure_base)
        (let [items (changed_files)
              n (length items)
              current (relpath H.base.root (buf_path 0))]
            (refresh_worktree_changes)
            (if (= n 0)
                (vim.notify "Review: no changed files" vim.log.levels.INFO)
                (do
                    (var idx (if (= direction :next) 1 n))
                    (when current
                        (if (= direction :next)
                            (for [i n 1 -1] (when (> (. items i :rel) current) (set idx i)))
                            (for [i 1 n] (when (< (. items i :rel) current) (set idx i)))))
                    (open_item (. items idx)))))))

(fn toggle_base_version []
    (let [file vim.b.review_file]
        (if file
            ;; In a notes buffer: go back to the file.
            (let [info (. H.notes (vim.api.nvim_get_current_buf))
                  (line row col) (cursor_state)
                  notes_text (buf_text 0)]
                (vim.cmd.edit (vim.fn.fnameescape file))
                (when info
                    (move_to_line (map_across line notes_text info.base_text (buf_text 0)) row col)))
            (when (ensure_base)
                (let [base H.base
                      rel (relpath base.root (buf_path 0))]
                    (if (= rel nil)
                        (vim.notify "Review: buffer is not in the reviewed repo" vim.log.levels.INFO)
                        (= nil (base_text base rel))
                        (vim.notify (.. "Review: file is not in " base.ref) vim.log.levels.INFO)
                        (let [(line row col) (cursor_state)
                              file_text (buf_text 0)]
                            (vim.cmd.edit (vim.fn.fnameescape (notes_name base rel)))
                            (let [info (. H.notes (vim.api.nvim_get_current_buf))]
                                (when info
                                    (move_to_line (map_across line file_text info.base_text (buf_text 0)) row col))))))))))

(vim.api.nvim_create_autocmd :BufReadCmd {
    :group augroup
    :pattern "review://*"
    :callback #(read_notes_buffer $.buf)})

(vim.api.nvim_create_autocmd :BufWriteCmd {
    :group augroup
    :pattern "review://*"
    :callback #(save_notes $.buf)})

(vim.api.nvim_create_autocmd [:TextChanged :InsertLeave] {
    :group augroup
    :pattern "review://*"
    :callback #(do (save_notes $.buf) (mark_notes $.buf))})

(vim.api.nvim_create_autocmd :TextChangedI {
    :group augroup
    :pattern "review://*"
    :callback #(mark_notes $.buf)})

(vim.api.nvim_create_autocmd :BufWipeout {
    :group augroup
    :pattern "review://*"
    :callback #(tset H.notes $.buf nil)})

;; Forget closed notes buffers. The buffer is still listed during the event.
(vim.api.nvim_create_autocmd [:BufDelete :BufWipeout] {
    :group augroup
    :pattern "review://*"
    :callback (fn [args]
        (let [root (. H.notes_roots (vim.api.nvim_buf_get_name args.buf))]
            (vim.schedule #(save_branch_state root))))})

;; Not scheduled: restoring before mini.diff's own (scheduled) enable means the
;; buffer starts on the review source instead of switching to it.
(vim.api.nvim_create_autocmd :BufEnter {
    :group augroup
    :callback #(restore_for_buffer $.buf)})

(vim.api.nvim_create_autocmd :VimLeavePre {
    :group augroup
    :callback #(set H.exiting true)})

;; Keep each buffer's base text, and its overlay in line with the setting for
;; the current mode.
(vim.api.nvim_create_autocmd :User {
    :group augroup
    :pattern :MiniDiffUpdated
    :callback (fn [args] (vim.schedule #(do (keep_review_ref_text args.buf)
                                            (sync_overlay args.buf))))})

(each [_ command (ipairs [:Review :ReviewBase])]
    (vim.api.nvim_create_user_command command
        (fn [opts] (start (if (= opts.args "") nil opts.args)))
        {:nargs "?"
         :desc "Review changes since a git base (default: the default branch)"
         :complete (fn [lead]
            (let [root (git_root (current_dir))
                  refs (if root (git_lines [:for-each-ref "--format=%(refname:short)" :refs/heads] root) [])
                  default (and root (default_branch root))]
                (when default (table.insert refs 1 default))
                (vim.tbl_filter #(vim.startswith $ lead) refs)))}))

(vim.api.nvim_create_user_command :ReviewOff #(stop) {:desc "Stop review mode"})

{
    :start #(start)
    : stop
    : pick_base
    : pick_changed_files
    :changed_files #(when (ensure_base) (changed_files))
    : toggle_base_version
    : toggle_overlay
    :next_file #(goto_changed_file :next)
    :prev_file #(goto_changed_file :prev)
    :next_hunk #(mini_diff.goto_hunk :next)
    :prev_hunk #(mini_diff.goto_hunk :prev)
}
