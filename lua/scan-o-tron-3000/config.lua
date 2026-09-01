local M = {}

local DEFAULTS = {
  adapters = { require("scan-o-tron-3000.adapters.ts-spec") },
}

local state = vim.deepcopy(DEFAULTS)

function M.setup(opts)
  opts = opts or {}
  state = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts)
end

function M.get()
  return state
end

return M
