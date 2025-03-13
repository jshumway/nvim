;; ---------------------------------------------------------------------
;; Config reloading

(local augroup_user (vim.api.nvim_create_augroup :user {:clear true}))

;; NOTE: this only supports reloading this specific file, not any of the
;; files that this one `requires`.
(vim.api.nvim_create_autocmd :BufWritePost { 
    :group augroup_user
    :pattern "main.fnl"
    :callback #(do
        (fennel.dofile (.. MYVIMRC_ROOT "main.fnl"))
        (vim.notify "Config reloaded"))
})

;; ---------------------------------------------------------------------
;; Bootstrap mini_deps

(let [package_path (.. (vim.fn.stdpath :data) "/site")
      mini_path (.. package_path "/pack/deps/start/mini.nvim")]
    (when (not (vim.loop.fs_stat mini_path))
        (vim.cmd "echo 'Installing `mini.nvim`' | redraw")
        (vim.fn.system [:git :clone "--filter=blob:none" "https://github.com/echasnovski/mini.nvim" mini_path])
        (vim.cmd "packadd mini.nvim | helptags ALL"))
    ((. (require :mini.deps) :setup) { :path { :package package_path }}))

;; ---------------------------------------------------------------------
;; Config helpers

(local mini_deps (require :mini.deps))
(local add mini_deps.add)
(local map vim.keymap.set)
(macro now-let [bindings ...] `(mini_deps.now (fn [] (let ,bindings ,...))))
(macro later-let [bindings ...] `(mini_deps.later (fn [] (let ,bindings ,...))))

;; ---------------------------------------------------------------------
;; Basic config

;; TODO:
;; - make a bunch of commands silent (they currently pollute the command bar)
;; - hotkey to view notify history
;; - pressing esc in normal mode clears highlight (:nohl) (or maybe not tbh)

