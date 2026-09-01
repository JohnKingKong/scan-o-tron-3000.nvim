if vim.g.loaded_scan_o_tron_3000 then
  return
end
vim.g.loaded_scan_o_tron_3000 = true

local SUBCOMMANDS = {
  ["run-nearest"] = function()
    require("scan-o-tron-3000").run_nearest()
  end,
  ["run-file"] = function()
    require("scan-o-tron-3000").run_file()
  end,
  ["run-project"] = function()
    require("scan-o-tron-3000").run_project()
  end,
  ["toggle-panel"] = function()
    require("scan-o-tron-3000").toggle_panel()
  end,
}

vim.api.nvim_create_user_command("ScanOTron", function(cmd_opts)
  local subcommand = SUBCOMMANDS[cmd_opts.args]
  if not subcommand then
    vim.notify("scan-o-tron-3000: unknown subcommand '" .. cmd_opts.args .. "'", vim.log.levels.ERROR)
    return
  end
  subcommand()
end, {
  nargs = 1,
  complete = function()
    return vim.tbl_keys(SUBCOMMANDS)
  end,
  desc = "Run or inspect Scan-o-tron-3000 tests: run-nearest | run-file | run-project | toggle-panel",
})
