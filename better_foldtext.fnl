(fn extract_treesitter_highlights [result s line col]
    (var substring "")
    (var hl "")

    (fn emit []
        (table.insert result [substring (.. "@" hl)])
        (set substring ""))

    (for [i 1 (length s)]
        (let [buf_col (+ col i -1)
              ts_results (vim.treesitter.get_captures_at_pos 0 line buf_col)
              ts_result (. ts_results (length ts_results))
              hl_cmp (?. ts_result :capture)]
            (when (and hl_cmp (not= hl hl_cmp))
                (emit)
                (set hl hl_cmp))
            (set substring (.. substring (s:sub i i)))))

    (emit))

(fn custom_foldtext []
    (let [(foldstart foldend) (values vim.v.foldstart vim.v.foldend)
          start_line_raw (vim.fn.getline foldstart)
          start_line (start_line_raw:gsub "\t" (string.rep " " vim.o.tabstop))
          end_line_raw (vim.fn.getline foldend)
          end_line (vim.trim end_line_raw)
          lines_hidden (- foldend foldstart)
          end_line_leading_spaces (length (or (end_line_raw:match "^(%s+)") ""))]

        (local result [])
        (extract_treesitter_highlights result start_line (- foldstart 1) 0)

        (let [num_results (length result)
              [last_substring last_hl] (. result num_results)
              ss_length (length last_substring)
              last_char (last_substring:sub ss_length ss_length)]
            (when (or (= last_char "(") (= last_char "[") (= last_char "{"))
                (tset result num_results [
                    (-> (last_substring:sub 1 (- ss_length 1)) (vim.trim))
                    last_hl
                ])))

        (each [_ v (ipairs [[" << " :Comment] [(tostring lines_hidden) :Delimiter] [" >> " :Comment]])]
            (table.insert result v))

        (extract_treesitter_highlights result
            (if vim.b.better_foldtext_lisp_mode
                (end_line:sub (length end_line) (length end_line))
            :else
                end_line)
            (- foldend 1)
            end_line_leading_spaces)

        result))

(set _G.better_foldtext_foldtext custom_foldtext)

{
}
