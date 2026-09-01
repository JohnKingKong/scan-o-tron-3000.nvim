-- tests/minimal_init.lua
vim.opt.rtp:append(".")
vim.opt.rtp:append(".deps/plenary.nvim")
vim.opt.rtp:append(".deps/nvim-treesitter")

-- Disable swapfiles: multiple spec files load the same fixture buffers in
-- this single headless nvim process, and swapfile creation/cleanup races
-- between them cause intermittent E303/E325 errors unrelated to test logic.
vim.opt.swapfile = false

vim.cmd("runtime! plugin/plenary.vim")

-- nvim-treesitter.configs was removed in the installed nvim-treesitter version;
-- the typescript parser itself works fine via vim.treesitter.* builtins, this
-- call is vestigial. pcall it so a missing module doesn't print a banner into
-- every `make test` run.
pcall(function()
  require("nvim-treesitter.configs").setup({ ensure_installed = {}, sync_install = false })
end)
