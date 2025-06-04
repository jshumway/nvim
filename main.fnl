;; TODO: an indicator in the status line that I have a buffer, besides
;; the current one, that is backed by a file, and isn't saved... and it
;; is like yellow.

;; ---------------------------------------------------------------------
;; Config reloading

(local augroup_user (vim.api.nvim_create_augroup :user {:clear true}))

;; NOTE: this only supports reloading this specific file, not any of the
;; files that this one `requires`.
; (vim.api.nvim_create_autocmd :BufWritePost {
;     :group augroup_user
;     :pattern "main.fnl"
;     :callback #(do
;         (fennel.dofile (.. MYVIMRC_ROOT "main.fnl"))
;         (vim.notify "Config reloaded"))
; })

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

(now-let [m (require :mini.basics)]
    (m.setup)
    (set vim.o.termguicolors true)
    (set vim.o.confirm true)
    ; (map :n :<leader>fE #(vim.cmd.edit (.. MYVIMRC_ROOT "main.fnl")) {:desc "Edit .nvimrc"})
    )

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
    (set vim.notify (m.make_notify)))

(now-let [m (require :mini.icons)]
    (m.setup)
    (m.mock_nvim_web_devicons)
    (m.tweak_lsp_kind))

(now-let [m (require :mini.extra)]
    (m.setup))

(now-let [m (require :mini.pick)]
    (m.setup))

;; ---------------------------------------------------------------------
;; Modules

(local module_clues [])

(now-let [m (require :editor)]
    (map :n :<Leader>cc "\"+y" {:noremap true :desc "Motion"})
    (map :v :<Leader>cc "\"+y" {:noremap true :desc "Selection"})
    (map :n :<Leader>cp m.copy_relative_path {:noremap true :desc "Relative path"})
    (map :n :<Leader>cn m.copy_path_and_line_number {:noremap true :desc "Path & line"})
    (map :n :<Leader>cP m.copy_absolute_path {:noremap true :desc "Absolute path"})
    (map :n :<Leader>cf m.copy_filename {:noremap true :desc "Filename"})

    (map :n :<C-u> m.half_page_up_center {:noremap true})
    (map :n :<C-d> m.half_page_down_center {:noremap true})

    (map :n :n m.search_next_centered_nojumplist {:silent true :noremap true})
    (map :n :N m.search_prev_centered_nojumplist {:silent true :noremap true})

    (map :x :I m.shift_i_in_visual_mode {:expr true :silent true :noremap true})

    (table.insert module_clues [
        {:mode :x :keys :<Leader>c :desc :+Copy}
        {:mode :n :keys :<Leader>c :desc :+Copy}
    ]))

(now-let [m (require :mini.statusline)
          mm (require :statusline)]
    (m.setup {
        :content {
            :active mm.active
            :inactive mm.inactive
        }
    }))

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
    (map :n :<Leader>wh m.horizontal_split {:noremap true :desc "Horizontal split"})

    (map :n :<Leader>wx m.exchange_windows {:noremap true :desc "Exchange splits"})
    (map :n :<Leader>w= m.rebalance_splits {:noremap true :desc "Rebalance splits"})

    (map :n :<Leader>wh m.focus_window_left {:noremap true :desc "Focus left"})
    (map :n :<Leader>wj m.focus_window_down {:noremap true :desc "Focus down"})
    (map :n :<Leader>wk m.focus_window_up {:noremap true :desc "Focus up"})
    (map :n :<Leader>wl m.focus_window_right {:noremap true :desc "Focus right"})

    (map :n :<C-h> m.focus_window_left {:noremap true})
    (map :n :<C-j> m.focus_window_down {:noremap true})
    (map :n :<C-k> m.focus_window_up {:noremap true})
    (map :n :<C-l> m.focus_window_right {:noremap true})

    (map :n :<Leader>wz m.toggle_zoom_window {:noremap true})

    (table.insert module_clues [
        {:mode :n :keys :<Leader>w :desc :+Windows}
        {:mode :n :keys :<Leader>wh :postkeys :<Leader>w}
        {:mode :n :keys :<Leader>wj :postkeys :<Leader>w}
        {:mode :n :keys :<Leader>wk :postkeys :<Leader>w}
        {:mode :n :keys :<Leader>wl :postkeys :<Leader>w}
        {:mode :n :keys :<Leader>wc :postkeys :<Leader>w}
        {:mode :n :keys :<Leader>wv :postkeys :<Leader>w}
        {:mode :n :keys :<Leader>wh :postkeys :<Leader>w}
    ]))

(now-let [m (require :theme)]
    (m.no_clown_fiesta))

(now-let [m (require :starter)] nil)

