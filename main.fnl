;; TODO:
;;
;; - Split into common config & work specific additions, move common config
;;   into github.com/jshumway repo
;;
;; - live (and non-live) grep across the codebase (mini.fuzzy)
;; - make a bunch of commands silent (they currently pollute the command bar)
;; - clean up statusline: don't need total columns, encoding, file size
;; - lsp motions: expand / shrink selection
;; - view notify history
;; - pressing esc in normal mode clears highlight (:nohl)
;; - mini.files binding for opening a file and closing the picker
;; - add linter / lsp error diagnostics stuff to status bar
;; - setup brackets to iterate through stuff like diagnostics, fixlist, w/e
;; - picker for files that have changed from the base of the branch (and since
;;   the previous commit, and unstaged)
;; - mini.visits labels...
;;      - add label based on current git branch
;;      - delete current branch name from label
;;      - find label from current git branch
;;      - add current git branch to all of the labels with selected git branch
;;        (carrying labels over from previous part of a feature)
;;      - make it so tabline only shows buffers labeled with the name of the current
;;        branch
;;      - and maybe an alternative to this when there isn't a git branch
;; - it'd be great not to display the tabline in the diffviewer tab
;; - normal mode ctrl-n/p to go to the prev/next entry in the last picker?
;;      - might require a PR to mini.pick
;; - need a way for (live)grep to be started with the current directory as the
;;   limiting path, as part of the search string so it is editable
;; - MiniPick.files key to open on right side of vsplit
;; - MiniExtra.pickers.diagnostic
;; - view hunk diff at current line in pop-up (w/ yanking)
;; - lsp rename opens buffers that it modifies... either want it to write automatically
;;   (so I can manage via git) or be able to quickly navigate between them, by like
;;   having the modified files in a quick list
;; 
;; - open scratch file: in ~, named after the current branch + .md, need a markdown
;;   viewer mode thing to make it nicer to
;;
;; writing mode:
;; - markdown viewer
;; - spell checking
;; - run stripe doc helpers
;;
;; - mini.pick:
;;      - create an action that sends all items in the current list to the quickfix
;;        list if nothing is marked, replacing the `M-CR` binding
;;      - create bindings to navigate the quickfix list easily
;;      - have a way to save/navigate to old `find references` quick lists
;;          - like a more filtered view into quickfix history that is for these reference
;;            searches specifically
;;
;; - add generated files status to statusline
;; - command to copy livegrep/sourcegraph link
;; - pay test integration
;;      show logs: --verbose --show-output
;; - pay commands (regen dataview, regen proto, sync generated files, pay generate)
;;      (just macros to run in a terminal? or as a background job?)
;; - pay-server integration: find __package.rb, find associated tests
;;      - this could be as simple as the same file name, but w/ .test.rb at the end
;; - sorbet: copy symbol 
;; - generate quickfix list from sorbet errors, lint warnings

;; Autogroup that all autocmds in this user config should use.
(local augroup_user (vim.api.nvim_create_augroup :user {:clear true}))

;; Set up basic automatic reloading of this file.
;; NOTE: this only supports reloading this specific file, not any of the
;; files that this one `requires`.
(vim.api.nvim_create_autocmd :BufWritePost { 
    :group augroup_user
    :pattern "main.fnl"
    :callback #(do
        (fennel.dofile (.. (string.gsub vim.env.MYVIMRC "(.*/)(.*)" "%1") "main.fnl"))
        (vim.notify "Config reloaded"))
})

;; Bootstrap mini.deps.

(let [package_path (.. (vim.fn.stdpath :data) "/site")
      mini_path (.. package_path "/pack/deps/start/mini.nvim")]
    (when (not (vim.loop.fs_stat mini_path))
        (vim.cmd "echo 'Installing `mini.nvim`' | redraw")
        (vim.fn.system [:git :clone "--filter=blob:none" "https://github.com/echasnovski/mini.nvim" mini_path])
        (vim.cmd "packadd mini.nvim | helptags ALL"))
    ((. (require :mini.deps) :setup) { :path { :package package_path }}))

;; Macros & globals.

(local add _G.MiniDeps.add)
(local map vim.keymap.set)
(macro now-let [bindings ...] `(_G.MiniDeps.now (fn [] (let ,bindings ,...))))
(macro later-let [bindings ...] `(_G.MiniDeps.later (fn [] (let ,bindings ,...))))

;; Basic config.

