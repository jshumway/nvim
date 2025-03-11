-- Add nvim config directory to lua path.
local os_name = vim.loop.os_uname().sysname
PATH_PATTERN = "(.*?/)(.*)"
if os_name == "Windows_NT" then
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
