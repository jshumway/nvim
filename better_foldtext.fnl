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

        ;; TODO: this is great for for examples like:
        ;; (local aoeu { ... }) => `(local aoeu ... )`
        ;; but not for sig { => `sig ... }`

        ;; I feel like the "right" decision is to to whatever the end string will
        ;; be and only keep delimiters that are "correctly paired" on each side...
        ;; Though there is, ofc, the possibility that that could be misleading.
        ;;
        ;; sig { => `sig { << ... >> }`
        ;;
        ;; But that's honestly pretty... idk, overkill

        ;; Okay, I think the algorithm needs to be something like:
        ;; - going through the foldstart line, record the position of each
        ;;   opening delimiter; when encountering a closing delimiter, pop
        ;;   the last closing delimiter
        ;; - do the same, but with closing delimiters and moving backwards through
        ;;   the foldend line
        ;; - compare the two stacks going from bottom to top... delimiters must
        ;;   match (opening to closing)
        ;; - as soon as we hit non-matching delimiters:
        ;;      - for the start line, we want to show everything up to but not
        ;;        including the first non-matching delimiter
        ;;      - for the end line, I guess it is the same, but starting from
        ;;        the back, unless we're in lisp mode, in which case we want to
        ;;        show up to and including the previous matching delimiter
        ;;
        ;; That's a rough outline of it.

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