(now-let [m (require :mini.basics)]
    (m.setup {})
    (tset vim.o :termguicolors true)
    (tset vim.o :scrolloff 4)
    (tset vim.o :confirm true)

    (tset vim.o :tabstop 4)
    (tset vim.o :shiftwidth 4)
    (tset vim.o :softtabstop 4)
    (tset vim.o :expandtab true)

    (vim.opt.fillchars:append {:diff  "🞌"})

    (tset vim.o :diffopt "filler,context:500")

    ;; Buffer persistence - disable swapfiles, autosave and reload buffers regularly.
    ;; Ideally this will make vim play nice with frequent git checkouts.
    (tset vim.o :swapfile false)
    (tset vim.o :autowriteall true)
    ;; https://unix.stackexchange.com/a/383044
    (vim.api.nvim_create_autocmd [:FocusGained :BufEnter :CursorHold :CursorHoldI] {
        :group augroup_user
        :pattern "*"
        :command "if mode() !~ '\v(c|r.?|!|t)' && getcmdwintype() == '' | checktime | endif"
    })
    (vim.api.nvim_create_autocmd [:FileChangedShellPost] {
        :group augroup_user
        :pattern "*"
        ; :command "echohl WarningMsg | echo \"File changed on disk. Buffer reloaded.\" | echohl None"
        :callback (fn [] (vim.notify "File changed on disk: buffer reloaded."))
    })

    ;; Editing:
    ;; Shift indentation without losing selection.
    (map :x :< :<gv {:noremap true})
    (map :x :> :>gv {:noremap true})
    ;; Fix Y to work like C & D.
    (map :n :Y :y$ {:noremap true})
    ;; H / L go to start / end of line instead of screen.
    ; (map :n :H :^ {:noremap true}) ; use _ instead
    ; (map :n :L :$ {:noremap true}) ; 

    ;; Buffer management:
    ;; Double space to switch to previous buffer.
    (map :n :<Leader><Leader> :<c-^> {:noremap true :desc "Last buffer"})
    (map :n :<Leader>bn ":bnext<CR>" {:noremap true :desc "Next buffer"})
    (map :n :<Leader>bp ":bprevious<CR>" {:noremap true :desc "Prev buffer"})
    (map :n :<Leader>bd ":MiniBufremove.wipeout<CR>" {:noremap true :desc "Delete buffer"})

    ;; Window management:
    ;; Space-w-w to switch to next window.
    (map :n :<Leader>ww :<C-w>w {:noremap true :desc "Last window"})
    (map :n :<Leader>wv ":vsplit<CR>" {:noremap true :desc "Vertical split"})
    (map :n :<Leader>wc :<C-w>c {:noremap true :desc "Close window"})

    ;; Copying

    (map :n :cp ":let @\" = expand(\"%\")<CR>" {:noremap true :desc "Copy path"})


    ;; Stick with gt & gT instead.
    ; (map :n :<Leader>tt ":tabnext<CR>" {:noremap true :silent true :desc "Next tab"})

    ; ;; TODO: these should be buffer local to the diff buffers
    ; (map :n "[C" "]c" {:noremap true :silent true :desc "Next change"})
    ; (map :n "]C" "[c" {:noremap true :silent true :desc "Prev change"})

    ;; TODO: consider the "cursorline in active window" autogroup thing
    )

;; Setup notify early so any errors come through mini.notify.
(now-let [m (require :mini.notify)]
    (m.setup {})
    (tset vim :notify (m.make_notify)))

(now-let [m (require :mini.icons)]
    (m.setup {})
    (m.mock_nvim_web_devicons)
    (m.tweak_lsp_kind))

; (now-let [m (require :mini.tabline)] (m.setup {}))
(now-let [m (require :mini.statusline)]
    (m.setup {})
    ; (vim.api.nvim_create_autocmd :BufFilePost {
    ;     :group augroup_user
    ;     :pattern "*"
    ;     :callback (fn []
    ;         (when (= vim.bo.ft :terminal)
    ;             (tset vim.b :ministatusline_disable true)))
    ; })
)

(later-let [m (require :mini.extra)] (m.setup {}))
(later-let [m (require :mini.comment)] (m.setup {}))
(later-let [m (require :mini.completion)] (m.setup {}))
(later-let [m (require :mini.bufremove)] (m.setup {}))
(later-let [m (require :mini.diff)] (m.setup {}))

(later-let [m (require :mini.move)]
    (m.setup {
        :mappings {
            :left       :<Leader>mh
            :right      :<Leader>ml
            :down       :<Leader>mj
            :up         :<Leader>mk
            :line_left  :<Leader>mh
            :line_right :<Leader>ml
            :line_down  :<Leader>mj
            :line_up    :<Leader>mk
        }
    }))

