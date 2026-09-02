local results = require("scan-o-tron-3000.results")
local signs = require("scan-o-tron-3000.signs")

local M = {}

local in_flight = {}

-- A tree-less non-project scope (e.g. a run triggered from a file tree
-- sidebar rather than an open buffer) has no tree.bufnr to key on -- falls
-- back to the scope's own path instead, so two different tree-less runs at
-- different paths don't block each other, while the same path still does.
local function key_for(tree, scope)
  if scope.kind == "project" then
    return "project"
  end
  return tree and tree.bufnr or scope.path
end

function M.is_running(key)
  return in_flight[key] == true
end

-- `tree` is optional: a project-wide run triggered from a buffer that isn't
-- itself a recognized test file has no single tree to track (results for
-- every file are applied separately via on_complete's by_file breakdown), so
-- every tree-touching step here is skipped when it's nil.
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

  if tree then
    results.set_running(tree, scope.scope_leaf_names)
    signs.render(tree.bufnr, tree)
  end

  local ok, err = pcall(function()
    local cmd = adapter.build_command(scope)
    local cwd = scope.package_json_path and vim.fs.dirname(scope.package_json_path) or nil

    system_fn(cmd, { text = true, cwd = cwd }, function(obj)
      in_flight[key] = nil

      local parse_ok, parsed, by_file = pcall(adapter.parse_results, obj.stdout or "")
      if tree then
        results.apply(tree, parse_ok and parsed or {}, scope.scope_leaf_names)
        results.aggregate(tree)
      end

      -- vim.system's on_exit runs in a fast-event (libuv) context, where
      -- nvim_buf_*/nvim_win_* calls are illegal; defer them to the main loop.
      vim.schedule(function()
        if tree then
          signs.render(tree.bufnr, tree)
        end

        if opts.on_complete then
          opts.on_complete(parse_ok and by_file or nil)
        end
      end)
    end)
  end)

  if not ok then
    in_flight[key] = nil

    if tree then
      results.apply(tree, {}, scope.scope_leaf_names)
      results.aggregate(tree)
      signs.render(tree.bufnr, tree)
    end

    vim.notify("scan-o-tron-3000: failed to start test run: " .. tostring(err), vim.log.levels.ERROR)

    if opts.on_complete then
      opts.on_complete()
    end
  end
end

return M
