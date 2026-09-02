local signs = require("scan-o-tron-3000.signs")

local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("scan-o-tron-3000-panel")

local state = {
  bufnr = nil,
  winid = nil,
  prev_winid = nil,
  files = {}, -- [path] = { tree = ..., expanded = { [key] = bool } }
  line_to_node = {}, -- [lnum] = { node = ..., path = ..., key = ... } for jump/toggle on <CR>
}

local function node_key(parent_key, node, index)
  return parent_key .. "|" .. node.type .. ":" .. (index or "") .. ":" .. (node.name or "")
end

local function compute_force_expanded(node, parent_key, out, index)
  local key = node_key(parent_key, node, index)
  if node.state == "fail" or node.state == "errored" then
    out[key] = true
  end
  for i, child in ipairs(node.children) do
    compute_force_expanded(child, key, out, i)
  end
  return out
end

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner = {
  active = false,
  frame = 1,
  timer = nil,
}

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
  local icon_highlights = {} -- { lnum, col_start, col_end, hl_group }

  if spinner.active then
    table.insert(lines, SPINNER_FRAMES[spinner.frame] .. " Running project tests...")
    table.insert(lines, "")
  end

  local function record_icon(depth, icon, node_state)
    local hl_group = signs.HL_GROUPS[node_state]
    if not hl_group then
      return
    end
    local col_start = depth * 2 + 1 -- skip the indent and the "["
    table.insert(icon_highlights, {
      lnum = #lines,
      col_start = col_start,
      col_end = col_start + #icon,
      hl_group = hl_group,
    })
  end

  local paths = vim.tbl_keys(state.files)
  table.sort(paths)

  for _, path in ipairs(paths) do
    local entry = state.files[path]
    local root_key = node_key("", entry.tree)
    local root_icon = icon_for(entry.tree)
    table.insert(lines, string.format("[%s] %s", root_icon, path))
    line_to_node[#lines] = { node = entry.tree, path = path, key = root_key }
    record_icon(0, root_icon, entry.tree.state)

    local function walk(node, depth, parent_key)
      for i, child in ipairs(node.children) do
        local key = node_key(parent_key, child, i)
        local icon = icon_for(child)
        table.insert(lines, string.format("%s[%s] %s", string.rep("  ", depth), icon, child.name))
        line_to_node[#lines] = { node = child, path = path, key = key }
        record_icon(depth, icon, child.state)
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

  vim.api.nvim_buf_clear_namespace(state.bufnr, M.NAMESPACE, 0, -1)
  for _, h in ipairs(icon_highlights) do
    vim.api.nvim_buf_set_extmark(state.bufnr, M.NAMESPACE, h.lnum - 1, h.col_start, {
      end_col = h.col_end,
      hl_group = h.hl_group,
    })
  end
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

local function do_open()
  state.prev_winid = vim.api.nvim_get_current_win()

  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    state.bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[state.bufnr].buftype = "nofile"
    vim.bo[state.bufnr].bufhidden = "hide"
    vim.keymap.set("n", "<CR>", on_confirm, { buffer = state.bufnr, silent = true })
  end

  vim.cmd("botright split")
  state.winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winid, state.bufnr)

  render()
end

function M.toggle()
  if M.is_open() then
    vim.api.nvim_win_close(state.winid, true)
    state.winid = nil
    return
  end

  do_open()
end

function M.open()
  if M.is_open() then
    return
  end

  do_open()
end

-- opts.default_collapsed, if true, starts a BRAND NEW file entry's root
-- collapsed (matching describe blocks' default) instead of expanded --
-- used for project-wide population, where hundreds of files at once would
-- otherwise all show fully open. Only applies the first time a path is
-- registered; a later re-run never overrides an already-set expand state
-- (manual collapse/expand, or a prior failure) purely because of this flag.
function M.update(path, tree, opts)
  opts = opts or {}
  local existing = state.files[path]
  local expanded = existing and existing.expanded or {}

  if not existing and opts.default_collapsed then
    expanded[node_key("", tree)] = false
  end

  local force = compute_force_expanded(tree, "", {})
  for key in pairs(force) do
    expanded[key] = true
  end

  state.files[path] = { tree = tree, expanded = expanded }
  render()
end

-- Toggles the animated "Running project tests..." header shown at the top
-- of the panel while a project-wide run is in flight -- there's no per-file
-- "running" state available for files we don't know about yet (we only
-- learn which files ran once the whole subprocess finishes).
function M.set_project_running(is_running)
  if is_running == spinner.active then
    return
  end
  spinner.active = is_running

  if is_running then
    spinner.frame = 1
    spinner.timer = vim.uv.new_timer()
    spinner.timer:start(
      0,
      100,
      vim.schedule_wrap(function()
        spinner.frame = (spinner.frame % #SPINNER_FRAMES) + 1
        render()
      end)
    )
  else
    if spinner.timer then
      spinner.timer:stop()
      spinner.timer:close()
      spinner.timer = nil
    end
    render()
  end
end

return M