(later-let [m (require :mini.jump)]
    (m.setup {
        :delay {
            :highlight 50
            :idle_stop 100000000
        }
    })
    (vim.cmd "highlight! link MiniJump Search"))

(now-let [m (require :mini.cursorword)]
    (m.setup {:delay 50})
    (vim.api.nvim_create_autocmd :FileType 
      {:group augroup_user
       :callback #(let [ft (. vim.bo $.buf :filetype)]
          ;; Enable for certain file types.
          (tset vim.b $.buf :minicursorword_disable
                (and (not= ft :fennel) (not= ft :ruby))))}))

(now-let [m (require :mini.indentscope)]
    (m.setup {
        :draw {
            :delay 50
            :animation (m.gen_animation.none)
        }
    })
    ;; TODO: make this a generic thing to add to different plugin loads
    (vim.api.nvim_create_autocmd :FileType 
      {:group augroup_user
       :callback #(let [ft (. vim.bo $.buf :filetype)]
          ;; Enable for certain file types.
          (tset vim.b $.buf :miniindentscope_disable
                (and (not= ft :fennel) (not= ft :ruby)))
          (when (= ft :fennel)
              (tset vim.b $.buf :miniindentscope_config {:options {:border :top}})))
      }))

(later-let [m (require :mini.pick)]
    (m.setup {
        :mappings {
            ; :choose_marked :<C-CR>
        }
    })
    (map :n :<Leader>bb ":Pick buffers<CR>" {:noremap true :desc "Pick buffer"})
    ;; TODO: custom action to move all results to the quickfix list
    ;;     basically <mark all> <choose marked>
    )

(later-let [m (require :mini.visits)]
    (m.setup {})
    (map :n :<Leader>fr _G.MiniExtra.pickers.visit_paths {:noremap true :desc "Recent files"}))

(later-let [m (require :mini.files)]
    (m.setup {
        :windows {
            :preview true
            :width_preview 120
        }
    })
    ;; Open MiniFiles in the same directory as the current buffer.
    (map :n :<leader>fe
        #(_G.MiniFiles.open (string.gsub (vim.fn.expand "%:p") "(.*/)(.*)" "%1"))
        {:desc "File explorer"}))

(later-let [m (require :mini.pick)]
    (m.setup)
    (map :n :<leader>ff _G.MiniPick.builtin.files {:desc "Find files"})
    (map :n :<leader>r _G.MiniPick.builtin.resume {:desc "Last picker"})

    (map :n :<leader>si _G.MiniPick.builtin.grep_live {:desc "Interactive grep"})
    (map :n :<leader>sg _G.MiniPick.builtin.grep {:desc "Grep"})

    (map :n :<leader>sh _G.MiniPick.builtin.help {:desc "Help"})
    )

