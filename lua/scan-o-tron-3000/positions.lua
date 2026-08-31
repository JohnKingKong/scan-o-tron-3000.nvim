local M = {}

local function point_lte(a_row, a_col, b_row, b_col)
  if a_row ~= b_row then
    return a_row < b_row
  end
  return a_col <= b_col
end

local function contains(outer, inner)
  local o = outer.range
  local i = inner.range
  return point_lte(o[1], o[2], i[1], i[2]) and point_lte(i[3], i[4], o[3], o[4])
end

function M.build_tree(flat_positions)
  local root = { type = "file", name = nil, range = nil, children = {} }

  -- stack of currently-open ancestor nodes, root always at the bottom
  local stack = { root }

  for _, raw in ipairs(flat_positions) do
    local node = {
      type = raw.type,
      name = raw.name,
      range = raw.range,
      children = {},
      state = "idle",
    }

    -- pop any stack entries that don't contain this node
    while #stack > 1 and not contains(stack[#stack], node) do
      table.remove(stack)
    end

    table.insert(stack[#stack].children, node)
    table.insert(stack, node)
  end

  return root
end

function M.discover(bufnr, adapter)
  local flat = adapter.treesitter_query(bufnr)
  local tree = M.build_tree(flat)
  tree.bufnr = bufnr
  return tree
end

return M
