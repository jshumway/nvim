(local mini_statusline (require :mini.statusline))
(local mini_icons (require :mini.icons))

(fn get_ft_icon [filetype] (mini_icons.get :filetype filetype))

(fn section_fileinfo [args]
    (var filetype vim.bo.filetype)
    (when (not= filetype "")
        (set filetype (.. (get_ft_icon filetype) " " filetype)))
    filetype)

(fn active []
    (local (mode mode_hl) (mini_statusline.section_mode {:trunc_width 120}))
    (local git (mini_statusline.section_git {:trunc_width 40}))
    (local diff (mini_statusline.section_diff {:trunc_width 75}))
    (local diagnostics (mini_statusline.section_diagnostics {:trunc_width 75}))
    (local lsp (mini_statusline.section_lsp {:trunc_width 75}))
    (local filename (mini_statusline.section_filename {:trunc_width 140}))
    (local fileinfo (section_fileinfo {:trunc_width 120}))
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