(later-let [_ (add {:source :nvim-treesitter/nvim-treesitter
             :checkout :master :monitor :main
    	     :hooks {:post_checkout #(vim.cmd :TSUpdate)}})
            m (require :nvim-treesitter.configs)]
        (m.setup {
            :ensure_installed [:lua :vimdoc :ruby :fennel]
            :highlight {:enable true}
        }))

(later-let [_ (add {:source :neovim/nvim-lspconfig})
            m (require :lspconfig)]

    (vim.api.nvim_create_autocmd :LspAttach {
        :pattern "*"
        :group augroup_user
        :callback #(do
            ;; TODO: using this picker for definitions is really annoying
            (map :n :gd vim.lsp.buf.definition {:buffer $.buf :desc "Goto definition"})
            ; (map :n :gd #(_G.MiniExtra.pickers.lsp {:scope :definition}) {:buffer $.buf :desc "Goto definition"})
            (map :n :gD #(_G.MiniExtra.pickers.lsp {:scope :type_definition}) {:buffer $.buf :desc "Goto type"})
            (map :n :grr #(_G.MiniExtra.pickers.lsp {:scope :references}) {:buffer $.buf :desc "Goto references"})
            (map :i :<C-s> vim.lsp.buf.signature_help {:buffer $.buf :desc "Signature help"})

            (map :n :gi #(_G.MiniExtra.pickers.lsp {:scope :implementation}) {:buffer $.buf :desc "Goto implementation"})
            (map :n :grd #(_G.MiniExtra.pickers.lsp {:scope :declaration}) {:buffer $.buf :desc "Goto declaration"})

            (map :n :<Leader>lr vim.lsp.buf.rename {:buffer $.buf :desc "Rename symbol"})
            (map :n :<Leader>la vim.lsp.buf.code_action {:buffer $.buf :desc "Code action"})
            (map :n :<Leader>ld vim.lsp.buf.hover {:buffer $.buf :desc "Hover documentation"})
    )})

    ; (each [_ lsp (ipairs [:gopls])]
    ;     ((. m lsp :setup) {}))
    )

(later-let [_ (add {:source :akinsho/toggleterm.nvim})
            m (require :toggleterm)]
    (m.setup)

    (vim.api.nvim_create_autocmd :TermEnter {
        :pattern "term://*toggleterm#*"
        :group augroup_user
        :callback #(do
            (map :t :<C-t> "<Cmd>exe v:count1 . \"ToggleTerm\"<CR>" {:buffer $.buf :noremap true :silent true})
            ; (map :t :<Esc> :<C-\><C-N> {:noremap true :silent true})
        )})
    (map :n :<C-t> "<Cmd>exe v:count1 . \"ToggleTerm\"<CR>" {:noremap true :silent true})
    (map :i :<C-t> "<Esc><Cmd>exe v:count1 . \"ToggleTerm\"<CR>" {:noremap true :silent true})

    ;; TODO: enable pasting from unnamed register via C-R
    ; :tnoremap <expr> <C-R> '<C-\><C-N>"'.nr2char(getchar()).'pi'
    )

; (later-let [_ (add {:source :stevearc/conform.nvim
;                     :depends ["git@git.corp.stripe.com:stevearc/nvim-stripe-configs"]})
;             m (require :conform)]
;     (m.setup {
;         :formatters_by_ft {
;             :javascript ["prettierd"]
;             :typescript ["prettierd"]
;             :javascriptreact [ "prettierd" ]
;             :typescriptreact [ "prettierd" ]
;             :html [ "prettierd" ]
;             :json [ "prettierd" ]
;             :jsonc [ "prettierd" ]
;             :graphql [ "prettierd" ]
;             :go [:goimports :gofmt]
;             :lua [ "stylua" ]
;             :python [ "zoolander_format_python" ]
;             :sql [ "zoolander_format_sql" ]
;             :bzl [ "zoolander_format_build" ]
;             :java [ "zoolander_format_java" ]
;             :scala [ "zoolander_format_scala" ]
;             :terraform [ "sc_terraform" ]
;         }
;         :format_after_save {:lsp_format :fallback}
;     }))

;; TODO: not sure if this git thing is really working
(later-let [_ (add :sindrets/diffview.nvim)
            m (require :diffview)]
    (m.setup {
        :enhanced_diff_hl true
        :file_panel {
            :listing_style :list
        }
        :hooks {
            :diff_buf_win_enter (fn [bufnr winid ctx]
                ;; Turn off cursor line for diffview windows because of bg conflict
                ;; https://github.com/neovim/neovim/issues/9800.
                (tset vim.wo winid :culopt :number)
            )
        }
    })

    ;; TODO: this plugin assigns <Leader>b to close the file browser, which
    ;; conflicts with my buffer submode.
    ;;
    ;; In fact, it messes with a number of <Leader>_ bindings.

    ;; TODO: it'd be cool to just run the `!git remote set-head...` automatically
    ;; if we hit the certain error... or just assume/hardcode master.
    
    (map :n :<Leader>dH ":!git remote set-head -a origin<CR>" {:noremap true :desc "Set origin/HEAD"})
    (map :n :<Leader>dM ":DiffviewOpen origin/HEAD...HEAD --imply-local<CR>" {:noremap true :desc "Diff origin/HEAD"})
    (map :n :<Leader>dw ":DiffviewOpen HEAD --imply-local<CR>" {:noremap true :desc "Working changes"})
    (map :n :<Leader>dc ":DiffviewFileHistory --range=origin/HEAD...HEAD --right-only --no-merges"
         {:noremap true :desc "Diff commits from HEAD"})
    (map :n :<Leader>dC ":DiffviewClose<CR>" {:noremap true :desc "Close"})
    )

;; Clue

(later-let [m (require :mini.clue)]
    (m.setup {
        :triggers [
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
        ]
        :clues [
            ;; MiniClue builtins.
            (m.gen_clues.builtin_completion)
            (m.gen_clues.g)
            (m.gen_clues.marks)
            (m.gen_clues.registers)
            (m.gen_clues.windows)
            (m.gen_clues.z)

            ;; Submenu names.
            {:mode :n :keys :<Leader>f :desc :+Files}
            {:mode :n :keys :<Leader>b :desc :+Buffers}
            {:mode :n :keys :<Leader>w :desc :+Windows}
            {:mode :n :keys :<Leader>l :desc :+Lsp}
            {:mode :n :keys :<Leader>m :desc :+Move} {:mode :x :keys :<Leader>m :desc :+Move}
            ; {:mode :n :keys :<Leader>t :desc :+Tabs}
            {:mode :n :keys :<Leader>d :desc :+Diff}
            {:mode :n :keys :<Leader>s :desc :+Search}
            {:mode :n :keys :<Leader>c :desc :+Copy}

            ;; MiniMove submode.
			{:mode :n :keys :<Leader>mh :postkeys :<Leader>m} {:mode :x :keys :<Leader>mh :postkeys :<Leader>m}
			{:mode :n :keys :<Leader>mj :postkeys :<Leader>m} {:mode :x :keys :<Leader>mj :postkeys :<Leader>m}
			{:mode :n :keys :<Leader>mk :postkeys :<Leader>m} {:mode :x :keys :<Leader>mk :postkeys :<Leader>m}
			{:mode :n :keys :<Leader>ml :postkeys :<Leader>m} {:mode :x :keys :<Leader>ml :postkeys :<Leader>m}

            ;; Buffer submode.
            {:mode :n :keys :<Leader>bn :postkeys :<Leader>b}
            {:mode :n :keys :<Leader>bp :postkeys :<Leader>b}
            {:mode :n :keys :<Leader>bd :postkeys :<Leader>b}

            ;; Brackets submode.
            {:mode :n :keys "[c" :postkeys "[" :desc "Prev change"}
            {:mode :n :keys "]c" :postkeys "]" :desc "Next change"}
            {:mode :n :keys "[C" :postkeys "["}
            {:mode :n :keys "]C" :postkeys "]"}
        ]
        :window {
            :delay 200
            :config {
                :width 36
            }
        }
    })
)

;; Aesthetic stuff

(now-let [_ (add :aktersnurra/no-clown-fiesta.nvim)
          m (require :no-clown-fiesta)
          ;; https://github.com/aktersnurra/no-clown-fiesta.nvim/blob/master/lua/no-clown-fiesta/palette.lua
          palette (require :no-clown-fiesta.palette)]
    (m.setup {
        :type {
            :bold false
        }
    })

    (vim.cmd "colorscheme no-clown-fiesta")

    ; code
    (vim.api.nvim_set_hl 0 "@string.special.symbol" {:link "@string"})
    (vim.api.nvim_set_hl 0 "@string.special.symbol" {:link "@string"})
    (vim.api.nvim_set_hl 0 "@type" {:link :Normal})

    ; (mini.)statusline
    (vim.cmd "highlight! link StatuslineNC Normal")
    (vim.cmd "highlight! link Statusline Comment")
    (vim.cmd "highlight! link MiniStatuslineInactive Comment")

    ; vimdiff
    (vim.api.nvim_set_hl 0 :DiffAdd {:bg "#1b2513"})
    (vim.api.nvim_set_hl 0 :DiffChange {:bg "#1f212e"}) 
    (vim.api.nvim_set_hl 0 :DiffText {:bg "#2f3450"}) 

    ; mini.pick
    (vim.api.nvim_set_hl 0 :MiniPickMatchCurrent {:fg palette.cursor_fg :bg palette.cursor_bg})
    (vim.api.nvim_set_hl 0 :MiniPickMatchMarked {:fg palette.gray_blue})
    (vim.api.nvim_set_hl 0 :MiniPickPreviewLine {:fg palette.cursor_fg :bg palette.cursor_bg})

    ; diagnostic signs
    (vim.api.nvim_set_hl 0 :DiagnosticSignError {:fg palette.error :bg palette.bg})
    (vim.api.nvim_set_hl 0 :DiagnosticSignHint {:bg palette.bg})
    (vim.api.nvim_set_hl 0 :DiagnosticSignInfo {:bg palette.bg})
    (vim.api.nvim_set_hl 0 :DiagnosticSignWarn {:bg palette.bg})
    (vim.api.nvim_set_hl 0 :DiagnosticSignOk {:bg palette.bg})
    )



;; Language specific config

;;; Fennel
; (autocmd :FileType {:pattern ["Fennel"] :command "setlocal ts=4 sw=4"})

