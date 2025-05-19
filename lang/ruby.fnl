;; TODO: figure out how I can fold just one branch of a conditional at a time

(local augroup_module (vim.api.nvim_create_augroup :user_lang_ruby {:clear true}))

(local folds_query "
[
  (method)
  (singleton_method)
  (class)
  (module)
  (if)
  (else)
  (case)
  (block)
  (do_block)
  (singleton_class)
  (lambda)
] @fold
")

(local ts_parsers (require :nvim-treesitter.parsers))
(when (ts_parsers.has_parser :ruby)
    ((. (require :vim.treesitter.query) :set) :ruby :folds folds_query))

(vim.api.nvim_create_autocmd :FileType {
    :group augroup_module
    :pattern [:ruby]
    :callback (fn [ctx]
        (set vim.b.miniindentscope_disable false)
        (set vim.b.minicursorword_disable false)
    )})

