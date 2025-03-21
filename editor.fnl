;; --------------------------------------------------------------------
;; Editor
;;
;; Behavior that impacts the text editing experience within a buffer:
;; intra-file navigation, text manipulation, visualizations, etc.
;;
;; Advanced editor behavior, like LSPs and Treesitter, are in
;; editor-advanced.

;; TODO:
;; - consider highlighting the cursor line in the active window
;;   (using an autogroup)
;; - various copy commands to extract info from/about the buffer
;;      - filename
;;      - relative path
;;      - file contents (over ssh too)
;; - spell checking

; (map :n :cp ":let @\" = expand(\"%\")<CR>" {:noremap true :desc "Copy path"})
; {:mode :n :keys :<Leader>c :desc :+Copy}

(local augroup_module (vim.api.nvim_create_augroup :user_editor {:clear true}))

;; --------------------------------------------------------------------
;; Basics

(set vim.o.scrolloff 3)

(set vim.o.tabstop 4)
(set vim.o.shiftwidth 4)
(set vim.o.softtabstop 4)
(set vim.o.expandtab true)
(set vim.o.spell true)

;; Shift indentation without losing selection.
(vim.keymap.set :x :< :<gv {:noremap true})
(vim.keymap.set :x :> :>gv {:noremap true})

;; Fix Y to work like C & D.
(vim.keymap.set :n :Y :y$ {:noremap true})

;; H / L go to start / end of line instead of screen.
; (vim.keymap.set :n :H :^ {:noremap true}) ; use _ instead
; (vim.keymap.set :n :L :$ {:noremap true}) ; 

;; --------------------------------------------------------------------
;; Buffer navigation

(let [m (require :mini.jump)]
    (m.setup {
        :delay {
            :highlight 50
            :idle_stop 100000000
        }
    })
    (vim.cmd "highlight! link MiniJump Search"))

;; --------------------------------------------------------------------
;; Text manipulation

(let [m (require :mini.comment)]
    (m.setup {}))

(let [m (require :mini.surround)]
    (m.setup))


; (let [m (require :mini.pairs)]
;     (m.setup {}))

; (let [m (require :mini.move)]
;     (m.setup {
;         :mappings {
;             :left       :<Leader>mh
;             :right      :<Leader>ml
;             :down       :<Leader>mj
;             :up         :<Leader>mk
;             :line_left  :<Leader>mh
;             :line_right :<Leader>ml
;             :line_down  :<Leader>mj
;             :line_up    :<Leader>mk
;         }
;     }))

;; --------------------------------------------------------------------
;; Appearance

(let [m (require :mini.cursorword)]
    (m.setup {:delay 50})
    (vim.api.nvim_create_autocmd :FileType {
        :group augroup_module
        :callback
        #(let [ft (. vim.bo $.buf :filetype)]
            ;; Enable for certain file types.
            (tset vim.b $.buf :minicursorword_disable
                (and (not= ft :fennel) (not= ft :ruby))))}))

(let [m (require :mini.indentscope)]
    (m.setup {
        :draw {
            :delay 50
            :animation (m.gen_animation.none)
        }
    })
    ;; TODO: make this a generic thing to add to different plugin loads
    (vim.api.nvim_create_autocmd :FileType {
        :group augroup_module
        :callback
        #(let [ft (. vim.bo $.buf :filetype)]
            ;; Enable for certain file types.
            (tset vim.b $.buf :miniindentscope_disable
                (and (not= ft :fennel) (not= ft :ruby)))
            (when (= ft :fennel)
                (tset vim.b $.buf :miniindentscope_config {:options {:border :top}})))
        }))

(let [m (require :mini.hipatterns)]
    (m.setup {
        :highlighters {
            :fixme {:pattern :FIXME :group :MiniHipatternsFixme }
            :hack {:pattern :HACK :group :MiniHipatternsHack }
            :todo {:pattern :TODO :group :MiniHipatternsTodo }
            :note {:pattern :NOTE :group :MiniHipatternsNote }
            :hex_color (m.gen_highlighter.hex_color)
        }
    }))

;; --------------------------------------------------------------------
;; Completion & snippets

(let [m (require :mini.completion)]
    (m.setup {}))

(let [m (require :mini.snippets)]
    (m.setup {
        :snippets [
            (m.gen_loader.from_file (.. MYVIMRC_ROOT "/snippets/all.json"))
            (m.gen_loader.from_lang)
        ]
        :mappings {
            :expand :<C-s>
        }
    }))

;; --------------------------------------------------------------------
;; Folding

;; https://www.jackfranklin.co.uk/blog/code-folding-in-vim-neovim/
(set vim.opt.foldmethod :expr)
(set vim.opt.foldexpr "v:lua.vim.treesitter.foldexpr()")
(set vim.opt.foldtext "")
(set vim.opt.foldenable true)
(set vim.opt.foldlevel 99)
; (tset vim.opt :foldlevelstart 99)
; (tset vim.opt :foldnestmax 6)
(vim.opt.fillchars:append {:fold  " "})

;; --------------------------------------------------------------------
;; Copy

(local osc52 (require :vim.ui.clipboard.osc52))
(tset vim.g :clipboard {
    :name "OSC 52"
    :copy {
        :+ (osc52.copy :+)
        :* (osc52.copy :*)
    }
    ;; NOTE: do not use osc52 for pasting.
    :paste {
        :+ (fn [])
        :* (fn [])
    }
})

{}

