local config = require("scan-o-tron-3000.config")
local positions = require("scan-o-tron-3000.positions")
local runner = require("scan-o-tron-3000.runner")
local panel = require("scan-o-tron-3000.panel")
local results = require("scan-o-tron-3000.results")

local M = {}

function M.setup(opts)
  config.setup(opts)
end

local function adapter_for_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  for _, adapter in ipairs(config.get().adapters) do
    if adapter.is_test_file(path) then
      return adapter, bufnr, path
    end
  end
  return nil
end

local function leaf_names(node, out)
  out = out or {}
  if node.type == "test" then
    table.insert(out, node.name)
  end
  for _, child in ipairs(node.children) do
    leaf_names(child, out)
  end
  return out
end

local function find_package_json(path)
  return vim.fs.find("package.json", { path = vim.fs.dirname(path), upward = true })[1]
end

local function find_nearest(node, row, best)
  best = best or nil
  if node.range and node.range[1] <= row and row <= node.range[3] then
    best = node
  end
  for _, child in ipairs(node.children) do
    best = find_nearest(child, row, best)
  end
  return best
end

local function run_scope(kind)
  local adapter, bufnr, path = adapter_for_current_buffer()
  if not adapter then
    vim.notify("scan-o-tron-3000: no adapter registered for this file type", vim.log.levels.WARN)
    return
  end

  local tree = positions.discover(bufnr, adapter)
  local package_json_path = find_package_json(path)

  local scope = { kind = kind, path = path, package_json_path = package_json_path }

  if kind == "test" or kind == "suite" then
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local nearest = find_nearest(tree, row)
    if not nearest then
      vim.notify("scan-o-tron-3000: no test or suite found under the cursor", vim.log.levels.WARN)
      return
    end
    scope.kind = nearest.type == "test" and "test" or "suite"
    scope.position = nearest
    scope.scope_leaf_names = leaf_names(nearest)
  else
    scope.scope_leaf_names = leaf_names(tree)
  end

  results.aggregate(tree)
  panel.open()
  runner.run({
    tree = tree,
    adapter = adapter,
    scope = scope,
    on_complete = function()
      panel.update(path, tree)
    end,
  })
  panel.update(path, tree)
end

function M.run_nearest()
  run_scope("test")
end

function M.run_file()
  run_scope("file")
end

function M.run_project()
  run_scope("project")
end

function M.toggle_panel()
  panel.toggle()
end

return M
