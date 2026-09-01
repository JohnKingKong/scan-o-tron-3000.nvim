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

  it("open() opens the panel if closed", function()
    assert.is_false(panel.is_open())
    panel.open()
    assert.is_true(panel.is_open())
  end)

  it("open() is idempotent -- calling it again while already open does not close it", function()
    panel.open()
    assert.is_true(panel.is_open())
    local winid = panel.winid()

    panel.open()

    assert.is_true(panel.is_open())
    assert.are.equal(winid, panel.winid())
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

  it("renders the fail icon on the file-level row when the root node's state is fail", function()
    panel.toggle()
    local tree = positions.build_tree({ { type = "test", name = "broken", range = { 0, 0, 1, 0 } } })
    tree.children[1].state = "fail"
    -- Mirrors what results.aggregate() now does: roll the failure up onto the
    -- file-type root node, not just describe nodes.
    tree.state = "fail"
    panel.update("src/foo.spec.ts", tree)

    local bufnr = vim.api.nvim_win_get_buf(panel.winid())
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local file_row
    for _, line in ipairs(lines) do
      if line:find("foo.spec.ts", 1, true) then
        file_row = line
        break
      end
    end
    assert.is_not_nil(file_row)
    assert.is_true(file_row:find("[✗]", 1, true) ~= nil)
  end)

  it("colors each row's icon with the highlight group matching its node state", function()
    panel.toggle()
    local signs = require("scan-o-tron-3000.signs")

    local tree = positions.build_tree({
      { type = "test", name = "passes", range = { 0, 0, 1, 0 } },
      { type = "test", name = "fails", range = { 2, 0, 3, 0 } },
    })
    tree.children[1].state = "pass"
    tree.children[2].state = "fail"
    tree.state = "fail"
    panel.update("src/foo.spec.ts", tree)

    local bufnr = vim.api.nvim_win_get_buf(panel.winid())
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local function lnum_of(text)
      for i, line in ipairs(lines) do
        if line:find(text, 1, true) then
          return i
        end
      end
    end

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, panel.NAMESPACE, 0, -1, { details = true })
    local hl_by_lnum = {}
    for _, mark in ipairs(marks) do
      hl_by_lnum[mark[2] + 1] = mark[4].hl_group
    end

    assert.are.equal(signs.HL_GROUPS.fail, hl_by_lnum[lnum_of("foo.spec.ts")])
    assert.are.equal(signs.HL_GROUPS.pass, hl_by_lnum[lnum_of("passes")])
    assert.are.equal(signs.HL_GROUPS.fail, hl_by_lnum[lnum_of("fails")])
  end)

  it("clears previous icon highlights on re-render instead of accumulating them", function()
    panel.toggle()

    local tree = positions.build_tree({ { type = "test", name = "flaky", range = { 0, 0, 1, 0 } } })
    tree.children[1].state = "fail"
    tree.state = "fail"
    panel.update("src/foo.spec.ts", tree)
    panel.update("src/foo.spec.ts", tree)

    local bufnr = vim.api.nvim_win_get_buf(panel.winid())
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, panel.NAMESPACE, 0, -1, {})
    -- One highlight for the file row, one for the "flaky" test row -- not doubled.
    assert.are.equal(2, #marks)
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

  it("does not alias expand state between same-named sibling nodes", function()
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

    -- Two top-level `describe` blocks with the SAME name, each with a distinctly
    -- named test child, so we can tell which sibling's expand state applied.
    local function build_duplicate_named_tree()
      return positions.build_tree({
        { type = "describe", name = "edge cases", range = { 0, 0, 2, 0 } },
        { type = "test", name = "case A", range = { 1, 0, 1, 5 } },
        { type = "describe", name = "edge cases", range = { 3, 0, 5, 0 } },
        { type = "test", name = "case B", range = { 4, 0, 4, 5 } },
      })
    end

    local tree1 = build_duplicate_named_tree()
    panel.update("src/foo.spec.ts", tree1)

    -- Both same-named describes start collapsed (neither is failing).
    assert.is_true(buffer_content():find("case A", 1, true) == nil)
    assert.is_true(buffer_content():find("case B", 1, true) == nil)

    -- Expand only the FIRST "edge cases" describe (the one containing "case A").
    press_enter_on("edge cases")
    assert.is_true(buffer_content():find("case A", 1, true) ~= nil)
    assert.is_true(buffer_content():find("case B", 1, true) == nil)

    -- Re-run with a fresh, structurally-equivalent tree (new table identities).
    local tree2 = build_duplicate_named_tree()
    assert.are_not.equal(tree1, tree2)
    panel.update("src/foo.spec.ts", tree2)

    -- Expand state must still apply to only the first sibling, not both.
    assert.is_true(buffer_content():find("case A", 1, true) ~= nil)
    assert.is_true(buffer_content():find("case B", 1, true) == nil)
  end)
end)
