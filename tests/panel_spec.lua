describe("scan-o-tron-3000.panel", function()
  local panel, positions

  before_each(function()
    package.loaded["scan-o-tron-3000.panel"] = nil
    package.loaded["scan-o-tron-3000.positions"] = nil
    panel = require("scan-o-tron-3000.panel")
    positions = require("scan-o-tron-3000.positions")
  end)

  after_each(function()
    if panel.is_open() then
      panel.toggle()
    end
  end)

  it("is closed by default", function()
    assert.is_false(panel.is_open())
  end)

  it("toggle() opens then closes the panel window", function()
    panel.toggle()
    assert.is_true(panel.is_open())
    panel.toggle()
    assert.is_false(panel.is_open())
  end)

  it("update() renders the file path and its test names once open", function()
    panel.toggle()
    local tree = positions.build_tree({ { type = "test", name = "does a thing", range = { 0, 0, 1, 0 } } })
    tree.children[1].state = "pass"
    panel.update("src/foo.spec.ts", tree)

    local bufnr = vim.api.nvim_win_get_buf(panel.winid())
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    assert.is_true(content:find("foo.spec.ts", 1, true) ~= nil)
    assert.is_true(content:find("does a thing", 1, true) ~= nil)
  end)

  it("auto-expands a file whose tree has a failing test", function()
    panel.toggle()
    local tree = positions.build_tree({ { type = "test", name = "broken", range = { 0, 0, 1, 0 } } })
    tree.children[1].state = "fail"
    panel.update("src/foo.spec.ts", tree)

    local bufnr = vim.api.nvim_win_get_buf(panel.winid())
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    assert.is_true(content:find("broken", 1, true) ~= nil)
  end)

  it("persists manually-expanded state across update() calls with a freshly-built tree", function()
    panel.toggle()

    local function buffer_content()
      local bufnr = vim.api.nvim_win_get_buf(panel.winid())
      return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end

    local function press_enter_on(text)
      local bufnr = vim.api.nvim_win_get_buf(panel.winid())
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local target_lnum
      for i, line in ipairs(lines) do
        if line:find(text, 1, true) then
          target_lnum = i
          break
        end
      end
      assert.is_not_nil(target_lnum)
      vim.api.nvim_win_set_cursor(panel.winid(), { target_lnum, 0 })

      local cr_callback
      for _, km in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if km.lhs == "<CR>" then
          cr_callback = km.callback
          break
        end
      end
      assert.is_not_nil(cr_callback)
      cr_callback()
    end

    local tree1 = positions.build_tree({
      { type = "describe", name = "outer", range = { 0, 0, 5, 0 } },
      { type = "test", name = "inner", range = { 1, 0, 2, 0 } },
    })
    panel.update("src/foo.spec.ts", tree1)

    -- "inner" is nested under "outer", which is collapsed by default (not failing).
    assert.is_true(buffer_content():find("inner", 1, true) == nil)

    -- Manually expand "outer" via the same <CR> keymap the panel wires up.
    press_enter_on("outer")
    assert.is_true(buffer_content():find("inner", 1, true) ~= nil)

    -- Re-run with a *fresh* tree: new table identities, same describe/test names --
    -- exactly what Task 12's runner integration does on every re-run via
    -- positions.discover()/build_tree(). Expand state must survive this.
    local tree2 = positions.build_tree({
      { type = "describe", name = "outer", range = { 0, 0, 5, 0 } },
      { type = "test", name = "inner", range = { 1, 0, 2, 0 } },
    })
    assert.are_not.equal(tree1, tree2)
    panel.update("src/foo.spec.ts", tree2)

    assert.is_true(buffer_content():find("inner", 1, true) ~= nil)
  end)
end)
