-- Detect OS
if vim.fn.exists('g:os') == 0 then
    local is_windows = vim.fn.has("win64") == 1 or vim.fn.has("win32") == 1 or vim.fn.has("win16") == 1
    if vim.fn.has("win64") + vim.fn.has("win32") + vim.fn.has("win16") > 0 then
        vim.g.os = "windows"
    else
        local uname_output = vim.fn.system('uname')
        vim.g.os = string.gsub(uname_output, '\n', '')
    end
end

-- Add nvim config directory to lua path.
PATH_PATTERN = "(.*/)(.*)"
if vim.g.os == "windows" then
    PATH_PATTERN = "(.*\\)(.*)"
end
MYVIMRC_ROOT = string.gsub(vim.env.MYVIMRC, PATH_PATTERN, "%1")

package.path = MYVIMRC_ROOT .. "?.lua;" .. package.path

-- bootstrap Fennel.
fennel = require("fennel.fennel").install()
-- Add ~/.config/nvim to fennel path.
fennel.path = MYVIMRC_ROOT .. "?.fnl;" .. fennel.path
fv = require("fennel.view")
-- Load the config entrypoint.
require("main")
