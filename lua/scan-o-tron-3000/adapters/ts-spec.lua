-- lua/scan-o-tron-3000/adapters/ts-spec.lua
local M = {}

M.name = "ts-spec"
M.filetypes = { "typescript", "typescriptreact" }

function M.is_test_file(path)
  return path:match("%.spec%.tsx?$") ~= nil or path:match("%.test%.tsx?$") ~= nil
end

local QUERY = [[
(call_expression
  function: (identifier) @_fn (#eq? @_fn "describe")
  arguments: (arguments
    (string (string_fragment) @describe.name)
    [(arrow_function) (function_expression)])) @describe.definition

(call_expression
  function: (identifier) @_fn (#any-of? @_fn "it" "test")
  arguments: (arguments
    (string (string_fragment) @test.name)
    [(arrow_function) (function_expression)])) @test.definition
]]

function M.treesitter_query(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, "typescript")
  local tree = parser:parse()[1]
  local root = tree:root()
  local query = vim.treesitter.query.parse("typescript", QUERY)

  local flat = {}
  for _, match, _ in query:iter_matches(root, bufnr, 0, -1, { all = true }) do
    local entry = { type = nil, name = nil, range = nil }
    for id, nodes in pairs(match) do
      local capture_name = query.captures[id]
      for _, node in ipairs(nodes) do
        if capture_name == "describe.definition" then
          entry.type = "describe"
          entry.range = { node:range() }
        elseif capture_name == "test.definition" then
          entry.type = "test"
          entry.range = { node:range() }
        elseif capture_name == "describe.name" or capture_name == "test.name" then
          entry.name = vim.treesitter.get_node_text(node, bufnr)
        end
      end
    end
    if entry.type and entry.range then
      table.insert(flat, entry)
    end
  end

  table.sort(flat, function(a, b)
    if a.range[1] ~= b.range[1] then
      return a.range[1] < b.range[1]
    end
    return a.range[2] < b.range[2]
  end)

  return flat
end

return M
