
;; ----------------------------------------------------------------------------------

(local mini_diff (require :mini.diff))

(local H {
    :is_enabled false
    :base_ref nil

    :git_cache {}
})

(local augroup (vim.api.nvim_create_augroup :plugin_example))

(vim.api.nvim_create_autocmd :BufEnter {
    :group augroup
    :pattern :*
    :desc ""
    :callback (fn []
        ;; if enabled and anything is missing, set it up:
        ;; - minidiff on, minidiff source as git_history, minidiff overlay mode
        ;; if disabled and anything is on that shouldn't be:
        ;; - minidiff source as normal git, minidiff overlay off
        ;; - though really what I want is to remember what these settings started
        ;;   as and reset them _just once per buffer_ per time the mode is
        ;;   globally disabled
    )})

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

(fn git_history_source [base_ref]
    (fn attach [buf_id]
        (when (. H.git_cache buf_id) (lua "return false"))
        (local path (get_buf_realpath buf_id))
        (when (= path "") (lua "return false"))
        (tset H.git_cache buf_id {})
        (get_git_history_for_file_and_set_ref_stuff buf_id base_ref))

    (fn detach [buf_id]
        (tset H.git_cache buf_id nil))

    (fn apply_hunks [])

    {:name :git_history : attach : detach : apply_hunks})

; -- Try getting buffer's full real path (after resolving symlinks)
; H.get_buf_realpath = function(buf_id) return vim.loop.fs_realpath(vim.api.nvim_buf_get_name(buf_id)) or '' end


; MiniDiff.gen_source.git = function()
;   local attach = function(buf_id)
;     -- Try attaching to a buffer only once
;     if H.git_cache[buf_id] ~= nil then return false end
;     -- - Possibly resolve symlinks to get data from the original repo
;     local path = H.get_buf_realpath(buf_id)
;     if path == '' then return false end
;
;     H.git_cache[buf_id] = {}
;     H.git_start_watching_index(buf_id, path)
;   end
;
;   local detach = function(buf_id)
;     local cache = H.git_cache[buf_id]
;     H.git_cache[buf_id] = nil
;     H.git_invalidate_cache(cache)
;   end
;
;   local apply_hunks = function(buf_id, hunks)
;     local path_data = H.git_get_path_data(H.get_buf_realpath(buf_id))
;     if path_data == nil or path_data.rel_path == nil then return end
;     local patch = H.git_format_patch(buf_id, hunks, path_data)
;     H.git_apply_patch(path_data, patch)
;   end
;
;   return { name = 'git', attach = attach, detach = detach, apply_hunks = apply_hunks }
; end

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
;; This can probably replace my usage of Diffview entierly

{
    :test set_merge_base_as_ref_text
}
