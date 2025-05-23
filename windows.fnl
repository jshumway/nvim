(local mini_misc (require :mini.misc))

{
    :last_window :<C-w>w
    :vertical_split ":vsplit<CR>"
    :horizontal_split ":split<CR>"
    :close_window :<C-w>c

    :rebalance_splits :<C-w>=
    :exchange_windows :<C-w>x

    :focus_window_left :<C-w>h
    :focus_window_down :<C-w>j
    :focus_window_up :<C-w>k
    :focus_window_right :<C-w>l

    :toggle_zoom_window mini_misc.zoom
}
