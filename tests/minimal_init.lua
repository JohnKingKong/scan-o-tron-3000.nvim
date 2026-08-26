-- tests/minimal_init.lua
vim.opt.rtp:append(".")
vim.opt.rtp:append(".deps/plenary.nvim")
vim.opt.rtp:append(".deps/nvim-treesitter")

vim.cmd("runtime! plugin/plenary.vim")
require("nvim-treesitter.configs").setup({ ensure_installed = {}, sync_install = false })