(later-let [m (require :navigation)]
    (map :n :<Leader>r m.resume_last_picker {:desc "Last picker"})

    (map :n :<Leader>fr m.pick_recent {:noremap true :desc "Recent files"})
    (map :n :<Leader>fe m.explore_files_at_current_path {:desc "File explorer"})
    (map :n :<Leader>ff m.pick_files_at_path {:desc "Find files"})
    (map :n :<Leader>fF m.pick_files {:desc "Find files (global)"})
    (map :n :<Leader>fi m.pick_grep_live_at_path {:desc "Interactive grep"})
    (map :n :<Leader>fI m.pick_grep_live {:desc "Interactive grep (global)"})
    (map :n :<Leader>fg m.pick_grep_at_path {:desc "Grep"})
    (map :n :<Leader>fG m.pick_grep {:desc "Grep (global)"})
    (map :n :<Leader>fh m.pick_help {:desc "Help"})

    (map :n :<Leader>at m.arglist_add {:desc "Track"})
    (map :n :<Leader>au m.arglist_delete {:desc "Untrack"})
    (map :n :<Leader>ap m.arglist_pick {:desc "Pick"})
    (map :n :<Leader>ac m.arglist_clear {:desc "Clear"})
    (map :n :<Leader>an m.arglist_next {:desc "Next"})
    (map :n :<Leader>aN m.arglist_prev {:desc "Prev"})

    (table.insert module_clues [
        {:mode :n :keys :<Leader>f :desc :+Find}
        ; {:mode :n :keys :<Leader>s :desc :+Search}
        {:mode :n :keys :<Leader>a :desc :+Arglist}

        {:mode :n :keys :<Leader>an :postkeys :<Leader>a}
        {:mode :n :keys :<Leader>aN :postkeys :<Leader>a}
    ]))

(now-let [m (require :editor-advanced)]
    ;; Completion pop-up navigation.
    (map :i :<Tab> m.move_down_suggestions {:noremap true :expr true})
    (map :i :<S-Tab> m.move_down_suggestions {:noremap true :expr true})

    ;; LSP
    (m.on_lsp_attach (fn [ctx]
        (map :n :gD m.type_definition {:buffer ctx.buf :desc "Goto type"})
        (map :n :gO m.outline {:buffer ctx.buf :desc "Outline"})
        (map :n :gd m.definition {:buffer ctx.buf :desc "Goto definition"})
        (map :n :gi m.implementation {:buffer ctx.buf :desc "Goto implementation"})
        (map :n :gra m.code_action {:buffer ctx.buf :desc "Code action"})
        (map :n :grd m.declaration {:buffer ctx.buf :desc "Goto declaration"})
        (map :n :gri m.implementation {:buffer ctx.buf :desc "Goto implementation"})
        (map :n :grn m.rename {:buffer ctx.buf :desc "Rename symbol"})
        (map :n :grr m.references {:buffer ctx.buf :desc "Goto references"})
        ))

    ; ;; Repl
    ; (map :n :<Leader>mf m.repl.focus {:desc "Toggle repl"})
    ; (map :n :<Leader>mC m.repl.close {:desc "Exit repl"})
    ; (map :n :<Leader>mM m.repl.send_line {:desc "Send line"})
    ; (map :n :<C-m> m.repl.send_operator {:desc "Send operator"})
    ; (map :v :<Leader>mm m.repl.send_visual {:desc "Send visual"})

    ; (table.insert module_clues [
    ;     {:mode :n :keys :<Leader>m :desc :+Mode}
    ;     {:mode :x :keys :<Leader>m :desc :+Mode}
    ; ])
    )

(later-let [m (require :terminal)
            main_terminal (m.create_terminal)]
    (map :n :<C-t> #(m.focus_or_toggle main_terminal) {:silent true})
    (map :i :<C-t> #(m.focus_or_toggle main_terminal) {:silent true})
    (map :t :<C-t> #(m.focus_or_toggle main_terminal) {:silent true})

    (map :t :<ESC> m.escape_from_terminal_insert_mode {:noremap true :silent true})
    ;; NOTE: <C-k><C-k> prevents conflict with the readline command <C-k>
    ;; used to kill the rest of the line.
    ; (map :t :<C-k><C-k> m.terminal_insert_focus_window_up {:noremap true :silent true})

    (m.on_term_enter (fn [ctx]
        (map :n :<ESC> #(m.focus_or_toggle main_terminal) {:buffer ctx.buf :silent true}))))

(later-let [m (require :diff)]
    (map :n :<Leader>dS m.toggle_inline_changes {:noremap true :silent true :desc "Show diff inline"})

    (table.insert module_clues [
        {:mode :n :keys :<Leader>d :desc :+Diff}
    ]))

(later-let [m (require :ai)
            terminal (require :terminal)
            goose_terminal (m.create_goose_terminal)]
    (map :n :<Leader>gg #(terminal.focus_or_toggle goose_terminal) {:noremap true :silent true :desc "Goose"})

    (m.on_goose_term_enter (fn [ctx]
        (map :n :<ESC> #(terminal.focus_or_toggle goose_terminal) {:buffer ctx.buf :silent true})))

    (table.insert module_clues [
        {:mode :n :keys :<Leader>g :desc :+Goose}
    ]))

;; TODO: disable because pay-server is so big.
;; (later-let [m (require :git)] nil)

;; ---------------------------------------------------------------------
;; Language modules
(now-let [m (require :lang.ruby)] nil)
(now-let [m (require :lang.fennel)] nil)

;; Load work specific settings last so they can overwrite the above
;; language modules as needed.
(when (vim.fn.filereadable :stripe.fnl)
    (now-let [m (require :stripe)]
        ;; TODO: ideally this would only be added to Ruby buffers.
        (map :n :<Leader>cS m.copy_symbol_name {:noremap true :desc "Copy symbol name"})))

;; ---------------------------------------------------------------------
;; Final setup
;;
;; Various modules allow other modules to add to their configuration. At
;; this point that should be finished, so we can finalize the setup for
;; such modules.

(let [m (require :editor-advanced)]
    (m.setup))

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

