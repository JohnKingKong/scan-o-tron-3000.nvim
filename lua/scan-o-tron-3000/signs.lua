local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("scan-o-tron-3000")

M.ICONS = {
  running = "",
  pass = "",
  fail = "",
  errored = "?",
}

M.HL_GROUPS = {
  running = "ScanOTronRunning",
  pass = "ScanOTronPass",
  fail = "ScanOTronFail",
  errored = "ScanOTronErrored",
}

vim.api.nvim_set_hl(0, "ScanOTronPass", { link = "DiagnosticOk", default = true })
vim.api.nvim_set_hl(0, "ScanOTronFail", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "ScanOTronRunning", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "ScanOTronErrored", { link = "DiagnosticWarn", default = true })

local function each_node(node, fn)
  if node.type ~= "file" then
    fn(node)
  end
  for _, child in ipairs(node.children) do
    each_node(child, fn)
  end
end

function M.render(bufnr, tree)
  vim.api.nvim_buf_clear_namespace(bufnr, M.NAMESPACE, 0, -1)

  each_node(tree, function(node)
    if node.state == "idle" then
      return
    end
    vim.api.nvim_buf_set_extmark(bufnr, M.NAMESPACE, node.range[1], 0, {
      sign_text = M.ICONS[node.state] or "?",
      sign_hl_group = M.HL_GROUPS[node.state] or "ScanOTronErrored",
    })
  end)
end

return M
