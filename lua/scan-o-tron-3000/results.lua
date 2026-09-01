local M = {}

local function each_test_node(node, fn)
  if node.type == "test" then
    fn(node)
  end
  for _, child in ipairs(node.children) do
    each_test_node(child, fn)
  end
end

function M.apply(tree, parsed_by_name, scope_leaf_names)
  local in_scope = {}
  for _, name in ipairs(scope_leaf_names or {}) do
    in_scope[name] = true
  end

  each_test_node(tree, function(node)
    local result = parsed_by_name[node.name]
    if result then
      node.state = result.status == "skip" and "idle" or result.status
      node.message = result.message
    elseif in_scope[node.name] then
      node.state = "errored"
    end
  end)
end

local PRIORITY = { running = 4, fail = 3, errored = 3, pass = 2, idle = 1 }

function M.aggregate(node)
  if node.type == "test" then
    return node.state
  end

  local best = "idle"
  for _, child in ipairs(node.children) do
    local child_state = M.aggregate(child)
    if PRIORITY[child_state] > PRIORITY[best] then
      best = child_state
    end
  end

  if PRIORITY[best] == 3 then
    best = "fail"
  end

  if node.type == "describe" then
    node.state = best
  end
  return best
end

function M.set_running(tree, scope_leaf_names)
  local in_scope = {}
  for _, name in ipairs(scope_leaf_names) do
    in_scope[name] = true
  end

  each_test_node(tree, function(node)
    if in_scope[node.name] then
      node.state = "running"
    end
  end)

  M.aggregate(tree)
end

return M
