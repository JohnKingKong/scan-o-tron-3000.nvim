local signs = require("scan-o-tron-3000.signs")

local M = {}

local state = {
  bufnr = nil,
  winid = nil,
  prev_winid = nil,
  files = {}, -- [path] = { tree = ..., expanded = { [key] = bool } }
  line_to_node = {}, -- [lnum] = { node = ..., path = ..., key = ... } for jump/toggle on <CR>
}

local function node_key(parent_key, node)
  return parent_key .. "|" .. node.type .. ":" .. (node.name or "")
end

local function compute_force_expanded(node, parent_key, out)
  local key = node_key(parent_key, node)
  if node.state == "fail" or node.state == "errored" then
    out[key] = true
  end
  for _, child in ipairs(node.children) do
    compute_force_expanded(child, key, out)
  end
  return out
end

function M.is_open()
  return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

function M.winid()
  return state.winid
end

local function icon_for(node)
  return signs.ICONS[node.state] or " "
end

local function render()
  if not M.is_open() then
    return
  end

  local lines = {}
  local line_to_node = {}

  local paths = vim.tbl_keys(state.files)
  table.sort(paths)

  for _, path in ipairs(paths) do
    local entry = state.files[path]
    local root_key = node_key("", entry.tree)
    table.insert(lines, string.format("[%s] %s", icon_for(entry.tree), path))
    line_to_node[#lines] = { node = entry.tree, path = path, key = root_key }

    local function walk(node, depth, parent_key)
      for _, child in ipairs(node.children) do
        local key = node_key(parent_key, child)
        table.insert(lines, string.format("%s[%s] %s", string.rep("  ", depth), icon_for(child), child.name))
        line_to_node[#lines] = { node = child, path = path, key = key }
        if entry.expanded[key] and #child.children > 0 then
          walk(child, depth + 1, key)
        elseif child.type == "test" and child.message then
          for _, msg_line in ipairs(vim.split(child.message, "\n")) do
            table.insert(lines, string.rep("  ", depth + 1) .. msg_line)
          end
        end
      end
    end

    if entry.expanded[root_key] ~= false then
      walk(entry.tree, 1, root_key)
    end
  end

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
  state.line_to_node = line_to_node
end

local function on_confirm()
  local lnum = vim.api.nvim_win_get_cursor(state.winid)[1]
  local entry = state.line_to_node[lnum]
  if not entry then
    return
  end

  if #entry.node.children > 0 then
    local file_entry = state.files[entry.path]
    file_entry.expanded[entry.key] = not file_entry.expanded[entry.key]
    render()
    return
  end

  if entry.node.range then
    local target_win = state.prev_winid
    if not target_win or not vim.api.nvim_win_is_valid(target_win) then
      target_win = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_set_current_win(target_win)
    vim.cmd.edit(entry.path)
    vim.api.nvim_win_set_cursor(target_win, { entry.node.range[1] + 1, 0 })
  end
end

function M.toggle()
  if M.is_open() then
    vim.api.nvim_win_close(state.winid, true)
    state.winid = nil
    return
  end

  state.prev_winid = vim.api.nvim_get_current_win()

  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    state.bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[state.bufnr].buftype = "nofile"
    vim.bo[state.bufnr].bufhidden = "hide"
    vim.keymap.set("n", "<CR>", on_confirm, { buffer = state.bufnr, silent = true })
  end

  vim.cmd("vsplit")
  state.winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winid, state.bufnr)

  render()
end

function M.update(path, tree)
  local existing = state.files[path]
  local expanded = existing and existing.expanded or {}

  local force = compute_force_expanded(tree, "", {})
  for key in pairs(force) do
    expanded[key] = true
  end

  state.files[path] = { tree = tree, expanded = expanded }
  render()
end

return M
