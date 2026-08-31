-- tests/minimal_init.lua
vim.opt.rtp:append(".")
vim.opt.rtp:append(".deps/plenary.nvim")
vim.opt.rtp:append(".deps/nvim-treesitter")

-- Disable swapfiles: multiple spec files load the same fixture buffers in
-- this single headless nvim process, and swapfile creation/cleanup races
-- between them cause intermittent E303/E325 errors unrelated to test logic.
vim.opt.swapfile = false

vim.cmd("runtime! plugin/plenary.vim")
require("nvim-treesitter.configs").setup({ ensure_installed = {}, sync_install = false })
