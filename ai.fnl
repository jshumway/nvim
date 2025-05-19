(local Terminal (-> (require :toggleterm.terminal) (. :Terminal)))

(fn create_goose_terminal []
    (Terminal:new {
        :display_name :goose
        :cmd "pay goose"
        :direction :vertical
        :count 0
    }))

{
    : create_goose_terminal
}

