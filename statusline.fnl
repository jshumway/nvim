(local mini_statusline (require :mini.statusline))

(fn active []
    (local (mode mode_hl) (mini_statusline.section_mode {:trunc_width 120}))
    (local git (mini_statusline.section_git {:trunc_width 40}))
    (local diff (mini_statusline.section_diff {:trunc_width 75}))
    (local diagnostics (mini_statusline.section_diagnostics {:trunc_width 75}))
    (local lsp (mini_statusline.section_lsp {:trunc_width 75}))
    (local filename (mini_statusline.section_filename {:trunc_width 140}))
    (local fileinfo (mini_statusline.section_fileinfo {:trunc_width 120}))
    (local location (mini_statusline.section_location {:trunc_width 75}))
    (local search (mini_statusline.section_searchcount {:trunc_width 75}))

    (mini_statusline.combine_groups [
        {:hl mode_hl :strings [mode]}
        {:hl :MiniStatuslineDevinfo :strings [git diff diagnostics lsp]}
        "%<"
        {:hl :MiniStatuslineFilename :strings [filename]}
        "%="
        {:hl :MiniStatuslineFileinfo :strings [fileinfo]}
        {:hl mode_hl :strings [search location]}
    ]))


(fn inactive []
    (if (= vim.bo.filetype :no-neck-pain)
        ""
    :else
        "%#MiniStatuslineInactive#%F%="))

{
    : active
    : inactive
}

