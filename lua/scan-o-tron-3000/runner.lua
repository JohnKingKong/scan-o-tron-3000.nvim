local results = require("scan-o-tron-3000.results")
local signs = require("scan-o-tron-3000.signs")

local M = {}

local in_flight = {}

local function key_for(tree, scope)
  return scope.kind == "project" and "project" or tree.bufnr
end

function M.is_running(key)
  return in_flight[key] == true
end

function M.run(opts)
  local tree = opts.tree
  local adapter = opts.adapter
  local scope = opts.scope
  local system_fn = opts.system_fn or vim.system

  local key = key_for(tree, scope)
  if in_flight[key] then
    vim.notify("scan-o-tron-3000: a run is already in progress for this scope", vim.log.levels.WARN)
    return
  end

  in_flight[key] = true

  results.set_running(tree, scope.scope_leaf_names)
  signs.render(tree.bufnr, tree)

  local ok, err = pcall(function()
    local cmd = adapter.build_command(scope)

    system_fn(cmd, { text = true }, function(obj)
      in_flight[key] = nil

      local parse_ok, parsed = pcall(adapter.parse_results, obj.stdout or "")
      results.apply(tree, parse_ok and parsed or {}, scope.scope_leaf_names)
      results.aggregate(tree)
      signs.render(tree.bufnr, tree)

      if opts.on_complete then
        opts.on_complete()
      end
    end)
  end)

  if not ok then
    in_flight[key] = nil

    results.apply(tree, {}, scope.scope_leaf_names)
    results.aggregate(tree)
    signs.render(tree.bufnr, tree)

    vim.notify("scan-o-tron-3000: failed to start test run: " .. tostring(err), vim.log.levels.ERROR)

    if opts.on_complete then
      opts.on_complete()
    end
  end
end

return M
