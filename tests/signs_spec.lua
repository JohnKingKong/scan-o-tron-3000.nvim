-- tests/signs_spec.lua
describe("scan-o-tron-3000.signs", function()
  local signs, positions

  before_each(function()
    package.loaded["scan-o-tron-3000.signs"] = nil
    package.loaded["scan-o-tron-3000.positions"] = nil
    signs = require("scan-o-tron-3000.signs")
    positions = require("scan-o-tron-3000.positions")
  end)

  local function make_bufnr()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "", "", "", "" })
    return bufnr
  end

  it("places no signs for idle nodes", function()
    local bufnr = make_bufnr()
    local tree = positions.build_tree({ { type = "test", name = "t", range = { 0, 0, 1, 0 } } })
    signs.render(bufnr, tree)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, signs.NAMESPACE, 0, -1, {})
    assert.are.equal(0, #marks)
  end)

  it("places one sign per non-idle node at its start row", function()
    local bufnr = make_bufnr()
    local tree = positions.build_tree({ { type = "test", name = "t", range = { 2, 0, 3, 0 } } })
    tree.children[1].state = "pass"
    signs.render(bufnr, tree)

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, signs.NAMESPACE, 0, -1, { details = true })
    assert.are.equal(1, #marks)
    assert.are.equal(2, marks[1][2]) -- row
    -- nvim pads single-width sign_text glyphs with a trailing space to fill
    -- the 2-cell sign column, so compare after trimming.
    assert.are.equal(signs.ICONS.pass, vim.trim(marks[1][4].sign_text))
    assert.are.equal(signs.HL_GROUPS.pass, marks[1][4].sign_hl_group)
  end)

  it("re-rendering clears previous signs first", function()
    local bufnr = make_bufnr()
    local tree = positions.build_tree({ { type = "test", name = "t", range = { 0, 0, 1, 0 } } })
    tree.children[1].state = "pass"
    signs.render(bufnr, tree)
    signs.render(bufnr, tree)

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, signs.NAMESPACE, 0, -1, {})
    assert.are.equal(1, #marks)
  end)
end)
