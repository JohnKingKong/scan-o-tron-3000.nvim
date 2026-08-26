-- tests/positions_spec.lua
describe("scan-o-tron-3000.positions", function()
  local positions

  before_each(function()
    package.loaded["scan-o-tron-3000.positions"] = nil
    positions = require("scan-o-tron-3000.positions")
  end)

  it("returns a file root with no children for an empty list", function()
    local tree = positions.build_tree({})
    assert.are.equal("file", tree.type)
    assert.are.same({}, tree.children)
  end)

  it("nests a test inside its enclosing describe", function()
    local flat = {
      { type = "describe", name = "outer", range = { 0, 0, 10, 1 } },
      { type = "test", name = "does a thing", range = { 1, 2, 3, 3 } },
    }
    local tree = positions.build_tree(flat)
    assert.are.equal(1, #tree.children)
    local describe_node = tree.children[1]
    assert.are.equal("describe", describe_node.type)
    assert.are.equal("outer", describe_node.name)
    assert.are.equal(1, #describe_node.children)
    assert.are.equal("does a thing", describe_node.children[1].name)
    assert.are.equal("test", describe_node.children[1].type)
  end)

  it("nests describes within describes to arbitrary depth", function()
    local flat = {
      { type = "describe", name = "outer", range = { 0, 0, 20, 1 } },
      { type = "describe", name = "inner", range = { 1, 2, 10, 3 } },
      { type = "test", name = "leaf", range = { 2, 4, 4, 5 } },
    }
    local tree = positions.build_tree(flat)
    local outer = tree.children[1]
    local inner = outer.children[1]
    assert.are.equal("inner", inner.name)
    assert.are.equal("leaf", inner.children[1].name)
  end)

  it("treats siblings that don't overlap as siblings, not nested", function()
    local flat = {
      { type = "test", name = "first", range = { 0, 0, 1, 1 } },
      { type = "test", name = "second", range = { 2, 0, 3, 1 } },
    }
    local tree = positions.build_tree(flat)
    assert.are.equal(2, #tree.children)
    assert.are.equal("first", tree.children[1].name)
    assert.are.equal("second", tree.children[2].name)
  end)

  it("every node starts with state 'idle'", function()
    local flat = { { type = "test", name = "t", range = { 0, 0, 1, 1 } } }
    local tree = positions.build_tree(flat)
    assert.are.equal("idle", tree.children[1].state)
  end)
end)
