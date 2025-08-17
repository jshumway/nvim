(local mini_hipatterns (require :mini.hipatterns))

;; Expects h, s, l in range [0, 1]
(fn hsl [h s l]
    (if (<= s 0) (values l l l)
    :else
        (let [h6 (* 6 h)
              c (* s (- 1 (math.abs (- (* l 2) 1))))
              x (* c (- 1 (math.abs (- (% h6 2) 1))))
              m (- l (* c .5))
              [r g b] (if (< h6 1) [c x 0]
                          (< h6 2) [x c 0]
                          (< h6 3) [0 c x]
                          (< h6 4) [0 x c]
                          (< h6 5) [x 0 c]
                          :else   [c 0 x])]
        (values (+ r m) (+ g m) (+ b m)))))

;; hsl "extended", where h is in [0, 360], s and l are in [0, 100]
(fn hsl/x [h s l] (hsl (/ h 360) (/ s 100) (/ l 100)))

;; hsl "extended", returned as a rgb string in the format #rrggbb.
(fn hsl/xs [h s l]
    (let [(r g b) (hsl/x h s l)]
        (string.format "#%02x%02x%02x" (* r 255) (* g 255) (* b 255))))

;; NOTE: these `h_` functions are taken directly from hlpatterns.lua. They cannot
;; be re-used directly because they are private to that module.
(fn h_always_true [] true)

(fn h_error [msg] (error (.. "(gen_highlighter_hsl_color) " msg) 0))

(fn h_wrap_pattern_with_filter [pattern filter]
    (fn [...] (when (filter ...) pattern)))

(lambda gen_highlighter_hsl_color [?opts]
    (local default_opts {
        :style :full
        :priority 200
        :filter h_always_true
        :inline_text "█"
        :lang :lua
        :fn_name "hsl"
    })
    (local opts (vim.tbl_deep_extend :force default_opts (or ?opts {})))

    (local style opts.style)
    (assert (or (= style :full) (= style :inline) (= style :line)) "invalid value for opts.style")

    (when (and (= style :inline) (= 0 (vim.fn.has :nvim-0.10)))
        (h_error "Style 'inline' in `gen_highlighter.hex_color()` requires Neovim>=0.10."))

    (local pattern
        (if (= opts.lang :lua)
            ;; e.g., hsl(h, s, l)
            (.. opts.fn_name "%(()%s*%d+%s*,%s*%d+%s*,%s*%d+%s*()%)")
            (= opts.lang :fnl)
            ;; e.g., (hsl h s l)
            (.. "%(%s*" opts.fn_name "%s()%s-%d+%s+%d+%s+%d+%s*()%)")
            :else
            (assert "unrecognized opts.lang")))

    (local hl_style (case style :full :bg :line :line :inline :fg _ :bg))
    (var extmark_opts {:priority opts.priority})
    (when (= style :inline)
        (let [priority opts.priority inline_text opts.inline_text]
            (set extmark_opts (fn [_ _ data]
                (local virt_text [[inline_text data.hl_group]])
                {: virt_text : priority :right_gravity false :virt_text_pos :inline}))))

    {
        :pattern (h_wrap_pattern_with_filter pattern opts.filter)
        :group (fn [_ raw_match _]
            (let [(_ _ hs ss ls) (raw_match:find "(%d+).-(%d+).-(%d+)")
                  h (tonumber hs) s (tonumber ss) l (tonumber ls)]
                (when (and (>= h 0) (<= h 360) (>= s 0) (<= s 100) (>= l 0) (<= l 100))
                    (mini_hipatterns.compute_hex_color_group (hsl/xs h s l) hl_style))))
         : extmark_opts
    })

