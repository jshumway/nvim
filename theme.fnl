(local mini_deps (require :mini.deps))

(let [_ (mini_deps.add :aktersnurra/no-clown-fiesta.nvim)
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

    (vim.api.nvim_set_hl 0 :Folded {:bg "#1f212e"}))

{}

