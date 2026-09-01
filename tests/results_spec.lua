-- tests/results_spec.lua
describe("scan-o-tron-3000.results", function()
  local results, positions

  before_each(function()
    package.loaded["scan-o-tron-3000.results"] = nil
    package.loaded["scan-o-tron-3000.positions"] = nil
    results = require("scan-o-tron-3000.results")
    positions = require("scan-o-tron-3000.positions")
  end)

  local function make_tree()
    return positions.build_tree({
      { type = "describe", name = "outer", range = { 0, 0, 10, 1 } },
      { type = "test", name = "passes", range = { 1, 0, 2, 0 } },
      { type = "test", name = "fails", range = { 3, 0, 4, 0 } },
      { type = "test", name = "never reports", range = { 5, 0, 6, 0 } },
    })
  end

  describe("apply", function()
    it("sets pass/fail state on matched leaf nodes", function()
      local tree = make_tree()
      results.apply(tree, {
        passes = { status = "pass" },
        fails = { status = "fail", message = "expected 1 to be 2" },
      }, { "passes", "fails", "never reports" })

      local outer = tree.children[1]
      assert.are.equal("pass", outer.children[1].state)
      assert.are.equal("fail", outer.children[2].state)
      assert.are.equal("expected 1 to be 2", outer.children[2].message)
    end)

    it("marks in-scope leaves that never reported as errored", function()
      local tree = make_tree()
      results.apply(tree, { passes = { status = "pass" } }, { "passes", "fails", "never reports" })

      local outer = tree.children[1]
      assert.are.equal("errored", outer.children[3].state)
    end)

    it("leaves out-of-scope nodes untouched", function()
      local tree = make_tree()
      results.apply(tree, { passes = { status = "pass" } }, { "passes" })

      local outer = tree.children[1]
      assert.are.equal("idle", outer.children[2].state)
      assert.are.equal("idle", outer.children[3].state)
    end)
  end)

  describe("aggregate", function()
    it("marks a describe as fail if any child failed", function()
      local tree = make_tree()
      results.apply(tree, { passes = { status = "pass" }, fails = { status = "fail" } }, { "passes", "fails" })
      results.aggregate(tree)
      assert.are.equal("fail", tree.children[1].state)
    end)

    it("marks a describe as pass if all children passed", function()
      local tree = positions.build_tree({
        { type = "describe", name = "outer", range = { 0, 0, 5, 1 } },
        { type = "test", name = "passes", range = { 1, 0, 2, 0 } },
      })
      results.apply(tree, { passes = { status = "pass" } }, { "passes" })
      results.aggregate(tree)
      assert.are.equal("pass", tree.children[1].state)
    end)

    it("marks a describe as fail (not errored) when its only bad child is errored", function()
      local tree = make_tree()
      results.apply(tree, { passes = { status = "pass" } }, { "passes", "never reports" })
      results.aggregate(tree)
      local outer = tree.children[1]
      assert.are.equal("errored", outer.children[3].state)
      assert.are.equal("fail", outer.state)
    end)

    it("marks a describe as deterministically fail with mixed fail/errored siblings", function()
      local tree = make_tree()
      results.apply(
        tree,
        { passes = { status = "pass" }, fails = { status = "fail" } },
        { "passes", "fails", "never reports" }
      )
      results.aggregate(tree)
      local outer = tree.children[1]
      assert.are.equal("fail", outer.children[2].state)
      assert.are.equal("errored", outer.children[3].state)
      assert.are.equal("fail", outer.state)
    end)

    it("also sets state on the file-type root node, not just describe nodes", function()
      local tree = make_tree()
      results.apply(
        tree,
        { passes = { status = "pass" }, fails = { status = "fail" } },
        { "passes", "fails", "never reports" }
      )
      results.aggregate(tree)
      assert.are.equal("file", tree.type)
      assert.are.equal("fail", tree.state)
    end)
  end)

  describe("set_running", function()
    it("marks scoped leaves and their ancestors as running", function()
      local tree = make_tree()
      results.set_running(tree, { "passes" })
      local outer = tree.children[1]
      assert.are.equal("running", outer.children[1].state)
      assert.are.equal("running", outer.state)
      assert.are.equal("idle", outer.children[2].state)
    end)
  end)
end)
