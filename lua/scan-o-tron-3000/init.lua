local config = require("scan-o-tron-3000.config")
local positions = require("scan-o-tron-3000.positions")
local runner = require("scan-o-tron-3000.runner")
local panel = require("scan-o-tron-3000.panel")
local results = require("scan-o-tron-3000.results")
local signs = require("scan-o-tron-3000.signs")

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

-- Project-wide runs aren't tied to any one file, so unlike the single-file
-- scopes this prefers the current buffer's adapter (matching existing
-- behavior when it happens to be a test file) but falls back to whatever's
-- configured first rather than refusing to run.
local function pick_project_adapter(path)
  for _, adapter in ipairs(config.get().adapters) do
    if path ~= "" and adapter.is_test_file(path) then
      return adapter
    end
  end
  return config.get().adapters[1]
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

local function find_package_json_from_dir(dir)
  return vim.fs.find("package.json", { path = dir, upward = true })[1]
end

local function find_package_json(path)
  return find_package_json_from_dir(vim.fs.dirname(path))
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

-- Populates every OTHER tested file's gutter marks and panel entry after a
-- project-wide run -- `runner.run` only ever tracks the single tree it was
-- given (the buffer open when the run was triggered, if any), so without
-- this, a project-wide run's results for every other file are silently
-- discarded. Each file starts collapsed (unless failing) since a project run
-- can easily touch hundreds of files at once.
local function populate_project_results(adapter, current_path, by_file)
  for file_path, file_results in pairs(by_file) do
    if vim.fs.normalize(file_path) ~= vim.fs.normalize(current_path) then
      local ok, err = pcall(function()
        local file_bufnr = vim.fn.bufadd(file_path)
        vim.fn.bufload(file_bufnr)

        local file_tree = positions.discover(file_bufnr, adapter)
        local file_leaf_names = leaf_names(file_tree)
        results.apply(file_tree, file_results, file_leaf_names)
        results.aggregate(file_tree)
        signs.render(file_bufnr, file_tree)
        panel.update(file_path, file_tree, { default_collapsed = true })
      end)
      if not ok then
        vim.notify(
          "scan-o-tron-3000: failed to show results for " .. file_path .. ": " .. tostring(err),
          vim.log.levels.WARN
        )
      end
    end
  end
end

-- Counts pass/fail/total across every file's results, for the project-run
-- completion notify -- there's no other way to tell a long project-wide run
-- actually finished besides watching the current file's icon change.
local function count_results(by_file)
  local total, passed, failed = 0, 0, 0
  for _, file_results in pairs(by_file) do
    for _, result in pairs(file_results) do
      total = total + 1
      if result.status == "pass" then
        passed = passed + 1
      elseif result.status == "fail" then
        failed = failed + 1
      end
    end
  end
  return total, passed, failed
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

-- Deliberately does NOT require the current buffer to be a test file --
-- project-wide runs every test in the project regardless of what you
-- happen to have open.
function M.run_project()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local adapter = pick_project_adapter(path)
  if not adapter then
    vim.notify("scan-o-tron-3000: no adapter registered", vim.log.levels.WARN)
    return
  end

  local is_spec_file = path ~= "" and adapter.is_test_file(path)
  local start_dir = (path ~= "" and vim.fs.dirname(path)) or vim.fn.getcwd()
  local package_json_path = find_package_json_from_dir(start_dir)

  local tree = is_spec_file and positions.discover(bufnr, adapter) or nil
  local scope = {
    kind = "project",
    path = path,
    package_json_path = package_json_path,
    scope_leaf_names = tree and leaf_names(tree) or {},
  }

  if tree then
    results.aggregate(tree)
  end

  panel.open()
  panel.set_project_running(true)
  vim.notify("scan-o-tron-3000: running project tests...", vim.log.levels.INFO)

  runner.run({
    tree = tree,
    adapter = adapter,
    scope = scope,
    on_complete = function(by_file)
      if tree then
        panel.update(path, tree, { default_collapsed = true })
      end
      if by_file then
        populate_project_results(adapter, path, by_file)
        local total, passed, failed = count_results(by_file)
        vim.notify(
          string.format(
            "scan-o-tron-3000: project run complete -- %d passed, %d failed (%d total)",
            passed,
            failed,
            total
          ),
          failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
        )
      end
      panel.set_project_running(false)
    end,
  })

  if tree then
    panel.update(path, tree, { default_collapsed = true })
  end
end

function M.toggle_panel()
  panel.toggle()
end

return M
