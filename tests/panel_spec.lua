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
end)
