-- Add ~/.config/nvim to lua path.
package.path = string.gsub(vim.env.MYVIMRC, "(.*/)(.*)", "%1") .. "?.lua;" .. package.path
-- bootstrap Fennel.
fennel = require("fennel/fennel").install()
-- Add ~/.config/nvim to fennel path.
fennel.path = string.gsub(vim.env.MYVIMRC, "(.*/)(.*)", "%1") .. "?.fnl;" .. fennel.path
fv = require("fennel/view")
-- Load the config entrypoint.
require("main")