(now-let [m (require :mini.basics)]
    (m.setup)
    (tset vim.o :termguicolors true)
    (tset vim.o :confirm true)
    (map :n :<leader>fE #(vim.cmd.edit (.. MYVIMRC_ROOT "main.fnl")) {:desc "Edit .nvimrc"}))

(when (= vim.g.os :windows)
    (now-let [m (require :os-windows)]
        nil))

;; ---------------------------------------------------------------------
;; Global modules
;;
;; These modules provide basic functionality and can be required by
;; all other modules without setup.

;; Setup notify early so any errors come through mini.notify.
(now-let [m (require :mini.notify)]
    (m.setup)
    (tset vim :notify (m.make_notify)))

(now-let [m (require :mini.icons)]
    (m.setup)
    (m.mock_nvim_web_devicons)
    (m.tweak_lsp_kind))

(now-let [m (require :mini.extra)]
    (m.setup))

(now-let [m (require :mini.pick)]
    (m.setup))

;; TODO: clean up the status line; don't need total columns, encoding, file size
(now-let [m (require :mini.statusline)]
    (m.setup))

;; ---------------------------------------------------------------------
;; Modules

(local module_clues [])

(now-let [m (require :editor)]
    (table.insert module_clues [
        {:mode :n :keys :<Leader>m :desc :+Move}
        {:mode :x :keys :<Leader>m :desc :+Move}

        {:mode :n :keys :<Leader>mh :postkeys :<Leader>m}
        {:mode :x :keys :<Leader>mh :postkeys :<Leader>m}
        {:mode :n :keys :<Leader>mj :postkeys :<Leader>m}
        {:mode :x :keys :<Leader>mj :postkeys :<Leader>m}
        {:mode :n :keys :<Leader>mk :postkeys :<Leader>m}
    	{:mode :x :keys :<Leader>mk :postkeys :<Leader>m}
        {:mode :n :keys :<Leader>ml :postkeys :<Leader>m}
	    {:mode :x :keys :<Leader>ml :postkeys :<Leader>m}
    ]))

(now-let [m (require :buffers)]
    (map :n :<Leader><Leader> m.last_buffer {:noremap true :desc "Last buffer"})
    (map :n :<Leader>bb m.pick_buffers {:noremap true :desc "Pick buffer"})
    (map :n :<Leader>bd m.wipeout {:noremap true :desc "Delete buffer"})
    (map :n :<Leader>bn m.next_buffer {:noremap true :desc "Next buffer"})
    (map :n :<Leader>bp m.prev_buffer {:noremap true :desc "Prev buffer"})

    (table.insert module_clues [
        {:mode :n :keys :<Leader>b :desc :+Buffers}
        {:mode :n :keys :<Leader>bn :postkeys :<Leader>b}
        {:mode :n :keys :<Leader>bp :postkeys :<Leader>b}
        {:mode :n :keys :<Leader>bd :postkeys :<Leader>b}
    ]))

(now-let [m (require :windows)]
    (map :n :<Leader>ww m.last_window {:noremap true :desc "Last window"})
    (map :n :<Leader>wc m.close_window {:noremap true :desc "Close window"})
    (map :n :<Leader>wv m.vertical_split {:noremap true :desc "Vertical split"})
    (map :n :<Leader>wR m.rebalance_splits {:noremap true :desc "Rebalance splits"})

    (table.insert module_clues [
        {:mode :n :keys :<Leader>w :desc :+Windows}
    ]))

(now-let [m (require :theme)] nil)

(later-let [m (require :navigation)]
    (map :n :<Leader>fr m.pick_recent {:noremap true :desc "Recent files"})
    (map :n :<leader>fe m.explore_files_at_current_path {:desc "File explorer"})
    (map :n :<leader>ff m.pick_files {:desc "Find files"})
    (map :n :<leader>r m.resume_last_picker {:desc "Last picker"})
    (map :n :<leader>si m.pick_grep_live {:desc "Interactive grep"})
    (map :n :<leader>sg m.pick_grep {:desc "Grep"})
    (map :n :<leader>sh m.pick_help {:desc "Help"})

    (table.insert module_clues [
        {:mode :n :keys :<Leader>f :desc :+Files}
        {:mode :n :keys :<Leader>s :desc :+Search}
    ]))

(later-let [m (require :editor-advanced)]
    (m.on_lsp_attach (fn [ctx]
        (map :n :gd m.definition {:buffer ctx.buf :desc "Goto definition"})
        (map :n :gD m.type_definition {:buffer ctx.buf :desc "Goto type"})
        (map :n :grr m.references {:buffer ctx.buf :desc "Goto references"})
        (map :n :gi m.implementation {:buffer ctx.buf :desc "Goto implementation"})
        (map :n :grd m.declaration {:buffer ctx.buf :desc "Goto declaration"})

        (map :i :<C-s> m.signature_help {:buffer ctx.buf :desc "Signature help"})
        (map :n :<Leader>ld m.hover {:buffer ctx.buf :desc "Hover documentation"})

        (map :n :<Leader>la m.code_action {:buffer ctx.buf :desc "Code action"})
        (map :n :<Leader>lr m.rename {:buffer ctx.buf :desc "Rename symbol"})))

    (table.insert module_clues [
        {:mode :n :keys :<Leader>l :desc :+Lsp}
    ]))

(later-let [m (require :terminal)]
    (map :n :<C-t> m.normal_toggle_terminal {:noremap true :silent true})
    (map :i :<C-t> m.insert_toggle_terminal {:noremap true :silent true})
    (m.on_term_enter (fn [ctx]
        (map :t :<C-t> m.normal_toggle_terminal {:buffer ctx.buf :noremap true :silent true})
    )))

(later-let [m (require :diff)]
    nil
    ;; {:mode :n :keys :<Leader>d :desc :+Diff}
    )

(when (vim.fn.filereadable :stripe.fnl)
    (require :stripe))

;; ---------------------------------------------------------------------
;; Language modules

(later-let [m (require :lang.ruby)] nil)
(later-let [m (require :lang.fennel)] nil)

;; ---------------------------------------------------------------------
;; Clues

(later-let [m (require :mini.clue)]
    (local triggers [
        {:mode :n :keys :<Leader>} {:mode :x :keys :<Leader>}
        ;; Built-in completion.
        {:mode :i :keys :<C-x>}
        ;; `g` keys.
        {:mode :n :keys :g} {:mode :x :keys :g}
        ;; Marks.
        {:mode :n :keys "'"} {:mode :n :keys "`"} {:mode :x :keys "'"} {:mode :x :keys "`"}
        ;; Registers.
        {:mode :n :keys "\""} {:mode :x :keys "\""} {:mode :i :keys :<C-r>} {:mode :c :keys :<C-r>}
        ;; Window commands.
        {:mode :n :keys :<C-w>}
        ;; `z` key
        {:mode :n :keys :z} {:mode :x :keys :z}

        {:mode :n :keys "["}
        {:mode :n :keys "]"}
    ])

    (local clues [
        ;; MiniClue builtins.
        (m.gen_clues.builtin_completion)
        (m.gen_clues.g)
        (m.gen_clues.marks)
        (m.gen_clues.registers)
        (m.gen_clues.windows)
        (m.gen_clues.z)

        ;; Brackets submode.
        {:mode :n :keys "[c" :postkeys "[" :desc "Prev change"}
        {:mode :n :keys "]c" :postkeys "]" :desc "Next change"}
        {:mode :n :keys "[C" :postkeys "["}
        {:mode :n :keys "]C" :postkeys "]"}
    ])

    ;; Add module clues.
    (each [_ mcs (ipairs module_clues)]
        (each [_ clue (ipairs mcs)]
            (table.insert clues clue)))

    (m.setup {
        :triggers triggers
        :clues clues
        :window {
            :delay 200
            :config {
                :width 36
            }
        }
    }))

